#if DEBUG
import AppKit
import ChuchoteCore

/// Essai reel des clics autour de la goutte (DEBUG) : `Chuchote -ChuchoteClickCheck`.
/// Montre la goutte en ecoute (moteur et niveau figes), place derriere elle une fenetre temoin qui compte
/// ses clics, puis poste de vrais clics (CGEvent) : a cote, sous la goutte et dans son ombre (hors de la
/// goutte visible : le temoin doit les recevoir), sur le texte (la goutte doit les garder) et sur la croix (la
/// dictee doit s'annuler). Le curseur revient ensuite a sa place. Exige l'Accessibilite pour poster les clics.
/// Imprime chaque verification, puis quitte (1 si echec).
@MainActor
enum ClickCheck {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("-\(Brand.name)ClickCheck") else { return false }
        Task {
            let failures = await run()
            print(failures == 0 ? "clics : tout est bon" : "clics : \(failures) echec(s)")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }

    private static var failures = 0

    private static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "ok  " : "ECHEC") \(label)")
        if !condition { failures += 1 }
    }

    private static func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    static func run() async -> Int {
        let start = NSEvent.mouseLocation
        let controller = DictationController.snapshot(style: .drop)
        await controller.snapshotListening()
        guard let window = controller.dropWindow, let geometry = controller.dropGeometry else {
            check(false, "goutte affichee")
            return failures
        }
        let visible = controller.dropHitRect
        print("fenetre \(window.frame), goutte visible \(visible)")
        check(!visible.isEmpty && window.frame.contains(visible), "goutte ouverte dans sa fenetre")

        // Temoin derriere la goutte, sous toute sa fenetre.
        let recorder = ClickRecorder()
        let behind = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        behind.isReleasedWhenClosed = false
        behind.level = .floating
        behind.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.25)
        behind.contentView = recorder
        behind.orderFrontRegardless()
        window.orderFrontRegardless()
        await wait(300)

        let frame = window.frame
        let beside = CGPoint(x: frame.minX + 8, y: frame.maxY - 70)
        let below = CGPoint(x: frame.midX, y: frame.minY + 6)
        // Juste sous le bord de la goutte, dans son ombre (pixels presque transparents).
        let shadow = CGPoint(x: visible.midX, y: visible.minY - 5)
        let text = CGPoint(x: visible.midX, y: visible.minY + 20)
        let cross = CGPoint(x: visible.maxX - DropView.sidePadding + 4 - 9, y: frame.maxY - geometry.bandHeight / 2)

        for (label, point) in [("a cote de la goutte", beside), ("sous la goutte", below), ("dans l'ombre de la goutte", shadow)] {
            let before = recorder.clicks
            await click(point)
            check(window.ignoresMouseEvents, "\(label) : la fenetre de la goutte ignore la souris")
            check(recorder.clicks == before + 1, "\(label) : le clic passe a la fenetre derriere")
        }
        let before = recorder.clicks
        await click(text)
        check(!window.ignoresMouseEvents, "sur le texte : la fenetre de la goutte prend la souris")
        check(recorder.clicks == before, "sur le texte : la goutte garde le clic")
        check(controller.phase != .idle, "sur le texte : la dictee continue")
        await click(cross)
        await wait(300)
        check(controller.phase == .idle, "sur la croix : la dictee est annulee (\(controller.phase))")
        let afterClose = recorder.clicks
        await click(text)
        check(recorder.clicks == afterClose + 1, "goutte refermee : le clic a sa place passe derriere")

        move(to: start)
        behind.orderOut(nil)
        return failures
    }

    /// Clic gauche reel a `point` (coordonnees AppKit), precede d'un deplacement du curseur.
    private static func click(_ point: CGPoint) async {
        move(to: point)
        await wait(120)
        let location = quartz(point)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            await wait(40)
        }
        await wait(150)
    }

    private static func move(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: quartz(point), mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// AppKit (origine en bas a gauche de l'ecran principal) -> Quartz (origine en haut a gauche).
    private static func quartz(_ point: CGPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }
}

/// Fenetre temoin : compte les clics recus.
private final class ClickRecorder: NSView {
    private(set) var clicks = 0
    override func mouseDown(with event: NSEvent) { clicks += 1 }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
#endif
