import Foundation

/// Niveau sonore lisse pour l'animation du blob : RMS du bloc, converti en dB,
/// ramene a 0-1 sur l'echelle [`floorDecibels`, 0 dB], puis lisse par un filtre
/// du premier ordre (constante `attack` a la montee, `release` a la descente).
public struct LevelMeter: Sendable, Equatable {
    /// Plancher de l'echelle : en dessous, niveau 0.
    public static let floorDecibels: Double = -50
    /// Constante de temps a la montee (s).
    public static let attack: TimeInterval = 0.060
    /// Constante de temps a la descente (s).
    public static let release: TimeInterval = 0.250

    /// Dernier niveau lisse, 0-1.
    public private(set) var level: Double = 0

    public init() {}

    /// Ajoute un bloc d'echantillons couvrant `dt` secondes et renvoie le niveau lisse.
    /// Un `dt` nul ou negatif laisse le niveau inchange.
    public mutating func feed(samples: [Float], dt: TimeInterval) -> Double {
        guard dt > 0 else { return level }
        let target = Self.instantLevel(samples: samples)
        let tau = target > level ? Self.attack : Self.release
        level += (target - level) * (1 - exp(-dt / tau))
        level = min(max(level, 0), 1)
        return level
    }

    public mutating func reset() {
        level = 0
    }

    /// Niveau instantane 0-1 d'un bloc (RMS en dB sur [`floorDecibels`, 0]). Bloc vide : 0.
    public static func instantLevel(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for sample in samples { sum += Double(sample) * Double(sample) }
        let rms = (sum / Double(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}
