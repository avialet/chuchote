import Foundation
import ChuchoteCore

/// Alimente le mesureur pendant `seconds` par pas de 10 ms.
private func feed(_ meter: inout LevelMeter, amplitude: Float, seconds: Double) -> Double {
    var level = meter.level
    let steps = Int((seconds / 0.01).rounded())
    for _ in 0..<steps {
        level = meter.feed(samples: [Float](repeating: amplitude, count: 160), dt: 0.01)
    }
    return level
}

let levelMeterTests: (String, [Test]) = ("LevelMeter", [
    Test("constants") {
        expectEqual(LevelMeter.floorDecibels, -50)
        expectEqual(LevelMeter.attack, 0.060)
        expectEqual(LevelMeter.release, 0.250)
    },
    Test("instantLevelMapsDecibels") {
        expectEqual(LevelMeter.instantLevel(samples: []), 0)
        expectEqual(LevelMeter.instantLevel(samples: [0, 0, 0]), 0)
        expectEqual(LevelMeter.instantLevel(samples: [1, -1, 1, -1]), 1)
        // RMS 0.1 = -20 dB -> 30/50.
        expect(abs(LevelMeter.instantLevel(samples: [0.1, -0.1]) - 0.6) < 1e-6)
        // Sous le plancher de -50 dB : 0 ; au-dessus de 0 dB : borne a 1.
        expectEqual(LevelMeter.instantLevel(samples: [0.001]), 0)
        expectEqual(LevelMeter.instantLevel(samples: [4, -4]), 1)
    },
    Test("silenceStaysAtZero") {
        var meter = LevelMeter()
        expectEqual(feed(&meter, amplitude: 0, seconds: 1), 0)
    },
    Test("fullSignalReachesNearOne") {
        var meter = LevelMeter()
        let level = feed(&meter, amplitude: 1, seconds: 0.5)
        expect(level > 0.99 && level <= 1, "niveau \(level)")
    },
    Test("riseIsFasterThanFall") {
        var rising = LevelMeter()
        let up = feed(&rising, amplitude: 1, seconds: 0.1)
        var falling = LevelMeter()
        _ = feed(&falling, amplitude: 1, seconds: 1)
        let start = falling.level
        let down = start - feed(&falling, amplitude: 0, seconds: 0.1)
        expect(up > down, "montee \(up) descente \(down)")
        // Constantes de temps : environ 63 % en 60 ms a la montee, en 250 ms a la descente.
        var a = LevelMeter()
        expect(abs(feed(&a, amplitude: 1, seconds: 0.06) - (1 - exp(-1))) < 0.01)
        var b = LevelMeter()
        _ = feed(&b, amplitude: 1, seconds: 1)
        let fallen = feed(&b, amplitude: 0, seconds: 0.25)
        expect(abs(fallen - b.level) < 1e-12)
        expect(abs((1 - fallen) - (1 - exp(-1))) < 0.02, "apres 250 ms : \(fallen)")
    },
    Test("zeroOrNegativeDtKeepsLevel") {
        var meter = LevelMeter()
        expectEqual(meter.feed(samples: [1, 1], dt: 0), 0)
        expectEqual(meter.feed(samples: [1, 1], dt: -1), 0)
    },
    Test("reset") {
        var meter = LevelMeter()
        _ = feed(&meter, amplitude: 1, seconds: 0.2)
        meter.reset()
        expectEqual(meter.level, 0)
    },
])
