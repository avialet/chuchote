import AVFoundation
import ChuchoteCore
import Speech

/// Moteur Apple (Speech, macOS 26) : `SpeechAnalyzer` + `SpeechTranscriber(locale:preset: .transcription)`.
/// Moteur chaud : une session (module + analyseur prepare) attend la prochaine dictee ; elle est
/// remplacee en arriere-plan apres chaque usage. Le modele reste charge le temps du processus.
/// `liveText` : un second analyseur, `.progressiveTranscription`, lit le meme audio et emet des apercus
/// (`Transcript.isPreview`) pendant la parole ; il s'arrete a la fin de l'audio. Le texte colle vient
/// toujours du preset `.transcription`. Deux analyseurs et non deux modules sur un meme analyseur :
/// ainsi assemble, l'apercu n'arrivait parfois qu'a la fin de l'audio (mesure, 0.2.0).
final class AppleTranscriber: Transcriber {
    let locale: Locale
    let liveText: Bool
    private let pool: SessionPool

    init(locale: Locale, liveText: Bool = false) {
        self.locale = locale
        self.liveText = liveText
        self.pool = SessionPool(locale: locale, liveText: liveText)
    }

    /// Prepare la prochaine session (chargement du modele). A appeler au lancement.
    func prepare() async throws {
        try await pool.refill()
    }

    func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<Transcript, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Transcript, any Error>.makeStream()
        let pool = pool
        let task = Task {
            do {
                let session = try await pool.take()
                try await session.run(audio: audio) { continuation.yield($0) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            // Session suivante, pour la prochaine dictee.
            try? await pool.refill()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: - Langues et ressources

    enum AssetState: Equatable, Sendable {
        /// Langue non prise en charge par le moteur.
        case unsupported
        /// Prise en charge, ressources a telecharger.
        case needsInstall
        /// Pret.
        case installed
    }

    /// Locale du moteur equivalente a `locale` (fr -> fr_FR), nil si non prise en charge.
    static func supportedLocale(for locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    static func assetState(for locale: Locale) async -> AssetState {
        guard SpeechTranscriber.isAvailable, let supported = await supportedLocale(for: locale) else {
            return .unsupported
        }
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == supported.identifier(.bcp47) }) { return .installed }
        let module = SpeechTranscriber(locale: supported, preset: .transcription)
        return await AssetInventory.status(forModules: [module]) == .installed ? .installed : .needsInstall
    }

    /// Telecharge et installe les ressources de `locale` ; `progress` recoit 0-1 (sur le MainActor).
    static func installAssets(for locale: Locale,
                              progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard let supported = await supportedLocale(for: locale) else { return }
        // Les deux presets de la dictee : texte et apercu en direct.
        let modules = [SpeechTranscriber(locale: supported, preset: .transcription),
                       SpeechTranscriber(locale: supported, preset: .progressiveTranscription)]
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else { return }
        let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
            let fraction = p.fractionCompleted
            Task { @MainActor in progress(fraction) }
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
        await progress(1)
    }
}

/// Analyseur prepare, son module et son format d'entree.
private struct Stage: Sendable {
    let module: SpeechTranscriber
    let analyzer: SpeechAnalyzer
    let format: AVAudioFormat

    static func make(locale: Locale, preset: SpeechTranscriber.Preset) async throws -> Stage {
        let module = SpeechTranscriber(locale: locale, preset: preset)
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        let analyzer = SpeechAnalyzer(modules: [module], options: options)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw EngineError.noAudioFormat
        }
        try await analyzer.prepareToAnalyze(in: format)
        return Stage(module: module, analyzer: analyzer, format: format)
    }
}

/// Session prete : l'analyseur du texte (`.transcription`) et, en option, celui de l'apercu.
private struct Session: Sendable {
    let main: Stage
    let live: Stage?

    static func make(locale: Locale, liveText: Bool) async throws -> Session {
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let main = try await Stage.make(locale: resolved, preset: .transcription)
        // Apercu facultatif : s'il ne se prepare pas, la dictee marche sans.
        let live = liveText ? try? await Stage.make(locale: resolved, preset: .progressiveTranscription) : nil
        return Session(main: main, live: live)
    }

