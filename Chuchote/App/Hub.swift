import AppKit
import VialetKit

/// Icone de barre des menus : masquee quand l'app Vialet est installee (reglage Automatique, Toujours, Jamais).
extension MenuBarPresence {
    static let shared = MenuBarPresence(app: Brand.identity)
}

/// Action rapide (`chuchote://dicter`), proposee par l'app Vialet dans son menu.
extension AppActions {
    static let shared: AppActions = {
        let actions = AppActions(Brand.identity, open: { WindowSummoner.show() },
                                 checkForUpdates: { WindowSummoner.show(); Updater.shared.check() })
        actions.register(AppAction("dicter", title: "Dicter", symbol: "mic")) {
            Task { await QuickDictation.toggle(DictationController.shared) }
        }
        return actions
    }()
}

/// « Dicter » depuis un lien : ecoute verrouillee, comme l'entree « Dicter » du menu (un second appel
/// la finit).
@MainActor
enum QuickDictation {
    static func toggle(_ controller: DictationController) async {
        // Ouvrir le lien active Chuchote : le texte serait colle dans Chuchote. On rend la main a l'app
        // d'avant (celle ou l'on dicte), puis on ecoute.
        try? await Task.sleep(for: .milliseconds(250))
        if NSApp.isActive {
            NSApp.hide(nil)
            try? await Task.sleep(for: .milliseconds(200))
        }
        controller.toggleLockedDictation()
    }
}
