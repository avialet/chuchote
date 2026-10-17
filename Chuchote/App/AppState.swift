import AppKit
import AVFoundation
import ChuchoteCore
import Observation

/// Etat partage des vues : l'historique (recherche, sections, ligne choisie), les compteurs du jour,
/// les autorisations de la carte d'accueil et les langues proposees.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let database: AppDatabase
    let store: DictationStore

    private(set) var dictations: [Dictation] = []
    private(set) var sections: [DictationSection] = []
    private(set) var countToday = 0
    private(set) var wordsToday = 0
    var query = "" { didSet { reload() } }
    var selectedId: Int64?
    /// Ligne qui vient d'etre recopiee (petit retour << Copie >>).
    private(set) var copiedId: Int64?

    private(set) var microphone: MicrophoneAccess = .notDetermined
    private(set) var accessibilityTrusted = false
    /// Langues prises en charge par le moteur (identifiants `fr_FR`), chargees a la demande.
    private(set) var supportedLocales: [String] = []

    @ObservationIgnored private var copiedTimer: Task<Void, Never>?
    @ObservationIgnored private var localesLoaded = false
    @ObservationIgnored private var activation: (any NSObjectProtocol)?
    #if DEBUG
    /// Mode capture : autorisations et langue figees.
    @ObservationIgnored private(set) var setupFrozen = false
    private(set) var languageOverride: LanguageReadiness?
    #endif

    private init() {
        do {
            database = try AppDatabase.open()
        } catch {
            fatalError("Impossible d'ouvrir la base \(AppDatabase.defaultURL.path) : \(error)")
        }
        store = DictationStore(database: database)
        DictationController.registerDefaults()
        refreshSetup()
        // Autorisations accordees dans les Reglages Systeme : re-verifiees au retour dans l'app.
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.runOnMainThread {
                self?.refreshSetup()
                self?.reload()
            }
        }
    }

    // MARK: - Historique

    var isHistoryEmpty: Bool { query.isEmpty && dictations.isEmpty }

    func reload() {
        let previous = dictations.compactMap(\.id)
        do {
            dictations = try store.search(query)
            countToday = try store.countToday()
            wordsToday = try store.wordsToday()
        } catch {
            NSLog("Chuchote : lecture de l'historique impossible : \(error)")
            dictations = []
        }
        sections = DictationSection.group(dictations)
        selectedId = ListSelection.keep(selectedId, in: dictations.compactMap(\.id), previous: previous)
    }

    var selected: Dictation? { dictations.first { $0.id == selectedId } }

    func moveSelection(by delta: Int) {
        selectedId = ListSelection.move(in: sections.flatMap(\.items).compactMap(\.id), from: selectedId, by: delta)
    }

    /// Recopie le texte dans le presse-papiers, avec un bref << Copie >> sur la ligne.
    func copy(_ dictation: Dictation) {
        Paster.copy(dictation.text)
        selectedId = dictation.id
        copiedId = dictation.id
        copiedTimer?.cancel()
        copiedTimer = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            self?.copiedId = nil
        }
    }

    func delete(_ dictation: Dictation) {
        guard let id = dictation.id else { return }
        _ = try? store.delete(id: id)
        reload()
    }

    func clearHistory() {
        _ = try? store.deleteAll()
        reload()
    }

    /// Applique le nombre de dictees a conserver.
    func applyHistoryLimit(_ limit: HistoryLimit) {
        if let keep = limit.keepLast { _ = try? store.prune(keepLast: keep) }
        reload()
    }

    // MARK: - Autorisations et langue

    func refreshSetup() {
        #if DEBUG
        if setupFrozen { return }
        #endif
        microphone = Self.microphoneAccess()
        accessibilityTrusted = Paster.isTrusted
    }

    var language: LanguageReadiness {
        #if DEBUG
        if let languageOverride { return languageOverride }
        #endif
        return DictationController.shared.engineStatus.readiness
    }

    /// Points a regler ; `directPaste` vient de l'@AppStorage de la vue (observe).
    func setupSteps(directPaste: Bool) -> [SetupStep] {
        SetupChecklist.steps(microphone: microphone, accessibilityTrusted: accessibilityTrusted,
                             directPaste: directPaste, language: language)
    }

    func requestMicrophone() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshSetup()
        }
    }

    /// Ouvre la page des Reglages Systeme (`Privacy_Microphone`, `Privacy_Accessibility`).
    static func openPrivacySettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func microphoneAccess() -> MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Langues du moteur, chargees une fois.
    func loadLocales() {
        guard !localesLoaded else { return }
        localesLoaded = true
        Task {
            supportedLocales = await AppleTranscriber.supportedLocales().map { LanguageChoices.canonical($0.identifier) }
        }
    }

    var currentLocale: String {
        UserDefaults.standard.string(forKey: DictationController.Keys.locale) ?? DictationController.defaultLocale
    }

    /// Change la langue de dictee et prepare le moteur de la nouvelle langue.
    func setLocale(_ identifier: String) {
        guard identifier != currentLocale else { return }
        UserDefaults.standard.set(identifier, forKey: DictationController.Keys.locale)
        DictationController.shared.reloadEngine()
    }

    #if DEBUG
    /// Mode capture : autorisations, langue et langues proposees figees (ni demande, ni moteur).
    func freezeSetup(microphone: MicrophoneAccess, accessibilityTrusted: Bool, language: LanguageReadiness,
                     locales: [String]) {
        setupFrozen = true
        localesLoaded = true
        self.microphone = microphone
        self.accessibilityTrusted = accessibilityTrusted
        languageOverride = language
        supportedLocales = locales
    }
    #endif
}

extension DictationController.EngineStatus {
    var readiness: LanguageReadiness {
        switch self {
        case .preparing: .preparing
        case .ready: .ready
        case .needsInstall: .needsInstall
        case .installing(let fraction): .installing(fraction)
        case .unsupported: .unsupported
        case .failed(let message): .failed(message)
        }
    }
}
