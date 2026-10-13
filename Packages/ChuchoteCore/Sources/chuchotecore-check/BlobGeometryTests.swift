import Foundation
import ChuchoteCore

/// r, r' et r'' par differences finies (rayon relatif du contour).
private func derivatives(angle: Double, time: Double, intensity: Double) -> (Double, Double, Double) {
    let h = 1e-3
    let r0 = BlobGeometry.radius(angle: angle, time: time, intensity: intensity)
    let rp = BlobGeometry.radius(angle: angle + h, time: time, intensity: intensity)
    let rm = BlobGeometry.radius(angle: angle - h, time: time, intensity: intensity)
    return (r0, (rp - rm) / (2 * h), (rp - 2 * r0 + rm) / (h * h))
}

let blobGeometryTests: (String, [Test]) = ("BlobGeometry", [
    Test("cinq a six harmoniques faibles, lentes") {
        let harmonics = BlobGeometry.harmonics
        expect((5...6).contains(harmonics.count), "\(harmonics.count) harmoniques")
        for h in harmonics {
            expect(h.order >= 2, "ordre \(h.order) : 0 et 1 deplaceraient la forme")
            expect(h.amplitude > 0 && h.amplitude <= 0.05, "amplitude \(h.amplitude)")
            expect(abs(h.speed) > 0 && abs(h.speed) <= 0.8, "vitesse \(h.speed) rad/s")
        }
        expectEqual(Set(harmonics.map(\.order)).count, harmonics.count, "ordres distincts")
    },

    Test("contour ferme, rayon borne") {
        for time in stride(from: 0.0, through: 60, by: 0.7) {
            for intensity in [0.0, BlobGeometry.intensity(level: 0), BlobGeometry.intensity(level: 1)] {
                let start = BlobGeometry.radius(angle: 0, time: time, intensity: intensity)
                let end = BlobGeometry.radius(angle: 2 * .pi, time: time, intensity: intensity)
                expect(abs(start - end) < 1e-9, "contour ouvert t=\(time)")
                for i in 0..<180 {
                    let r = BlobGeometry.radius(angle: Double(i) / 180 * 2 * .pi, time: time, intensity: intensity)
                    let bound = BlobGeometry.maxDeviation * intensity + 1e-9
                    expect(r >= 1 - bound && r <= 1 + bound,
                           "r=\(r) t=\(time)")
                }
            }
        }
        expect(BlobGeometry.maxDeviation * BlobGeometry.intensity(level: 1) <= 0.12, "deformation trop forte")
    },

    Test("intensite nulle : cercle") {
        for i in 0..<36 {
            expectEqual(BlobGeometry.radius(angle: Double(i), time: 12.3, intensity: 0), 1)
        }
    },

    Test("forme convexe a tout niveau : ni pointe ni creux") {
        let intensity = BlobGeometry.intensity(level: 1)
        for time in stride(from: 0.0, through: 120, by: 0.37) {
            for i in 0..<240 {
                let angle = Double(i) / 240 * 2 * .pi
                let (r, r1, r2) = derivatives(angle: angle, time: time, intensity: intensity)
                // Courbure positive d'une courbe polaire : r^2 + 2r'^2 - r r'' > 0 (marge).
                let curvature = r * r + 2 * r1 * r1 - r * r2
                if curvature <= 0.1 {
                    expect(false, "creux t=\(time) angle=\(angle) : \(curvature)")
                    return
                }
            }
        }
    },

    Test("derive lente : peu de changement en un dixieme de seconde") {
        let intensity = BlobGeometry.intensity(level: 1)
        for i in 0..<72 {
            let angle = Double(i) / 72 * 2 * .pi
            let a = BlobGeometry.radius(angle: angle, time: 3, intensity: intensity)
            let b = BlobGeometry.radius(angle: angle, time: 3.1, intensity: intensity)
            expect(abs(a - b) < 0.01, "saut \(abs(a - b))")
        }
    },

    Test("intensite : le niveau anime un peu plus la forme") {
        expect(BlobGeometry.intensity(level: 0) > 0, "forme vivante au repos")
        expect(BlobGeometry.intensity(level: 1) > BlobGeometry.intensity(level: 0))
        expectEqual(BlobGeometry.intensity(level: -1), BlobGeometry.intensity(level: 0))
        expectEqual(BlobGeometry.intensity(level: 3), BlobGeometry.intensity(level: 1))
    },

    Test("halo : echelle 1,0 a 1,35 selon le niveau") {
        expectEqual(BlobGeometry.haloScale(level: 0), 1.0)
        expectEqual(BlobGeometry.haloScale(level: 1), 1.35)
        expectEqual(BlobGeometry.haloScale(level: -0.5), 1.0)
        expectEqual(BlobGeometry.haloScale(level: 2), 1.35)
        expect(abs(BlobGeometry.haloScale(level: 0.5) - 1.175) < 1e-9)
    },

    Test("coeur : bouge peu avec la voix") {
        expectEqual(BlobGeometry.coreScale(level: 0), 1.0)
        let loud = BlobGeometry.coreScale(level: 1)
        expect(loud > 1 && loud <= 1.05, "coeur \(loud)")
    },

    Test("ecriture : le coeur pulse entre 0,9 et 1,0 en 1,2 s") {
        expectEqual(BlobGeometry.writingPulsePeriod, 1.2)
        var low = 1.0, high = 0.0
        for i in 0...1200 {
            let s = BlobGeometry.writingPulse(time: Double(i) / 1000)
            low = min(low, s)
            high = max(high, s)
        }
        expect(abs(low - 0.9) < 1e-6 && abs(high - 1.0) < 1e-6, "\(low)...\(high)")
        expect(abs(BlobGeometry.writingPulse(time: 0.3) - BlobGeometry.writingPulse(time: 1.5)) < 1e-9, "periode")
    },

    Test("collage : halo bref puis rien") {
        let (scale0, opacity0) = BlobGeometry.pastedFlash(elapsed: 0)
        expectEqual(scale0, 1.0)
        expect(opacity0 > 0.9, "opacite au depart \(opacity0)")
        let (scaleMid, opacityMid) = BlobGeometry.pastedFlash(elapsed: BlobGeometry.pastedFlashDuration / 2)
        expect(scaleMid > 1.1 && scaleMid <= 1.35, "echelle \(scaleMid)")
        expect(opacityMid > 0 && opacityMid < opacity0)
        let (_, opacityEnd) = BlobGeometry.pastedFlash(elapsed: BlobGeometry.pastedFlashDuration)
        expectEqual(opacityEnd, 0)
        let (_, opacityLate) = BlobGeometry.pastedFlash(elapsed: 5)
        expectEqual(opacityLate, 0)
        expect(BlobGeometry.pastedFlashDuration <= 0.5, "bref")
    },
])
