import SwiftUI
import VialetKit

@main
struct ChuchoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared
    @AppStorage(Brand.key("MenuBar")) private var menuBarVisible = true

    /// Teintes de l'app avant le premier rendu (et police Bricolage Grotesque des titres).
    init() { Theme.configure(Brand.palette) }

    var body: some Scene {
        Window(Brand.displayName, id: "main") {
            MainWindow()
                .environment(state)
                .fontDesign(.rounded)
                .frame(minWidth: 640, minHeight: 420)
                .onAppear { AppearanceChoice.current(defaultsKey: Brand.key("Appearance")).apply(defaultsKey: Brand.key("Appearance")) }
                .captureOpenWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 860, height: 560)
        .commands { AboutCommands(identity: Brand.identity) }

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $menuBarVisible) {
            MenuBarContent().environment(state)
        } label: {
            if Brand.glyph.isEmpty {
                Image(systemName: "app.dashed") // repli tant que le glyphe n'est pas dessine
            } else {
                MenuBarIcon(glyph: Brand.glyph)
            }
        }
    }
}
