import Foundation

/// Geometrie du blob de l'ecoute, sans dessin : une forme organique lisse (rayon module par quelques
/// harmoniques faibles qui derivent lentement) et les echelles du coeur et du halo selon l'etat.
/// Le coeur et le halo partagent la meme forme et le meme centre : le halo n'en est qu'un agrandissement.
public enum BlobGeometry {
    public struct Harmonic: Sendable, Equatable {
        /// Nombre de lobes (2 et plus : 0 et 1 changeraient la taille ou deplaceraient la forme).
        public let order: Int
        /// Part du rayon (avant l'intensite).
        public let amplitude: Double
        /// Derive en rad/s (signe : sens de rotation).
        public let speed: Double
        public let phase: Double
    }

    /// Amplitudes decroissantes avec l'ordre : la forme reste convexe, sans pointe ni creux.
    public static let harmonics: [Harmonic] = [
        Harmonic(order: 2, amplitude: 0.042, speed: 0.31, phase: 0.0),
        Harmonic(order: 3, amplitude: 0.014, speed: -0.23, phase: 1.7),
        Harmonic(order: 4, amplitude: 0.006, speed: 0.41, phase: 3.1),
        Harmonic(order: 5, amplitude: 0.003, speed: -0.37, phase: 4.4),
        Harmonic(order: 6, amplitude: 0.0015, speed: 0.29, phase: 5.6),
    ]

    /// Ecart relatif maximal du rayon a intensite 1.
    public static let maxDeviation: Double = harmonics.reduce(0) { $0 + $1.amplitude }

    /// Rayon relatif (1 = cercle) a l'angle `angle` (radians) et a l'instant `time` (secondes).
    /// `intensity` multiplie la deformation (0 : cercle).
    public static func radius(angle: Double, time: Double, intensity: Double) -> Double {
        var wobble = 0.0
        for h in harmonics {
            wobble += h.amplitude * sin(Double(h.order) * angle + h.speed * time + h.phase)
        }
        return 1 + intensity * wobble
    }

    /// Deformation selon le niveau de la voix : vivante au repos, un peu plus marquee en parlant.
    public static func intensity(level: Double) -> Double {
        1 + 0.5 * clamp(level)
    }

    /// Halo : 1,0 (confondu avec le coeur) au silence, 1,35 a pleine voix. C'est lui qui respire.
    public static func haloScale(level: Double) -> Double {
        1 + 0.35 * clamp(level)
    }

    /// Coeur : bouge peu (au plus 4 %).
    public static func coreScale(level: Double) -> Double {
        1 + 0.04 * clamp(level)
    }

    /// Ecriture : le coeur pulse doucement entre 0,9 et 1,0.
    public static let writingPulsePeriod: Double = 1.2

    public static func writingPulse(time: Double) -> Double {
        0.95 + 0.05 * cos(2 * .pi * time / writingPulsePeriod)
    }

    /// << Colle >> : bref halo qui s'ouvre et s'efface, puis la forme se fige.
    public static let pastedFlashDuration: Double = 0.42

    /// Echelle et opacite du halo `elapsed` secondes apres le collage.
    public static func pastedFlash(elapsed: Double) -> (scale: Double, opacity: Double) {
        let t = min(max(elapsed / pastedFlashDuration, 0), 1)
        let eased = 1 - (1 - t) * (1 - t)
        return (1 + 0.3 * eased, 1 - t)
    }

    private static func clamp(_ level: Double) -> Double { min(max(level, 0), 1) }
}
