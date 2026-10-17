/// Format du tap pose sur le micro (noeud d'entree d'AVAudioEngine).
///
/// `installTap` exige la frequence du materiel ; sinon AVFAudio leve une exception Objective-C, que Swift
/// ne peut pas rattraper. Le format du noeud est fige par `prepare()` : si le micro change ensuite de
/// frequence (AirPods en Bluetooth : 24 kHz, noeud prepare a 48 kHz), il est perime. Chuchote 0.2.2 plantait
/// ainsi a chaque dictee.
public enum TapFormat: Equatable, Sendable {
    /// Format du noeud, a jour.
    case node
    /// Format du materiel, le noeud etant perime.
    case hardware

    public struct Description: Equatable, Sendable {
        public var sampleRate: Double
        public var channels: Int

        public init(sampleRate: Double, channels: Int) {
            self.sampleRate = sampleRate
            self.channels = channels
        }

        var isAudio: Bool { sampleRate > 0 && channels > 0 }
    }

    /// Format a donner au tap ; nil sans micro utilisable.
    public static func choose(node: Description, hardware: Description) -> TapFormat? {
        guard hardware.isAudio else { return nil }
        return node.isAudio && node.sampleRate == hardware.sampleRate ? .node : .hardware
    }
}
