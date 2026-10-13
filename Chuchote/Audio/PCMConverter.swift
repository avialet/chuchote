import AVFoundation
import ChuchoteCore

/// Conversion de tampons PCM d'un format a un autre (frequence, canaux, Float/Int16), bloc par bloc.
/// A utiliser depuis un seul fil a la fois (le tap du micro, ou la tache du moteur).
final class PCMConverter {
    let input: AVAudioFormat
    let output: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.input = input
        self.output = output
        self.converter = converter
    }

    /// Convertit un bloc ; nil si la conversion echoue ou ne produit rien.
    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = output.sampleRate / input.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        // Le bloc d'entree n'est fourni qu'une fois ; ensuite : rien pour l'instant (flux continu).
        nonisolated(unsafe) var provided = false
        nonisolated(unsafe) let source = buffer
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if provided {
                inputStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, error == nil, out.frameLength > 0 else { return nil }
        return out
    }
}

extension AudioChunk {
    /// Echantillons du premier canal d'un tampon Float32.
    init?(buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        self.init(samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))),
                  sampleRate: buffer.format.sampleRate)
    }

    /// Tampon Float32 mono non entrelace portant ces echantillons.
    func pcmBuffer() -> AVAudioPCMBuffer? {
        guard sampleRate > 0, !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
