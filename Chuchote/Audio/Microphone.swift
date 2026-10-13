import AVFoundation
import ChuchoteCore

/// Source d'audio de la dictee : le micro, ou une source figee pour le mode capture.
@MainActor
protocol AudioSource: AnyObject {
    /// Niveau 0-1 lisse (attaque 60 ms, relache 250 ms), publie sur le MainActor (~30 Hz).
    var onLevel: ((Double) -> Void)? { get set }
    /// Ecoute interrompue par la source elle-meme (micro perdu), appele sur le MainActor ; le flux
    /// est ensuite termine.
    var onInterruption: (() -> Void)? { get set }
    /// Vrai si l'ecoute est autorisee (demande la permission au premier usage).
    func authorize() async -> Bool
    /// Demarre l'ecoute : blocs mono Float32 a `sampleRate`, jusqu'a `stop()`.
    func start(sampleRate: Double) throws -> AsyncStream<AudioChunk>
    /// Arrete l'ecoute et termine le flux.
    func stop()
}

/// Micro par AVAudioEngine. Le moteur est prepare a l'avance (`prepare()`), mais ne tourne que
/// pendant l'ecoute : aucun indicateur de micro au repos.
@MainActor
final class Microphone: AudioSource {
    enum Failure: LocalizedError {
        case noInput
        case engine(String)

        var errorDescription: String? {
            switch self {
            case .noInput: "Aucun micro disponible."
            case .engine(let message): "Micro indisponible : \(message)"
            }
        }
    }

    var onLevel: ((Double) -> Void)?
    var onInterruption: (() -> Void)?
    private let engine = AVAudioEngine()
    private var tap: MicrophoneTap?
    /// Ecoute en cours : flux, format cible et observation des changements de peripherique.
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var target: AVAudioFormat?
    private var configurationObserver: (any NSObjectProtocol)?
    private var isPrepared = false

    static var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static var isDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .denied || status == .restricted
    }

    func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Prepare le moteur (sans demarrer le micro) si l'acces est deja accorde.
    func prepare() {
        guard Self.isAuthorized, !isPrepared, tap == nil else { return }
        _ = engine.inputNode
        engine.prepare()
        isPrepared = true
    }

    func start(sampleRate: Double) throws -> AsyncStream<AudioChunk> {
        stop()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let converter = PCMConverter(from: format, to: target) else { throw Failure.noInput }
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        let tap = makeTap(converter: converter, continuation: continuation)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap.block())
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            throw Failure.engine(error.localizedDescription)
        }
        self.tap = tap
        self.continuation = continuation
        self.target = target
        // Peripherique change en pleine ecoute (AirPods, micro debranche) : le moteur s'arrete.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged() }
        }
        return stream
    }

    private func makeTap(converter: PCMConverter,
                         continuation: AsyncStream<AudioChunk>.Continuation) -> MicrophoneTap {
        MicrophoneTap(converter: converter, continuation: continuation) { [weak self] level in
            self?.onLevel?(level)
        }
    }

    /// Le moteur s'est arrete sur un changement de peripherique : nouveau tap au nouveau format,
    /// meme flux ; si le micro ne repart pas, l'ecoute est interrompue.
    private func configurationChanged() {
        guard let old = tap, let continuation, let target else { return }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        old.retire()
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let converter = PCMConverter(from: format, to: target) else {
            interrupt()
            return
        }
        let tap = makeTap(converter: converter, continuation: continuation)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap.block())
        self.tap = tap
        do {
            try engine.start()
        } catch {
            interrupt()
        }
    }

    private func interrupt() {
        onInterruption?()
        stop()
    }

    func stop() {
        guard let tap else { return }
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        tap.finish()
        self.tap = nil
        continuation = nil
        target = nil
        onLevel?(0)
        // Pret pour la prochaine ecoute.
        engine.prepare()
        isPrepared = true
    }
}

/// Etat du tap, utilise sur le fil audio : conversion, niveau, emission des blocs.
private final class MicrophoneTap: @unchecked Sendable {
    private let converter: PCMConverter
    private let continuation: AsyncStream<AudioChunk>.Continuation
    private let publish: @MainActor (Double) -> Void
    private var meter = LevelMeter()
    private var sinceLastPublish: TimeInterval = 1
    /// Pose par `finish()` (MainActor) : un niveau deja en route vers le MainActor n'est plus publie.
    @MainActor private var stopped = false
    private static let publishInterval: TimeInterval = 1.0 / 30

    init(converter: PCMConverter, continuation: AsyncStream<AudioChunk>.Continuation,
         publish: @escaping @MainActor (Double) -> Void) {
        self.converter = converter
        self.continuation = continuation
        self.publish = publish
    }

    /// Bloc du tap, construit hors du MainActor : il est appele sur le fil audio.
    nonisolated func block() -> AVAudioNodeTapBlock {
        { [self] buffer, _ in handle(buffer) }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer), let chunk = AudioChunk(buffer: converted) else { return }
        continuation.yield(chunk)
        let level = meter.feed(samples: chunk.samples, dt: chunk.duration)
        sinceLastPublish += chunk.duration
        if sinceLastPublish >= Self.publishInterval {
            sinceLastPublish = 0
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated {
                    guard !stopped else { return }
                    publish(level)
                }
            }
        }
    }

    @MainActor func finish() {
        stopped = true
        continuation.finish()
    }

    /// Tap remplace (changement de peripherique) : n'emet plus de niveau, le flux continue.
    @MainActor func retire() { stopped = true }
}
