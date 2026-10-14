import AppKit
import VialetKit

/// Icone de barre des menus : masquee quand l'app Vialet est installee (reglage Automatique, Toujours, Jamais).
extension MenuBarPresence {
    static let shared = MenuBarPresence(app: Brand.identity)
}

/// Icone du Dock : seulement pendant qu'une fenetre est ouverte (reglage Toujours).
extension DockPresence {
    static let shared = DockPresence(app: Brand.identity)
}

/// Phrase des Reglages sur les echanges reseau : l'app peut tenir le menu rassembleur des apps vialet.app.
extension HubPresence {
    static let updateNote = "\u{00C9}changes r\u{00E9}seau de \(Brand.displayName) : la derni\u{00E8}re version publi\u{00E9}e sur GitHub et, quand son ic\u{00F4}ne rassemble vos apps vialet.app, celle de ces apps et le catalogue de vialet.app une fois par jour. Aucune donn\u{00E9}e n'est envoy\u{00E9}e."
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
