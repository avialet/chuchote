import AVFoundation
import ChuchoteCore
import Speech

/// Moteur Apple (Speech, macOS 26) : `SpeechAnalyzer` + `SpeechTranscriber(locale:preset: .transcription)`.
/// Moteur chaud : une session (module + analyseur prepare) attend la prochaine dictee ; elle est
/// remplacee en arriere-plan apres chaque usage. Le modele reste charge le temps du processus.
final class AppleTranscriber: Transcriber {
    let locale: Locale
    private let pool: SessionPool

    init(locale: Locale) {
        self.locale = locale
        self.pool = SessionPool(locale: locale)
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
        let module = SpeechTranscriber(locale: supported, preset: .transcription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
            let fraction = p.fractionCompleted
            Task { @MainActor in progress(fraction) }
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
        await progress(1)
    }
}

/// Session prete : module, analyseur prepare et format d'entree de l'analyseur.
private struct Session: Sendable {
    let module: SpeechTranscriber
    let analyzer: SpeechAnalyzer
    let format: AVAudioFormat

    static func make(locale: Locale) async throws -> Session {
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let module = SpeechTranscriber(locale: resolved, preset: .transcription)
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        let analyzer = SpeechAnalyzer(modules: [module], options: options)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw EngineError.noAudioFormat
        }
        try await analyzer.prepareToAnalyze(in: format)
        return Session(module: module, analyzer: analyzer, format: format)
    }

    /// Lit `audio` jusqu'a sa fin, finalise, et emet chaque resultat (finals seulement avec ce preset).
    func run(audio: AsyncStream<AudioChunk>, emit: @escaping @Sendable (Transcript) -> Void) async throws {
        let (inputs, feed) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = analyzer
        let module = module
        let format = format
        try await withTaskCancellationHandler {
            try await analyzer.start(inputSequence: inputs)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await result in module.results {
                        emit(Transcript(text: String(result.text.characters), isFinal: result.isFinal))
                    }
                }
                group.addTask {
                    var converter: PCMConverter?
                    for await chunk in audio {
                        guard let buffer = chunk.pcmBuffer() else { continue }
                        if converter?.input != buffer.format {
                            converter = PCMConverter(from: buffer.format, to: format)
                        }
                        if let converted = converter?.convert(buffer) {
                            feed.yield(AnalyzerInput(buffer: converted))
                        }
                    }
                    feed.finish()
                    try Task.checkCancellation()
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
                try await group.waitForAll()
            }
        } onCancel: {
            feed.finish()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}

enum EngineError: LocalizedError {
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .noAudioFormat: "Le moteur de dict\u{00E9}e ne propose aucun format audio pour cette langue."
        }
    }
}

/// Garde une session prete d'avance (au plus une).
private actor SessionPool {
    let locale: Locale
    private var next: Session?
    private var making: Task<Session, any Error>?

    init(locale: Locale) { self.locale = locale }

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
        return try await Session.make(locale: locale)
    }

    func refill() async throws {
        guard next == nil else { return }
        if let making {
            _ = try await making.value
            return
        }
        let locale = locale
        let task = Task { try await Session.make(locale: locale) }
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
