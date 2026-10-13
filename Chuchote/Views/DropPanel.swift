import AppKit
import ChuchoteCore
import Observation
import SwiftUI
import VialetKit

/// Fenetre de la goutte : sans bord, jamais cle ni principale, au-dessus de la barre des menus, sur toutes
/// les Spaces et en plein ecran. Transparente hors de la goutte : les clics y passent a travers.
final class DropWindow: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Collee au bord haut, sur la barre des menus : AppKit ne doit pas la redescendre.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Montre et cache la goutte d'encoche sur l'ecran de la souris. La fenetre garde une taille fixe ;
/// c'est la vue qui s'ouvre depuis la taille de l'encoche et y remonte.
@MainActor
@Observable
final class DropPanelController {
    /// Goutte ouverte (la vue anime le passage).
    private(set) var expanded = false
    private(set) var geometry = NotchGeometry(screenFrame: .zero, safeAreaTop: 0, auxiliaryLeft: nil,
                                              auxiliaryRight: nil, menuBarHeight: 24)
    @ObservationIgnored private unowned let controller: DictationController
    @ObservationIgnored private var window: DropWindow?
    @ObservationIgnored private var openCount = 0

    /// Marge autour de la goutte : bords evases et ombre.
    static let margin: CGFloat = 28

    init(controller: DictationController) {
        self.controller = controller
    }

    var isVisible: Bool { window?.isVisible == true }

    /// Fenetre (mode capture).
    var nsWindow: NSWindow? { window }

    func show() {
        openCount += 1
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            geometry = Self.geometry(for: Self.mouseScreen())
            expanded = false
            window.setFrame(geometry.windowFrame(size: Self.windowSize(for: geometry)), display: true)
            window.orderFrontRegardless()
        }
        // Un tour de boucle : la vue part de l'encoche avant de s'ouvrir.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.expanded = true }
        }
    }

    /// La goutte remonte dans l'encoche, puis la fenetre se retire ; un `show()` entre-temps l'emporte.
    func hide() {
        guard let window, window.isVisible else { return }
        let token = openCount
        expanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + DropView.closeDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.openCount == token else { return }
                window.orderOut(nil)
            }
        }
    }

    private func makeWindow() -> DropWindow {
        let window = DropWindow(size: Self.windowSize(for: geometry))
        let host = NSHostingView(rootView: DropHost(controller: controller, drop: self).fontDesign(.rounded))
        host.sizingOptions = []
        window.contentView = host
        return window
    }

    static func windowSize(for geometry: NotchGeometry) -> CGSize {
        CGSize(width: NotchGeometry.dropWidth(notchWidth: geometry.notchWidth) + 2 * margin,
               height: geometry.bandHeight + DropView.maxBodyHeight + margin)
    }

    static func mouseScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    static func geometry(for screen: NSScreen?) -> NotchGeometry {
        guard let screen else {
            return NotchGeometry(screenFrame: .zero, safeAreaTop: 0, auxiliaryLeft: nil, auxiliaryRight: nil,
                                 menuBarHeight: 24)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                             auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea,
                             menuBarHeight: menuBar > 0 ? menuBar : NSStatusBar.system.thickness)
    }
}

/// Lien entre le controleur et la vue de la goutte.
private struct DropHost: View {
    let controller: DictationController
    let drop: DropPanelController

    var body: some View {
        DropView(content: DropContent(controller: controller), geometry: drop.geometry, expanded: drop.expanded,
                 onCancel: { controller.cancel() })
    }
}

/// Ce que montre la goutte.
struct DropContent: Equatable {
    var phase: DictationController.Phase
    var level: Double
    var liveText: String
    var showsLiveText: Bool
    var fixedBlobTime: Double?

    @MainActor
    init(controller: DictationController) {
        phase = controller.phase
        level = controller.level
        liveText = controller.liveText
        showsLiveText = controller.showsLiveText
        fixedBlobTime = controller.fixedBlobTime
    }

    init(phase: DictationController.Phase, level: Double, liveText: String, showsLiveText: Bool = true,
         fixedBlobTime: Double? = 2.4) {
        self.phase = phase
        self.level = level
        self.liveText = liveText
        self.showsLiveText = showsLiveText
        self.fixedBlobTime = fixedBlobTime
    }
}

/// La goutte : noire comme l'encoche, bords hauts evases qui s'y fondent, bas tres arrondi. Rangee du haut
/// de part et d'autre de l'encoche (blob a gauche, minuteur ou etat a droite) ; dessous, le texte en direct.
struct DropView: View {
    let content: DropContent
    let geometry: NotchGeometry
    let expanded: Bool
    var onCancel: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textHeight: CGFloat = 0
    @State private var threeLines: CGFloat = 54

    /// Rayon des evasements du haut (concaves, comme ceux de l'encoche).
    static let flare: CGFloat = 9
    static let bottomRadius: CGFloat = 28
    static let sidePadding: CGFloat = 18
    static let textSize: CGFloat = 14
    /// Hauteur maximale sous la rangee du haut : trois lignes, marges et ombre.
    static let maxBodyHeight: CGFloat = 100
    static let openAnimation = Animation.spring(duration: 0.38, bounce: 0.22)
    static let closeDuration = 0.34

    private var width: CGFloat { NotchGeometry.dropWidth(notchWidth: geometry.notchWidth) }
    private var wing: CGFloat { (width - geometry.notchWidth) / 2 }
    /// Taille de depart et d'arrivee : l'encoche, ou un trait au bord haut sans encoche.
    private var collapsed: CGSize {
        geometry.hasNotch ? CGSize(width: geometry.notchWidth, height: geometry.bandHeight) : CGSize(width: 160, height: 0)
    }

