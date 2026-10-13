import Foundation

/// Bloc d'audio brut : echantillons Float mono et leur frequence (Hz).
/// Volontairement sans AVFoundation : le moteur reel convertit vers son format.
public struct AudioChunk: Sendable, Equatable {
    public var samples: [Float]
    public var sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// Duree du bloc en secondes (0 si la frequence est nulle).
    public var duration: TimeInterval {
        sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }
}

/// Texte reconnu. Un partiel (`isFinal == false`) remplace le partiel precedent ;
/// un final est definitif pour son segment.
public struct Transcript: Sendable, Equatable {
    public var text: String
    public var isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// Texte d'une dictee au fil des transcriptions : les finals bout a bout, puis le dernier
/// partiel (qui remplace le precedent) tant qu'aucun final ne l'a remplace. Segments vides ignores,
/// blancs de bord retires ; la mise au propre reste a `Polish`.
public struct TranscriptBuffer: Sendable, Equatable {
    private var finals: [String] = []
    private var partial = ""

    public init() {}

    public mutating func add(_ transcript: Transcript) {
        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if transcript.isFinal {
            if !text.isEmpty { finals.append(text) }
            partial = ""
        } else {
            partial = text
        }
    }

    public var text: String {
        (partial.isEmpty ? finals : finals + [partial]).joined(separator: " ")
    }
}

/// Moteur de reconnaissance. Il lit l'audio jusqu'a la fin du flux (fin de
/// l'ecoute), emet des partiels au fil de l'eau puis ses finals, et termine son
/// flux apres le dernier final. La langue se choisit a la construction du moteur.
/// Annuler la consommation du flux de sortie arrete le moteur.
public protocol Transcriber: Sendable {
    func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<Transcript, any Error>
}

/// Moteur scripte, pour les tests et le mode capture. Emet les partiels du script
/// (dans l'ordre, avec `delay` avant chacun), attend la fin de l'audio, puis emet
/// le reste du script a partir du premier final, et enfin `failure` s'il y en a une.
public struct FakeTranscriber: Transcriber {
    public let script: [Transcript]
    public let delay: Duration
    /// Erreur qui termine le flux apres le script et la fin de l'audio (nil : fin normale).
    public let failure: (any Error)?

    public init(script: [Transcript], delay: Duration = .zero, failure: (any Error)? = nil) {
        self.script = script
        self.delay = delay
        self.failure = failure
    }

    /// Partiels mot a mot puis la phrase entiere en final.
    public static func progressive(_ sentence: String, delay: Duration = .zero) -> FakeTranscriber {
        let words = sentence.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            return FakeTranscriber(script: [Transcript(text: "", isFinal: true)], delay: delay)
        }
        let script = (1...words.count).map { n in
            Transcript(text: words.prefix(n).joined(separator: " "), isFinal: n == words.count)
        }
        return FakeTranscriber(script: script, delay: delay)
    }

    public func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<Transcript, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Transcript, any Error>.makeStream()
        let script = script
        let delay = delay
        let failure = failure
        let task = Task {
            do {
                var audioEnded = false
                for transcript in script {
                    if transcript.isFinal && !audioEnded {
                        for await _ in audio {}
                        audioEnded = true
                    }
                    if delay > .zero { try await Task.sleep(for: delay) }
                    try Task.checkCancellation()
                    continuation.yield(transcript)
                }
                if !audioEnded { for await _ in audio {} }
                try Task.checkCancellation()
                if let failure { throw failure }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
