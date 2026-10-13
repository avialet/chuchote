#if DEBUG
import AVFoundation
import ChuchoteCore

/// Essai du moteur sans micro (DEBUG) : `Chuchote -ChuchoteEngineCheck <fichier audio> [-ChuchoteEngineCheckOut <rapport>]`.
/// Lit le fichier en blocs de 100 ms au rythme reel, le passe deux fois dans AppleTranscriber (la premiere
/// apres la preparation : moteur chaud ; la seconde comme une dictee suivante), et mesure la latence entre
/// la fin de l'audio et la fin du texte, sans puis avec l'apercu en direct (premier apercu, nombre).
/// Imprime le rapport (et l'ecrit dans le fichier demande), puis quitte.
enum EngineCheck {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-\(Brand.name)EngineCheck"), i + 1 < args.count else { return false }
        let input = URL(fileURLWithPath: args[i + 1])
        let output = args.firstIndex(of: "-\(Brand.name)EngineCheckOut").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        Task {
            let report = await run(file: input)
            print(report)
            if let output { try? report.write(toFile: output, atomically: true, encoding: .utf8) }
            exit(0)
        }
        return true
    }

    static func run(file: URL) async -> String {
        var lines: [String] = []
        do {
            let chunks = try readChunks(file)
            let seconds = chunks.reduce(0) { $0 + $1.duration }
            let locale = DictationController.currentLocale
            lines.append("fichier : \(file.lastPathComponent), \(String(format: "%.2f", seconds)) s, langue \(locale.identifier)")
            lines.append("ressources : \(await AppleTranscriber.assetState(for: locale))")
            for liveText in [false, true] {
                lines.append(liveText ? "avec apercu en direct" : "sans apercu")
                let engine = AppleTranscriber(locale: locale, liveText: liveText)
                let clock = ContinuousClock()
                let prepare = try await clock.measure { try await engine.prepare() }
                lines.append("  preparation (moteur froid -> chaud) : \(milliseconds(prepare)) ms")
                for pass in 1...2 {
                    let run = try await transcribe(chunks, with: engine)
                    lines.append("  passe \(pass) : fin de l'audio -> texte : \(milliseconds(run.latency)) ms")
                    if liveText {
                        let first = run.firstPreview.map { "\(milliseconds($0)) ms" } ?? "aucun"
                        lines.append("    apercus : \(run.previews), premier \(first) apres le debut de l'audio")
                        lines.append("    dernier apercu : \(run.preview)")
                    }
                    lines.append("    brut : \(run.text)")
                    lines.append("    poli : \(Polish.apply(run.text, locale: locale.identifier, frenchTypography: true))")
                }
            }
        } catch {
            lines.append("echec : \(error)")
        }
        return lines.joined(separator: "\n")
    }

    private struct Run {
        var text: String
        var preview: String
        var latency: Duration
        var previews: Int
        var firstPreview: Duration?
    }

    /// Envoie les blocs au rythme reel, termine l'audio, et mesure jusqu'a la fin du flux.
    private static func transcribe(_ chunks: [AudioChunk], with engine: AppleTranscriber) async throws -> Run {
        let (audio, feed) = AsyncStream<AudioChunk>.makeStream()
        let output = engine.transcribe(audio)
        let start = ContinuousClock.now
        let reader = Task {
            var buffer = TranscriptBuffer()
            var previews = 0
            var first: Duration?
            for try await transcript in output {
                if transcript.isPreview {
                    previews += 1
                    if first == nil { first = ContinuousClock.now - start }
                }
                buffer.add(transcript)
            }
            return (buffer, previews, first, ContinuousClock.now)
        }
        for chunk in chunks {
            feed.yield(chunk)
            try await Task.sleep(for: .seconds(chunk.duration))
        }
        let end = ContinuousClock.now
        feed.finish()
        let (buffer, previews, first, done) = try await reader.value
        return Run(text: buffer.text, preview: buffer.preview, latency: done - end, previews: previews,
                   firstPreview: first)
    }

    /// Blocs mono Float32 de 100 ms a la frequence de la dictee.
    private static func readChunks(_ url: URL) throws -> [AudioChunk] {
        let file = try AVAudioFile(forReading: url)
        let rate = DictationController.sampleRate
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let converter = PCMConverter(from: file.processingFormat, to: target),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        guard let converted = converter.convert(buffer), let all = AudioChunk(buffer: converted) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let size = Int(rate / 10)
        return stride(from: 0, to: all.samples.count, by: size).map { start in
            AudioChunk(samples: Array(all.samples[start..<min(start + size, all.samples.count)]), sampleRate: rate)
        }
    }

    private static func milliseconds(_ d: Duration) -> Int {
        Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }
}
#endif
