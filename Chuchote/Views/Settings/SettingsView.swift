import SwiftUI
import VialetKit

/// Reglages : les quatre cartes standard du kit (raccourci, toujours la, mises a jour, apparence).
/// Les cartes propres a l'app se passent en fermeture finale : `SettingsScreen(...) { SettingsCard(...) }`.
struct SettingsView: View {
    @AppStorage(Brand.key("MenuBar")) private var menuBarVisible = true

    var body: some View {
        SettingsScreen(app: Brand.identity, hotKey: HotKeyController.shared, updater: Updater.shared,
                       menuBarVisible: $menuBarVisible,
                       hotKeyHint: "Depuis n'importe quelle app : affiche ou masque \(Brand.displayName).")
    }
}