    /// En mouvement reduit : la goutte garde sa taille et apparait en fondu.
    private var open: Bool { expanded || reduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            band
            if showsBody { textBody }
        }
        .frame(width: width)
        .opacity(expanded ? 1 : 0)
        .animation(expanded ? .easeOut(duration: 0.22).delay(reduceMotion ? 0 : 0.06) : .easeIn(duration: 0.12),
                   value: expanded)
        .frame(width: open ? width : collapsed.width, height: open ? nil : collapsed.height, alignment: .top)
        .padding(.horizontal, Self.flare)
        .background(DropShape(flare: Self.flare, bottomRadius: open ? Self.bottomRadius : 10).fill(.black))
        .clipShape(DropShape(flare: Self.flare, bottomRadius: open ? Self.bottomRadius : 10))
        .shadow(color: .black.opacity(open ? 0.28 : 0), radius: 10, y: 4)
        .opacity(reduceMotion ? (expanded ? 1 : 0) : (geometry.hasNotch || expanded ? 1 : 0))
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                   : (expanded ? Self.openAnimation : .smooth(duration: Self.closeDuration - 0.04)),
                   value: expanded)
        .animation(.smooth(duration: 0.25), value: showsBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Rangee du haut

    private var band: some View {
        HStack(spacing: 0) {
            HStack {
                Blob(level: content.level, mode: blobMode, fixedTime: content.fixedBlobTime)
                    .frame(width: 24, height: 24)
                Spacer(minLength: 0)
            }
            .padding(.leading, Self.sidePadding - 2)
            .frame(width: wing)
            Color.clear.frame(width: geometry.notchWidth)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                status
                if cancellable { cancelButton }
            }
            .padding(.trailing, Self.sidePadding - 4)
            .frame(width: wing)
        }
        .frame(height: geometry.bandHeight)
    }

    private var blobMode: Blob.Mode {
        switch content.phase {
        case .writing: .writing
        case .done: .pasted
        case .failed: .frozen
        case .idle, .listening: .listening
        }
    }

    private var cancellable: Bool {
        switch content.phase {
        case .listening, .writing: true
        default: false
        }
    }

    @ViewBuilder private var status: some View {
        switch content.phase {
        case .idle:
            EmptyView()
        case .listening(let since):
            DropElapsed(since: since)
        case .writing:
            Text("J\u{2019}\u{00E9}cris\u{2026}")
                .font(Theme.ui(12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        case .done(let pasted):
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(pasted ? "Coll\u{00E9}" : "Copi\u{00E9}\u{00A0}: \u{2318}V")
                    .font(Theme.ui(12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .lineLimit(1)
            .fixedSize()
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.coral)
        }
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Annuler la dict\u{00E9}e (esc)")
        .accessibilityLabel("Annuler la dict\u{00E9}e")
    }

    // MARK: - Texte en direct

    private var showsBody: Bool {
        switch content.phase {
        case .failed: true
        case .listening, .writing, .done: content.showsLiveText
        case .idle: false
        }
    }

    private var textWidth: CGFloat { width - 2 * Self.sidePadding }

    @ViewBuilder private var textBody: some View {
        Group {
            if case .failed(let message) = content.phase {
                Text(message)
                    .font(Theme.ui(Self.textSize, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .lineLimit(2)
                    .frame(width: textWidth, alignment: .leading)
            } else if content.liveText.isEmpty {
                Text(placeholder)
                    .font(Theme.ui(Self.textSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: textWidth, alignment: .leading)
            } else {
                liveText
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 15)
    }

    private var placeholder: String {
        if case .writing = content.phase { return "J\u{2019}\u{00E9}cris\u{2026}" }
        return "J\u{2019}\u{00E9}coute\u{2026}"
    }

    /// Les derniers mots restent visibles : le debut remonte et s'efface sous un fondu.
    private var liveText: some View {
        let overflow = textHeight > threeLines + 1
        let writing = content.phase == .writing
        return Text(content.liveText)
            .font(Theme.ui(Self.textSize, weight: .medium))
            .foregroundStyle(.white.opacity(writing ? 0.55 : 0.94))
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: textWidth, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { textHeight = $0 })
            .frame(height: min(max(textHeight, 1), threeLines), alignment: .bottom)
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: overflow ? .clear : .black, location: 0),
                                       .init(color: .black, location: overflow ? 0.42 : 0)],
                               startPoint: .top, endPoint: .bottom)
            }
            .background(alignment: .topLeading) {
                // Hauteur de trois lignes dans cette police.
                Text("A\nA\nA")
                    .font(Theme.ui(Self.textSize, weight: .medium))
                    .lineSpacing(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { threeLines = $0 })
            }
            .animation(.smooth(duration: 0.2), value: textHeight)
    }
}

/// Minuteur m:ss en chiffres tabulaires, blanc sur la goutte.
private struct DropElapsed: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(Theme.ui(12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// Forme de la goutte dans `rect` : le corps occupe `rect` moins `flare` de chaque cote ; en haut, deux
/// evasements concaves rejoignent le bord de `rect` (la goutte sort de l'encoche) ; en bas, deux grands arrondis.
struct DropShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set {
            flare = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let left = rect.minX + flare
        let right = rect.maxX - flare
        let top = rect.minY
        let bottom = rect.maxY
        let radius = max(0, min(bottomRadius, (right - left) / 2, (bottom - top - flare) ))
        let f = min(flare, max(0, bottom - top - radius))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        // Evasement droit : du bord haut vers le flanc, concave.
        path.addQuadCurve(to: CGPoint(x: right, y: top + f), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - radius), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: top + f))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: top), control: CGPoint(x: left, y: top))
        path.closeSubpath()
        return path
    }
}
