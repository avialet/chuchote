import ChuchoteCore

let tapFormatTests: (String, [Test]) = ("TapFormat", [
    Test("nodeFormatWhenItMatchesTheHardware") {
        expectEqual(TapFormat.choose(node: .init(sampleRate: 48_000, channels: 1),
                                     hardware: .init(sampleRate: 48_000, channels: 1)), .node)
    },
    Test("hardwareFormatWhenTheNodeIsStale") {
        // AirPods Max (Chuchote 0.2.2) : noeud prepare a 48 kHz, micro Bluetooth a 24 kHz. installTap au
        // format du noeud leve l'exception Objective-C « format.sampleRate == inputHWFormat.sampleRate ».
        expectEqual(TapFormat.choose(node: .init(sampleRate: 48_000, channels: 1),
                                     hardware: .init(sampleRate: 24_000, channels: 1)), .hardware)
        expectEqual(TapFormat.choose(node: .init(sampleRate: 0, channels: 0),
                                     hardware: .init(sampleRate: 16_000, channels: 1)), .hardware)
    },
    Test("hardwareFormatWhenTheChannelsDiffer") {
        expectEqual(TapFormat.choose(node: .init(sampleRate: 48_000, channels: 1),
                                     hardware: .init(sampleRate: 48_000, channels: 2)), .hardware)
    },
    Test("noTapWithoutAMicrophone") {
        expectEqual(TapFormat.choose(node: .init(sampleRate: 48_000, channels: 1),
                                     hardware: .init(sampleRate: 0, channels: 0)), nil)
        expectEqual(TapFormat.choose(node: .init(sampleRate: 48_000, channels: 1),
                                     hardware: .init(sampleRate: 48_000, channels: 0)), nil)
    },
])
