import SwiftUI
import VialetKit

/// Blob de l'ecoute : trois couches (halo pale, corps accent, coeur deep a faible opacite), contour
/// ferme deforme par trois sinusoides lentes dont l'amplitude suit le niveau de la voix. En ecriture
/// il se resserre et respire ; fige, il garde sa pose. Reduire les animations : un cercle qui pulse.
struct Blob: View {
    enum Mode: Equatable {
        /// Ecoute : amplitude = niveau.
        case listening
        /// Transcription : resserre, respiration lente.
        case writing
        /// Pose figee (<< Colle >>).
        case frozen
    }

    var level: Double
    var mode: Mode
    /// Instant fixe (secondes) pour une pose stable (mode capture) ; nil : anime.
    var fixedTime: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var frozenTime: Double?

    var body: some View {
        Group {
            if let time = fixedTime ?? frozenTime {
                canvas(time: time)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: mode == .frozen)) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .onChange(of: mode, initial: true) { _, mode in
            frozenTime = mode == .frozen ? (frozenTime ?? Date.timeIntervalSinceReferenceDate) : nil
        }
        .accessibilityHidden(true)
    }

    private func canvas(time: Double) -> some View {
        let palette = Palette(dark: colorScheme == .dark)
        let level = min(max(level, 0), 1)
        let mode = mode
        let reduceMotion = reduceMotion
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let half = min(size.width, size.height) / 2
            let body = half * 0.62
            if reduceMotion {
                Self.drawCircles(in: &context, center: center, body: body, level: level, mode: mode,
                                 time: time, palette: palette)
                return
            }
            let shape = Self.shape(mode: mode, level: level, time: time)
            // Halo
            context.fill(Self.outline(center: center, radius: body * shape.haloScale, amplitude: shape.haloAmplitude,
                                      time: time, phase: 1.9),
                         with: .color(palette.halo))
            // Corps
            context.fill(Self.outline(center: center, radius: body * shape.scale, amplitude: shape.amplitude,
                                      time: time, phase: 0),
                         with: .color(palette.body))
            // Coeur, legerement decale vers le bas : du relief sans reflet
            let offset = body * shape.scale * 0.12
            context.fill(Self.outline(center: CGPoint(x: center.x + offset * 0.5, y: center.y + offset),
                                      radius: body * shape.scale * 0.55, amplitude: shape.amplitude * 1.3,
                                      time: time * 1.15, phase: 3.7),
                         with: .color(palette.core))
        }
    }

    // MARK: - Forme

    private struct Shape {
        var scale: Double
        var amplitude: Double
        var haloScale: Double
        var haloAmplitude: Double
    }

    private static func shape(mode: Mode, level: Double, time: Double) -> Shape {
        switch mode {
        case .listening, .frozen:
            return Shape(scale: 0.92 + 0.08 * level, amplitude: 0.04 + 0.15 * level,
                         haloScale: 1.1 + 0.22 * level, haloAmplitude: 0.06 + 0.2 * level)
        case .writing:
            let breath = sin(time * 2 * .pi / 1.6)
            return Shape(scale: 0.8 + 0.05 * breath, amplitude: 0.035,
                         haloScale: 1.02 + 0.08 * breath, haloAmplitude: 0.05)
        }
    }

    /// Contour ferme : rayon module par trois sinusoides lentes, lisse par des courbes quadratiques.
    private static func outline(center: CGPoint, radius: Double, amplitude: Double, time: Double,
                                phase: Double) -> Path {
        let count = 72
        let points: [CGPoint] = (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi
            let wobble = 0.55 * sin(3 * angle + 0.9 * time + phase)
                + 0.3 * sin(5 * angle - 1.3 * time + 2 * phase)
                + 0.15 * sin(2 * angle + 0.6 * time + 1.7)
            let r = radius * (1 + amplitude * wobble)
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

    /// Reduire les animations : cercles concentriques dont la taille suit le niveau (ou respire en ecriture).
    private static func drawCircles(in context: inout GraphicsContext, center: CGPoint, body: Double,
                                    level: Double, mode: Mode, time: Double, palette: Palette) {
        let pulse: Double
        switch mode {
        case .listening, .frozen: pulse = level
        case .writing: pulse = 0.25 + 0.25 * sin(time * 2 * .pi / 1.6)
        }
        func circle(_ r: Double) -> Path {
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }
        context.fill(circle(body * (1.1 + 0.25 * pulse)), with: .color(palette.halo))
        context.fill(circle(body * (0.88 + 0.12 * pulse)), with: .color(palette.body))
    }

    // MARK: - Teintes

    /// Clair : halo pale, corps accent, coeur deep a faible opacite.
    /// Sombre (teintes de nuit) : halo accent attenue, corps accent, coeur nightInk a faible opacite.
    private struct Palette {
        let halo: Color
        let body: Color
        let core: Color

        @MainActor init(dark: Bool) {
            halo = dark ? Theme.accent.opacity(0.3) : Theme.accentPale
            body = Theme.accent
            core = dark ? Theme.accentNightInk.opacity(0.28) : Theme.accentDeep.opacity(0.22)
        }
    }
}
