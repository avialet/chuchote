import AppKit
import ChuchoteCore
import Observation
import os
import VialetKit

/// Orchestre une dictee : raccourci -> micro -> moteur -> Polish -> presse-papiers et collage ->
/// historique, et l'etat que montre le panneau d'ecoute.
@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        case listening(since: Date)
        case writing
        case done(pasted: Bool)
        case failed(String)
    }

    /// Etat du moteur de la langue courante (pour l'accueil et les Reglages).
    enum EngineStatus: Equatable {
        case preparing
        case ready
        case needsInstall
        case installing(Double)
        case unsupported
        case failed(String)
    }

    /// Cles UserDefaults (valeurs par defaut posees par `registerDefaults()`).
    enum Keys {
        static let locale = Brand.key("Locale")
        static let frenchTypography = Brand.key("FrenchTypography")
        static let directPaste = Brand.key("DirectPaste")
        static let keepHistory = Brand.key("KeepHistory")
        /// Nombre de dictees conservees (`HistoryLimit.rawValue`, 0 : toutes).
        static let historyLimit = Brand.key("HistoryLimit")
        /// Affichage pendant la dictee (`ListeningStyle.rawValue`) : goutte d'encoche ou pilule en bas.
        static let listeningStyle = Brand.key("ListeningStyle")
        /// Texte en direct dans la goutte.
        static let liveText = Brand.key("LiveText")
    }

    nonisolated static let defaultLocale = "fr_FR"
    /// Frequence des blocs envoyes au moteur (celle que prefere le moteur Apple).
    nonisolated static let sampleRate: Double = 16_000
    /// Delai maximal de transcription apres la fin de l'ecoute.
    @ObservationIgnored var transcriptionTimeout: Duration = .seconds(15)
    /// Maintien plus long : relachement probablement perdu, le maintien devient un verrouillage.
    static let holdLimit: Duration = .seconds(120)
    /// Panneau d'ecoute : pilule 360 x 76 et sa marge d'ombre.
    static let pillSize = CGSize(width: 360, height: 76)
    static let shadowMargin: CGFloat = 32

    static let shared = DictationController(audio: Microphone(),
                                            makeTranscriber: { AppleTranscriber(locale: $0, liveText: $1) },
                                            store: DictationStore(database: AppState.shared.database),
                                            deliversText: true)

    private(set) var phase: Phase = .idle
    /// Niveau du micro 0-1, lisse.
    private(set) var level: Double = 0
    /// Ecoute verrouillee (appui bref) plutot que maintenue.
    private(set) var isLocked = false
    private(set) var engineStatus: EngineStatus = .preparing
    /// Incremente apres chaque dictee enregistree (rafraichir l'historique).
    private(set) var historyVersion = 0
    /// Derniere latence relachement -> collage (ou copie).
    private(set) var lastLatency: Duration?
    /// Dernier texte ecrit (apres Polish).
    private(set) var lastText: String?
    /// Texte montre dans la goutte : l'apercu pendant la parole, puis le texte ecrit.
    private(set) var liveText = ""
    /// Affichage de la dictee en cours (lu au debut de chaque dictee).
    private(set) var style: ListeningStyle = .defaultValue
    /// La goutte montre le texte en direct (lu au debut de chaque dictee).
    private(set) var showsLiveText = true
    /// Mode capture : pose figee du blob (secondes) ; nil : anime.
    var fixedBlobTime: Double?

    @ObservationIgnored private var gesture = HotKeyGesture()
    @ObservationIgnored private let audio: any AudioSource
    /// Moteur pour une langue, avec ou sans apercu en direct.
    @ObservationIgnored private let makeTranscriber: (Locale, Bool) -> any Transcriber
    @ObservationIgnored private var transcriber: (any Transcriber)?
    @ObservationIgnored private var transcriberLocale: Locale?
    @ObservationIgnored private var transcriberLive = false
    @ObservationIgnored private let store: DictationStore?
    @ObservationIgnored private let deliversText: Bool
    @ObservationIgnored private var panel: FloatingPanelController<ListeningPanel>?
    @ObservationIgnored private var drop: DropPanelController?
    #if DEBUG
    /// Reglages imposes (mode capture) ; nil : ceux de l'utilisateur.
    @ObservationIgnored var styleOverride: ListeningStyle?
    @ObservationIgnored var liveTextOverride: Bool?
    #endif
    /// Jeton de la dictee en cours : tout travail d'une dictee precedente l'ignore.
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var pipelineStarted = false
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var timers: [Task<Void, Never>] = []
    @ObservationIgnored private var target: NSRunningApplication?
    @ObservationIgnored private var listenedFor: TimeInterval = 0
    @ObservationIgnored private var releasedAt: ContinuousClock.Instant?
    @ObservationIgnored private var keyMonitors: [Any] = []
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private let logger = Logger(subsystem: Brand.identity.bundleIdentifier, category: "latence")

    init(audio: any AudioSource, makeTranscriber: @escaping (Locale, Bool) -> any Transcriber,
         store: DictationStore?, deliversText: Bool) {
        self.audio = audio
        self.makeTranscriber = makeTranscriber
        self.store = store
        self.deliversText = deliversText
        let size = CGSize(width: Self.pillSize.width + 2 * Self.shadowMargin,
                          height: Self.pillSize.height + 2 * Self.shadowMargin)
        panel = FloatingPanelController(size: size, takesFocus: false, placement: .bottom) { [unowned self] in
            ListeningPanel(controller: self)
        }
        drop = DropPanelController(controller: self)
        audio.onLevel = { [weak self] level in self?.level = level }
        audio.onInterruption = { [weak self] in self?.microphoneInterrupted() }
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.locale: defaultLocale,
            Keys.frenchTypography: true,
            Keys.directPaste: true,
            Keys.keepHistory: true,
            Keys.historyLimit: HistoryLimit.defaultValue.rawValue,
            Keys.listeningStyle: ListeningStyle.defaultValue.rawValue,
            Keys.liveText: true,
        ])
    }

    /// Branche le raccourci, prepare le micro et le moteur (moteur chaud).
    func start() {
        Self.registerDefaults()
        HotKeyController.shared.start(action: { [weak self] in self?.keyPressed() },
                                      onRelease: { [weak self] in self?.keyReleased() })
        // Relachement perdu possible pendant la veille ou une autre session.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.runOnMainThread { self?.resetKey() }
            })
        }
        (audio as? Microphone)?.prepare()
        reloadEngine()
    }

    // MARK: - Commandes

    func keyPressed() { handle(gesture.press(at: Self.now())) }
    func keyReleased() { handle(gesture.release(at: Self.now())) }
    /// Echap ou bouton du panneau : annule l'ecoute ou la transcription.
    func cancel() { handle(gesture.cancel()) }

    /// Menu << Dicter >> : ecoute verrouillee, ou fin de l'ecoute verrouillee en cours.
    func toggleLockedDictation() {
        let time = Self.now()
        handle(gesture.press(at: time))
        handle(gesture.release(at: time))
    }

    /// Langue changee (Reglages) : nouveau moteur, prepare tout de suite.
    func reloadEngine() {
        transcriber = nil
        transcriberLocale = nil
        prepareEngine()
    }

    /// Affichage ou texte en direct changes (Reglages) : le moteur suit (apercu ou non) s'il le faut.
    func displaySettingsChanged() {
        guard currentTranscriberIsStale else { return }
        prepareEngine()
    }

    /// Reglages d'affichage de la prochaine dictee.
    private var preferredStyle: ListeningStyle {
        #if DEBUG
        if let styleOverride { return styleOverride }
        #endif
        return ListeningStyle(stored: UserDefaults.standard.string(forKey: Keys.listeningStyle))
    }

    private var prefersLiveText: Bool {
        #if DEBUG
        if let liveTextOverride { return liveTextOverride }
        #endif
        return UserDefaults.standard.bool(forKey: Keys.liveText)
    }

    /// L'apercu ne sert qu'au texte en direct de la goutte : sans lui, pas de second analyseur.
    private var wantsPreview: Bool { preferredStyle == .drop && prefersLiveText }

    /// Telecharge les ressources de la langue courante, puis prepare le moteur.
    func installLanguage() {
        let locale = Self.currentLocale
        engineStatus = .installing(0)
        Task {
            do {
                try await AppleTranscriber.installAssets(for: locale) { [weak self] fraction in
                    if case .installing = self?.engineStatus { self?.engineStatus = .installing(fraction) }
                }
                prepareEngine()
            } catch {
                engineStatus = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated static var currentLocale: Locale {
        Locale(identifier: UserDefaults.standard.string(forKey: Keys.locale) ?? defaultLocale)
    }

    // MARK: - Geste

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func handle(_ action: HotKeyGesture.Action) {
        switch action {
        case .none: break
        case .startListening: begin()
        case .finish: finishListening()
        case .cancel: abort()
        }
        isLocked = gesture.state == .locked
    }

    private func resetKey() {
        gesture.resetKey()
        isLocked = gesture.state == .locked
    }

    // MARK: - Deroule

    private func begin() {
        session += 1
        let id = session
        clearTimers()
        work?.cancel()
        pipelineStarted = false
        releasedAt = nil
        target = NSWorkspace.shared.frontmostApplication
        level = 0
        liveText = ""
        if phase == .idle {
            // Le panneau deja ouvert (dictee enchainee) garde son affichage.
            style = preferredStyle
            showsLiveText = prefersLiveText
        }
        phase = .listening(since: Date())
        showPanel()
        installKeyMonitors()
        schedule(after: Self.holdLimit) { [weak self] in
            guard let self, id == self.session, case .holding = self.gesture.state else { return }
            self.resetKey()
        }
        Task { [weak self] in
            guard let self else { return }
            let allowed = await self.audio.authorize()
            guard id == self.session else { return }
            guard allowed else {
                self.fail("Micro refus\u{00E9} (R\u{00E9}glages Syst\u{00E8}me)")
                return
            }
            // Ecoute deja finie pendant la demande d'autorisation : rien a ecrire.
            guard self.gesture.isListening else { return }
            self.startPipeline(id)
        }
    }

    private func startPipeline(_ id: Int) {
        if case .needsInstall = engineStatus {
            fail("Langue \u{00E0} installer (R\u{00E9}glages)")
            return
        }
        let engine = currentTranscriber()
        let audioStream: AsyncStream<AudioChunk>
        do {
            audioStream = try audio.start(sampleRate: Self.sampleRate)
        } catch {
            fail(error.localizedDescription)
            return
        }
        pipelineStarted = true
        let output = engine.transcribe(audioStream)
        work = Task { [weak self] in
            var buffer = TranscriptBuffer()
            do {
                for try await transcript in output {
                    buffer.add(transcript)
                    if let self, id == self.session, self.showsLiveText {
                        self.liveText = LiveText.tail(buffer.live, maxCharacters: Self.liveTextLimit)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self?.transcriptionFailed(id, error)
                return
            }
            await self?.deliver(id, text: buffer.text)
        }
    }

    private func finishListening() {
        guard case .listening(let since) = phase else { return }
        let id = session
        releasedAt = .now
        listenedFor = Date().timeIntervalSince(since)
        audio.stop()
        guard pipelineStarted else {
            // Fin avant l'ouverture du micro (autorisation en cours) : rien a ecrire.
            gesture.finished()
            close()
            return
        }
        phase = .writing
        schedule(after: transcriptionTimeout) { [weak self] in
            guard let self, id == self.session, self.phase == .writing else { return }
            self.work?.cancel()
            self.gesture.finished()
            self.fail("Transcription trop longue")
        }
    }

    /// Fin du texte : mise au propre, presse-papiers, collage, historique.
    private func deliver(_ id: Int, text: String) async {
        guard id == session else { return }
        if case .listening = phase {
            // Le moteur s'est arrete avant la fin de l'ecoute (micro perdu) : on garde ce qui est dit.
            audio.stop()
            _ = gesture.cancel()
        }
        removeKeyMonitors()
        clearTimers()
        gesture.finished()
        isLocked = false
        let defaults = UserDefaults.standard
        let localeID = (transcriberLocale ?? Self.currentLocale).identifier
        let polished = Polish.apply(text, locale: localeID,
                                    frenchTypography: defaults.bool(forKey: Keys.frenchTypography))
        guard !polished.isEmpty else {
            close()
            return
        }
        var pasted = false
        lastText = polished
        liveText = polished
        if deliversText {
            Paster.copy(polished)
            if defaults.bool(forKey: Keys.directPaste) && Paster.isTrusted {
                try? await Task.sleep(for: .milliseconds(60))
                // Echap (ou nouvelle dictee) pendant l'attente : rien a coller ni a enregistrer.
                guard id == session else { return }
                pasted = Paster.simulatePaste()
            }
            if let releasedAt {
                let latency = ContinuousClock.now - releasedAt
                lastLatency = latency
                let ms = Int(latency.components.seconds * 1000 + latency.components.attoseconds / 1_000_000_000_000_000)
                logger.notice("relachement -> \(pasted ? "collage" : "copie", privacy: .public) : \(ms) ms (parole \(self.listenedFor, format: .fixed(precision: 1)) s, \(Dictation.wordCount(polished)) mots)")
            }
            if defaults.bool(forKey: Keys.keepHistory), let store {
                let dictation = Dictation(text: polished, duration: listenedFor, locale: localeID,
                                          targetApp: target?.localizedName)
                if (try? store.insert(dictation)) != nil {
                    if let keep = HistoryLimit(stored: defaults.integer(forKey: Keys.historyLimit)).keepLast {
                        _ = try? store.prune(keepLast: keep)
                    }
                    historyVersion += 1
                }
            }
        }
        guard id == session else { return }
        phase = .done(pasted: pasted)
        // << Colle >> : bref (un peu plus quand la goutte montre le texte) ; << Copie : Cmd-V >> reste
        // le temps d'etre lu.
        let showsText = style == .drop && showsLiveText
        let hold: Duration = pasted ? .milliseconds(showsText ? 1000 : 600) : .milliseconds(1600)
        schedule(after: hold) { [weak self] in
            guard let self, id == self.session else { return }
            self.close()
        }
    }

    /// Micro perdu en pleine ecoute (peripherique change sans reprise possible).
    private func microphoneInterrupted() {
        guard case .listening = phase else { return }
        fail("Micro interrompu")
    }

    private func transcriptionFailed(_ id: Int, _ error: any Error) {
        guard id == session else { return }
        gesture.finished()
        fail("Transcription impossible")
        logger.error("transcription : \(error.localizedDescription, privacy: .public)")
    }

    /// Echap, bouton annuler : tout s'arrete, rien n'est ecrit.
    private func abort() {
        session += 1
        work?.cancel()
        work = nil
        audio.stop()
        close()
    }

    private func fail(_ message: String) {
        // Nouveau jeton : le travail en cours (texte partiel compris) est ignore.
        session += 1
        let id = session
        work?.cancel()
        work = nil
        audio.stop()
        removeKeyMonitors()
        clearTimers()
        // L'ecoute s'arrete : le geste revient au repos (le relachement a venir est ignore).
        if gesture.isListening { _ = gesture.cancel() }
        isLocked = false
        phase = .failed(message)
        if !panelIsVisible { showPanel() }
        schedule(after: .milliseconds(2600)) { [weak self] in
            guard let self, id == self.session else { return }
            self.close()
        }
    }

    /// Masque le panneau (fondu), puis revient au repos.
    private func close() {
        let id = session
        removeKeyMonitors()
        clearTimers()
        level = 0
        hidePanel()
        // Le contenu s'efface en 0,12 s (pilule comme goutte) : la goutte vide finit de remonter.
        schedule(after: .milliseconds(150)) { [weak self] in
            guard let self, id == self.session else { return }
            self.phase = .idle
        }
    }

    // MARK: - Moteur

    /// Longueur maximale du texte en direct (environ trois lignes et demie de goutte).
    static let liveTextLimit = 240

    private var currentTranscriberIsStale: Bool {
        transcriber == nil || transcriberLocale != Self.currentLocale || transcriberLive != wantsPreview
    }

    private func currentTranscriber() -> any Transcriber {
        if let transcriber, !currentTranscriberIsStale { return transcriber }
        let locale = Self.currentLocale
        let live = wantsPreview
        let made = makeTranscriber(locale, live)
        transcriber = made
        transcriberLocale = locale
        transcriberLive = live
        return made
    }

    // MARK: - Panneau

    private var panelIsVisible: Bool { panel?.isVisible == true || drop?.isVisible == true }

    private func showPanel() {
        switch style {
        case .drop: drop?.show()
        case .pill: panel?.show()
        }
    }

    private func hidePanel() {
        panel?.hide()
        drop?.hide()
    }

    private func prepareEngine() {
        let engine = currentTranscriber()
        guard let apple = engine as? AppleTranscriber else {
            engineStatus = .ready
            return
        }
        engineStatus = .preparing
        Task {
            switch await AppleTranscriber.assetState(for: apple.locale) {
            case .unsupported:
                engineStatus = .unsupported
            case .needsInstall:
                engineStatus = .needsInstall
            case .installed:
                do {
                    try await apple.prepare()
                    engineStatus = .ready
                } catch {
                    engineStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Echap

    /// Echap pendant l'ecoute et l'ecriture : moniteur global (exige l'Accessibilite) et local
    /// (fenetre de l'app au premier plan). Sans Accessibilite, le bouton du panneau reste.
    private func installKeyMonitors() {
        guard keyMonitors.isEmpty else { return }
        let escape: UInt16 = 53
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == escape { MainActor.runOnMainThread { self?.cancel() } }
        }) {
            keyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == escape else { return event }
            MainActor.runOnMainThread { self?.cancel() }
            return nil
        }) {
            keyMonitors.append(local)
        }
    }

    private func removeKeyMonitors() {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors.removeAll()
    }

    // MARK: - Minuteries

    private func schedule(after delay: Duration, _ body: @escaping @MainActor () -> Void) {
        timers.append(Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            body()
        })
    }

    private func clearTimers() {
        timers.forEach { $0.cancel() }
        timers.removeAll()
    }
}

#if DEBUG
// MARK: - Mode capture

/// Moteur du mode capture : l'apercu tout de suite, puis rien (l'ecriture dure).
struct SnapshotTranscriber: Transcriber {
    let preview: String

    func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<Transcript, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Transcript, any Error>.makeStream()
        continuation.yield(Transcript(text: preview, isFinal: false, isPreview: true))
        let task = Task {
            for await _ in audio {}
            try? await Task.sleep(for: .seconds(60))
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}

/// Source figee : aucun micro, un niveau constant (pose stable du blob).
@MainActor
final class FrozenAudio: AudioSource {
    var onLevel: ((Double) -> Void)?
    var onInterruption: (() -> Void)?
    let level: Double
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    init(level: Double) { self.level = level }

    func authorize() async -> Bool { true }

    func start(sampleRate: Double) throws -> AsyncStream<AudioChunk> {
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        self.continuation = continuation
        onLevel?(level)
        return stream
    }

    func stop() {
        continuation?.finish()
        continuation = nil
    }
}

extension DictationController {
    /// Controleur du mode capture : FakeTranscriber lent (l'ecriture dure), niveau fige, rien de colle.
    static func snapshot(style: ListeningStyle = .pill) -> DictationController {
        let controller = DictationController(
            audio: FrozenAudio(level: 0.62),
            makeTranscriber: { _, _ in SnapshotTranscriber(preview: snapshotPreview) },
            store: nil, deliversText: false)
        controller.fixedBlobTime = 2.4
        controller.styleOverride = style
        controller.liveTextOverride = true
        return controller
    }

    /// Texte en direct fictif (apercu brut, sans majuscule ni ponctuation finale) et texte ecrit.
    static let snapshotPreview = "bonjour Claire je te confirme notre rendez-vous de jeudi \u{00E0} 10 h 30 peux-tu apporter le dossier du projet et les chiffres du trimestre"
    static let snapshotFinal = "Bonjour Claire, je te confirme notre rendez-vous de jeudi \u{00E0} 10\u{00A0}h\u{00A0}30. Peux-tu apporter le dossier du projet et les chiffres du trimestre\u{202F}? Merci et \u{00E0} bient\u{00F4}t."

    /// Fenetre de la goutte (mode capture).
    var dropWindow: NSWindow? { drop?.nsWindow }
    var dropGeometry: NotchGeometry? { drop?.geometry }
    var dropHitRect: CGRect { drop?.hitRect ?? .zero }

    /// Amene la goutte au texte ecrit et colle.
    func snapshotDone() async {
        await snapshotWriting()
        clearTimers()
        removeKeyMonitors()
        // Nouveau jeton : la fin du travail annule ne livre rien (ni ne ferme la goutte).
        session += 1
        work?.cancel()
        liveText = Self.snapshotFinal
        phase = .done(pasted: true)
        try? await Task.sleep(for: .milliseconds(500))
    }

    /// Amene le panneau en ecoute maintenue (minuteur a 0:04 ; 0:09 pour la goutte, qui a deja du texte).
    func snapshotListening() async {
        if phase == .idle {
            handle(gesture.press(at: 1_000))
            phase = .listening(since: Date().addingTimeInterval(style == .drop ? -9 : -4))
        }
        try? await Task.sleep(for: .milliseconds(style == .drop ? 700 : 400))
    }

    /// Amene le panneau en ecriture (relachement apres un maintien).
    func snapshotWriting() async {
        await snapshotListening()
        handle(gesture.release(at: 1_004))
        try? await Task.sleep(for: .milliseconds(400))
    }
}
#endif
