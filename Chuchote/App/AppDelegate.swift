import AppKit
import ChuchoteCore
import VialetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Mode capture et essai du moteur : ni raccourci global, ni micro, ni reseau.
        if runSnapshotIfRequested() || EngineCheck.runIfRequested() || FlowCheck.runIfRequested()
            || ClickCheck.runIfRequested() { return }
        if writeHubManifestIfRequested() { return }
        #endif
        _ = DockPresence.shared
        HubPresence.start(menuBar: MenuBarPresence.shared, actions: AppActions.shared, updater: Updater.shared)
        // Le raccourci dicte ; la fenetre principale s'ouvre par le menu (le Dock la montre ensuite).
        DictationController.shared.start()
        // Laisse l'app s'afficher avant le moindre appel reseau.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.runOnMainThread { Updater.shared.checkAutomatically() }
        }
    }

    /// Liens `chuchote://` : `chuchote://dicter` lance une ecoute verrouillee, `chuchote://update` verifie
    /// les mises a jour ; le reste ouvre la fenetre principale.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where !AppActions.shared.handle(url) { WindowSummoner.show() }
    }

    /// L'app reste disponible (raccourci global, barre des menus) fenetre fermee.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowSummoner.show() }
        return true
    }
}

#if DEBUG
extension AppDelegate {
    /// `Chuchote -ChuchoteHubManifest <dossier>` : ecrit la fiche pour Vialet dans le dossier (sans la
    /// condition du dossier Applications, sans prevenir Vialet), imprime son chemin et quitte.
    func writeHubManifestIfRequested() -> Bool {
        guard let path = UserDefaults.standard.string(forKey: Brand.key("HubManifest")) else { return false }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try AppActions.shared.manifest().write(to: directory)
            print("fiche : \(HubManifest.fileURL(bundleIdentifier: Brand.identity.bundleIdentifier, in: directory).path)")
        } catch {
            print("fiche non ecrite : \(error)")
        }
        exit(0)
    }
}

/// Mode capture sans ecran (voir SnapshotRunner) : `Chuchote -ChuchoteSnapshot <dossier>
/// [-ChuchoteSnapshotSeed 1] [-ChuchoteSnapshotAppearance dark] [-ChuchoteSnapshotOnly a,b]
/// [-ChuchoteSnapshotSize 1000x720]`, avec CHUCHOTE_DB_PATH vers une base jetable. Ecrit
/// `mainWindow`, `settings`, `about`, `listening` et `writing` (pilule d'ecoute, moteur factice et
/// niveau fige), `drop`, `dropWriting` et `dropDone` (goutte d'encoche avec texte en direct fictif),
/// `drop-encoche` (planche de la goutte sur un faux haut d'ecran), `blob-niveaux` (planche du blob), `empty` (historique vide) et `welcome` (carte
/// d'accueil, historique vide) (`-sombre` en sombre) dans le dossier, puis quitte. Autorisations et
/// langue figees : tout en ordre, sauf pour `welcome`.
extension AppDelegate {
    func runSnapshotIfRequested() -> Bool {
        guard SnapshotRequest.parse(prefix: Brand.name, arguments: CommandLine.arguments) != nil else { return false }
        let state = AppState.shared
        let locales = ["fr_FR", "en_US", "en_GB", "de_DE", "es_ES", "it_IT"]
        state.freezeSetup(microphone: .authorized, accessibilityTrusted: true, language: .ready, locales: locales)
        if UserDefaults.standard.bool(forKey: Brand.key("SnapshotSeed")) { seed(into: state.store) }
        state.reload()
        let standard = SnapshotRunner.standardScenarios(mainWindow: { WindowSummoner.mainWindow }, identity: Brand.identity)
        let dictation = DictationController.snapshot()
        let drop = DictationController.snapshot(style: .drop)
        func panel() -> NSWindow? { NSApp.windows.first { $0 is FloatingPanel && $0.isVisible } }
        let panels = [
            // Remplace le scenario standard : le panneau n'existe qu'une fois montre.
            SnapshotScenario("floatingPanel") {
                await dictation.snapshotListening()
                return panel()
            },
            SnapshotScenario("listening") {
                await dictation.snapshotListening()
                return panel()
            },
            SnapshotScenario("writing") {
                await dictation.snapshotWriting()
                return panel()
            },
            SnapshotScenario("drop") {
                await drop.snapshotListening()
                return drop.dropWindow
            },
            SnapshotScenario("dropWriting") {
                await drop.snapshotWriting()
                return drop.dropWindow
            },
            SnapshotScenario("dropDone") {
                await drop.snapshotDone()
                return drop.dropWindow
            },
            SnapshotScenario("drop-ouverture") {
                // Images de l'ouverture (ms apres l'appui) a cote de la capture finale.
                let folder = CommandLine.arguments.firstIndex(of: "-\(Brand.name)Snapshot")
                    .map { URL(fileURLWithPath: CommandLine.arguments[$0 + 1]) }
                let opening = DictationController.snapshot(style: .drop)
                opening.keyPressed()
                var elapsed = 0
                for ms in [16, 60, 120, 200, 320] {
                    try await Task.sleep(for: .milliseconds(ms - elapsed))
                    elapsed = ms
                    if let folder, let window = opening.dropWindow {
                        try? WindowSnapshot.write(window, to: folder.appendingPathComponent("drop-ouverture-\(ms).png"))
                    }
                }
                try await Task.sleep(for: .milliseconds(300))
                return opening.dropWindow
            },
            SnapshotScenario("drop-encoche") {
                let window = DropBoard.window()
                try await Task.sleep(for: .milliseconds(400))
                return window
            },
            SnapshotScenario("blob-niveaux") {
                let window = BlobBoard.window()
                try await Task.sleep(for: .milliseconds(400))
                return window
            },
            SnapshotScenario("barre-des-menus") {
                let window = MenuBarBoard.window()
                try await Task.sleep(for: .milliseconds(300))
                return window
            },
            SnapshotScenario("empty") {
                state.clearHistory()
                try await Task.sleep(for: .milliseconds(600))
                return WindowSummoner.mainWindow
            },
            SnapshotScenario("welcome") {
                state.clearHistory()
                state.freezeSetup(microphone: .notDetermined, accessibilityTrusted: false,
                                  language: .installing(0.62), locales: locales)
                try await Task.sleep(for: .milliseconds(600))
                return WindowSummoner.mainWindow
            },
        ]
        return SnapshotRunner.runIfRequested(prefix: Brand.name, scenarios: standard + panels)
    }

