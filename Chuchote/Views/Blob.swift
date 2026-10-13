import ChuchoteCore
import SwiftUI
import VialetKit

/// Blob de l'ecoute : une seule forme organique lisse (BlobGeometry) remplie d'un degrade radial
/// accent -> deep (nuit en sombre) eclaire en haut a gauche, et un halo concentrique de la meme forme
/// dont l'echelle suit la voix. Le coeur bouge peu ; c'est le halo qui respire. Aucun trait.
struct Blob: View {
    enum Mode: Equatable {
        /// Repos de la fenetre (etat vide) : derive lente, halo discret qui respire.
        case calm
        /// Ecoute : le halo suit le niveau.
        case listening
        /// Transcription : halo replie, le coeur pulse doucement.
        case writing
        /// Texte livre : halo bref, puis la forme se fige.
        case pasted
        /// Pose figee (erreur).
        case frozen
    }

    var level: Double
    var mode: Mode
    /// Instant fixe (secondes) pour une pose stable (mode capture) ; nil : anime.
    var fixedTime: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Instant de la forme figee (collage, erreur).
    @State private var frozenAt: Double?

    /// Rayon du coeur rapporte a la demi-largeur du cadre : laisse la place au halo le plus grand.
    static let coreFraction: Double = 1 / (BlobGeometry.haloScale(level: 1) * BlobGeometry.coreScale(level: 1)
        * (1 + BlobGeometry.maxDeviation * BlobGeometry.intensity(level: 1)))

    /// Repos : 30 images par seconde suffisent a une derive lente.
    private var frameInterval: Double { mode == .calm ? 1.0 / 30 : 1.0 / 60 }

    var body: some View {
        Group {
            if let fixedTime {
                canvas(time: fixedTime)
            } else {
                TimelineView(.animation(minimumInterval: frameInterval, paused: mode == .frozen)) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .onChange(of: mode, initial: true) { _, mode in freeze(mode) }
        .accessibilityHidden(true)
    }

    private func freeze(_ mode: Mode) {
        let still = mode == .pasted || mode == .frozen
        frozenAt = still ? Date.timeIntervalSinceReferenceDate : nil
    }

    private func canvas(time: Double) -> some View {
        let palette = Palette(dark: colorScheme == .dark)
        let pose = Self.pose(mode: mode, level: min(max(level, 0), 1), time: time, frozenAt: frozenAt,
                             reduceMotion: reduceMotion)
        return Canvas { context, size in
            Self.draw(in: &context, size: size, pose: pose, palette: palette)
        }
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, pose: Pose, palette: Palette) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: Double = min(size.width, size.height) / 2 * coreFraction * pose.coreScale
        if pose.haloOpacity > 0.001 && pose.haloScale > 1.001 {
            let halo = outline(center: center, radius: radius * pose.haloScale, time: pose.shapeTime,
                               intensity: pose.intensity)
            context.fill(halo, with: .color(palette.halo.opacity(pose.haloOpacity)))
        }
        // Lumiere en haut a gauche : du volume sans reflet.
        let light = CGPoint(x: center.x - 0.32 * radius, y: center.y - 0.38 * radius)
        let core = outline(center: center, radius: radius, time: pose.shapeTime, intensity: pose.intensity)
        let shading = GraphicsContext.Shading.radialGradient(palette.core, center: light, startRadius: 0,
                                                             endRadius: radius * 2.3)
        context.fill(core, with: shading)
    }

    // MARK: - Pose

    private struct Pose {
        var shapeTime: Double
        var intensity: Double
        var coreScale: Double
        var haloScale: Double
        var haloOpacity: Double
    }

    private static func pose(mode: Mode, level: Double, time: Double, frozenAt: Double?,
                             reduceMotion: Bool) -> Pose {
        let shapeTime = reduceMotion ? 0 : (frozenAt ?? time)
        var pose = Pose(shapeTime: shapeTime, intensity: BlobGeometry.intensity(level: level),
                        coreScale: 1, haloScale: 1, haloOpacity: 1)
        if reduceMotion {
            // Coeur fixe, halo en fondu a echelle fixe.
            pose.intensity = BlobGeometry.intensity(level: 0)
            pose.haloScale = BlobGeometry.haloScale(level: 0.7)
            switch mode {
            case .listening: pose.haloOpacity = level
            case .pasted: pose.haloOpacity = BlobGeometry.pastedFlash(elapsed: time - (frozenAt ?? time)).opacity
            case .calm, .writing, .frozen: pose.haloOpacity = 0
            }
            return pose
        }
        switch mode {
        case .calm:
            pose.intensity = BlobGeometry.intensity(level: 0)
            // Halo large et attenue qui respire lentement : une lueur, pas un anneau.
            let breath: Double = sin(2 * Double.pi * time / 5)
            pose.haloScale = BlobGeometry.haloScale(level: 0.55 + 0.15 * breath)
            pose.haloOpacity = 0.5
        case .listening:
            pose.coreScale = BlobGeometry.coreScale(level: level)
            pose.haloScale = BlobGeometry.haloScale(level: level)
            // Halo a peine ouvert : attenue, pour ne pas lire un anneau.
            pose.haloOpacity = 0.45 + 0.55 * level
        case .writing:
            pose.intensity = BlobGeometry.intensity(level: 0)
            pose.coreScale = BlobGeometry.writingPulse(time: time)
        case .pasted:
            let flash = BlobGeometry.pastedFlash(elapsed: time - (frozenAt ?? time))
            pose.intensity = BlobGeometry.intensity(level: 0)
            pose.haloScale = flash.scale
            pose.haloOpacity = flash.opacity
        case .frozen:
            pose.intensity = BlobGeometry.intensity(level: 0)
        }
        return pose
    }

    // MARK: - Forme

    /// Contour ferme de BlobGeometry, lisse par des courbes quadratiques entre les milieux.
    private static func outline(center: CGPoint, radius: Double, time: Double, intensity: Double) -> Path {
        let count = 96
        let points: [CGPoint] = (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi
            let r = radius * BlobGeometry.radius(angle: angle, time: time, intensity: intensity)
            return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var path = Path()
        path.move(to: mid(points[count - 1], points[0]))
        for i in 0..<count {
            path.addQuadCurve(to: mid(points[i], points[(i + 1) % count]), control: points[i])
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Teintes

    /// Clair : coeur accent -> deep, halo pale. Sombre : coeur accent -> nuit, halo accent a 30 % (nightInk a 30 % grisait le halo en anneau terne).
    private struct Palette {
        let core: Gradient
        let halo: Color

        @MainActor init(dark: Bool) {
            let edge = dark ? Theme.accentNight : Theme.accentDeep
            core = Gradient(stops: [
                .init(color: Theme.accent, location: 0.25),
                .init(color: edge, location: 1),
            ])
            halo = dark ? Theme.accent.opacity(0.3) : Theme.accentPale
        }
    }
}
