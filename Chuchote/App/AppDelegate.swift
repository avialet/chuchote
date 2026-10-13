import AppKit
import VialetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Mode capture : ni raccourci global, ni reseau.
        if runSnapshotIfRequested() { return }
        #endif
        HotKeyController.shared.start { WindowSummoner.toggle() }
        // Laisse l'app s'afficher avant le moindre appel reseau.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.assumeIsolated { Updater.shared.checkAutomatically() }
        }
    }

    /// Liens `chuchote://` : ouvre la fenetre principale.
    func application(_ application: NSApplication, open urls: [URL]) {
        WindowSummoner.show()
    }

    /// L'app reste disponible (raccourci global, barre des menus) fenetre fermee.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowSummoner.show() }
        return true
    }
}

#if DEBUG
/// Mode capture sans ecran (voir SnapshotRunner) : `Chuchote -ChuchoteSnapshot <dossier>
/// [-ChuchoteSnapshotSeed 1] [-ChuchoteSnapshotAppearance dark] [-ChuchoteSnapshotOnly a,b]
/// [-ChuchoteSnapshotSize 1000x720]`, avec CHUCHOTE_DB_PATH vers une base jetable. Ecrit
/// `mainWindow`, `settings` et `about` (`-sombre` en sombre) dans le dossier, puis quitte.
extension AppDelegate {
    func runSnapshotIfRequested() -> Bool {
        guard SnapshotRequest.parse(prefix: Brand.name, arguments: CommandLine.arguments) != nil else { return false }
        if UserDefaults.standard.bool(forKey: Brand.key("SnapshotSeed")) { seed() }
        let standard = SnapshotRunner.standardScenarios(mainWindow: { WindowSummoner.mainWindow }, identity: Brand.identity)
        // Scenarios propres a l'app : `+ [SnapshotScenario("detail") { ...; return WindowSummoner.mainWindow }]`.
        return SnapshotRunner.runIfRequested(prefix: Brand.name, scenarios: standard)
    }

    /// Exemples neutres pour les captures, sans donnee personnelle (chaines en echappements ASCII).
    private func seed() {
    }
}
#endif