    /// Huit dictees fictives et neutres sur deux semaines, sans donnee personnelle (chaines en
    /// echappements ASCII), mises au propre par Polish comme une vraie dictee.
    private func seed(into store: DictationStore) {
        let now = Date()
        let samples: [(ago: TimeInterval, text: String, duration: TimeInterval, app: String, locale: String)] = [
            (40, "pense \u{00E0} rappeler le garage avant midi pour le contr\u{00F4}le technique", 4.2, "Rappels", "fr_FR"),
            (25 * 60, "bonjour Claire, je te confirme notre rendez-vous de jeudi \u{00E0} 10 h 30. Peux-tu apporter le dossier du projet et les chiffres du trimestre ? Merci et \u{00E0} bient\u{00F4}t", 9.5, "Mail", "fr_FR"),
            (3 * 3600, "id\u{00E9}es pour l'atelier : commencer par un tour de table, garder vingt minutes pour les questions, envoyer le compte rendu le soir m\u{00EA}me", 11.2, "Notes", "fr_FR"),
            (26 * 3600, "hi Tom, thanks for the quick reply. Friday works for me, let's meet at the station caf\u{00E9} at nine", 7.8, "Mail", "en_US"),
            (29 * 3600, "liste de courses : farine, \u{0153}ufs, citrons, un bouquet de basilic et du caf\u{00E9} en grains", 6.3, "Rappels", "fr_FR"),
            (3 * 86400, "compte rendu de la r\u{00E9}union d'\u{00E9}quipe : le planning de novembre est valid\u{00E9}, la mise en ligne du nouveau site est repouss\u{00E9}e d'une semaine pour finir les tests, et chacun relit la documentation avant vendredi. Prochaine r\u{00E9}union mardi \u{00E0} 9 h, m\u{00EA}me salle, avec les maquettes imprim\u{00E9}es et la liste des questions ouvertes", 24.6, "Pages", "fr_FR"),
            (5 * 86400, "r\u{00E9}server une table pour quatre samedi soir, de pr\u{00E9}f\u{00E9}rence en terrasse", 4.4, "Messages", "fr_FR"),
            (12 * 86400, "penser \u{00E0} sauvegarder les photos de vacances sur le disque externe", 5.0, "Notes", "fr_FR"),
        ]
        for sample in samples.reversed() {
            let text = Polish.apply(sample.text, locale: sample.locale, frenchTypography: true)
            _ = try? store.insert(Dictation(text: text, createdAt: now.addingTimeInterval(-sample.ago),
                                            duration: sample.duration, locale: sample.locale, targetApp: sample.app))
        }
    }
}
#endif