    /// Lit `audio` jusqu'a sa fin, finalise, et emet chaque resultat : les apercus pendant la parole,
    /// puis les finals du texte.
    func run(audio: AsyncStream<AudioChunk>, emit: @escaping @Sendable (Transcript) -> Void) async throws {
        let (inputs, feed) = AsyncStream<AnalyzerInput>.makeStream()
        let (liveInputs, liveFeed) = AsyncStream<AnalyzerInput>.makeStream()
        let main = main
        let live = live
        try await withTaskCancellationHandler {
            do {
                try await main.analyzer.start(inputSequence: inputs)
                // Apercu facultatif : s'il ne demarre pas, la dictee continue sans lui.
                let active = await Self.startPreview(live, inputs: liveInputs, feed: liveFeed)
                let preview = active.map { live in
                    Task {
                        do {
                            for try await result in live.module.results {
                                emit(Transcript(text: String(result.text.characters), isFinal: result.isFinal,
                                                isPreview: true))
                            }
                        } catch {}
                    }
                }
                defer { preview?.cancel() }
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await result in main.module.results {
                            emit(Transcript(text: String(result.text.characters), isFinal: result.isFinal))
                        }
                    }
                    group.addTask {
                        var converter: PCMConverter?
                        var liveConverter: PCMConverter?
                        for await chunk in audio {
                            guard let buffer = chunk.pcmBuffer() else { continue }
                            if converter?.input != buffer.format {
                                converter = PCMConverter(from: buffer.format, to: main.format)
                            }
                            let converted = converter?.convert(buffer)
                            if let converted { feed.yield(AnalyzerInput(buffer: converted)) }
                            guard let active else { continue }
                            if active.format == main.format {
                                if let converted { liveFeed.yield(AnalyzerInput(buffer: converted)) }
                            } else {
                                if liveConverter?.input != buffer.format {
                                    liveConverter = PCMConverter(from: buffer.format, to: active.format)
                                }
                                if let other = liveConverter?.convert(buffer) {
                                    liveFeed.yield(AnalyzerInput(buffer: other))
                                }
                            }
                        }
                        feed.finish()
                        // L'apercu s'arrete net : il ne dispute pas la finalisation au texte.
                        liveFeed.finish()
                        if let active { Task { await active.analyzer.cancelAndFinishNow() } }
                        try Task.checkCancellation()
                        try await main.analyzer.finalizeAndFinishThroughEndOfInput()
                    }
                    try await group.waitForAll()
                }
            } catch {
                // Aucun analyseur laisse ouvert.
                feed.finish()
                liveFeed.finish()
                await main.analyzer.cancelAndFinishNow()
                await live?.analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            feed.finish()
            liveFeed.finish()
            Task {
                await main.analyzer.cancelAndFinishNow()
                await live?.analyzer.cancelAndFinishNow()
            }
        }
    }

    /// Demarre l'analyseur de l'apercu. S'il ne demarre pas : son flux est ferme, l'analyseur annule,
    /// et la dictee continue sans apercu (nil).
    private static func startPreview(_ live: Stage?, inputs: AsyncStream<AnalyzerInput>,
                                     feed: AsyncStream<AnalyzerInput>.Continuation) async -> Stage? {
        guard let live else { return nil }
        do {
            #if DEBUG
            // Essai : `CHUCHOTE_FAIL_PREVIEW_START=1` simule un apercu qui ne demarre pas.
            if ProcessInfo.processInfo.environment["CHUCHOTE_FAIL_PREVIEW_START"] != nil {
                throw EngineError.previewUnavailable
            }
            #endif
            try await live.analyzer.start(inputSequence: inputs)
            return live
        } catch {
            feed.finish()
            await live.analyzer.cancelAndFinishNow()
            return nil
        }
    }
}

enum EngineError: LocalizedError {
    case noAudioFormat
    /// L'apercu en direct n'a pas demarre (la dictee continue sans lui).
    case previewUnavailable

    var errorDescription: String? {
        switch self {
        case .noAudioFormat: "Le moteur de dict\u{00E9}e ne propose aucun format audio pour cette langue."
        case .previewUnavailable: "L\u{2019}aper\u{00E7}u en direct n\u{2019}a pas d\u{00E9}marr\u{00E9}."
        }
    }
}

/// Garde une session prete d'avance (au plus une).
private actor SessionPool {
    let locale: Locale
    let liveText: Bool
    private var next: Session?
    private var making: Task<Session, any Error>?

    init(locale: Locale, liveText: Bool) {
        self.locale = locale
        self.liveText = liveText
    }

    /// Session prete, ou creee a la demande (moteur froid).
    func take() async throws -> Session {
        if let next {
            self.next = nil
            return next
        }
        if let making {
            self.making = nil
            return try await making.value
        }
        return try await Session.make(locale: locale, liveText: liveText)
    }

    func refill() async throws {
        guard next == nil else { return }
        if let making {
            _ = try await making.value
            return
        }
        let locale = locale
        let liveText = liveText
        let task = Task { try await Session.make(locale: locale, liveText: liveText) }
        making = task
        let session: Session
        do {
            session = try await task.value
        } catch {
            // Echec : la prochaine preparation doit pouvoir reessayer.
            if making == task { making = nil }
            throw error
        }
        // `take()` a pu prendre la tache entre-temps : la session est alors deja utilisee.
        if making == task {
            making = nil
            next = session
        }
    }
}
