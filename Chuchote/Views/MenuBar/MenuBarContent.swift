import AppKit
import ChuchoteCore
import SwiftUI
import VialetKit

struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @AppStorage(DictationController.Keys.locale) private var locale = DictationController.defaultLocale

    var body: some View {
        let dictation = DictationController.shared
        Button(dictation.isLocked ? "Finir la dict\u{00E9}e" : "Dicter") { dictation.toggleLockedDictation() }
            .disabled(!dictation.isLocked && dictation.phase != .idle)
        Picker("Langue", selection: Binding(get: { LanguageChoices.canonical(locale) },
                                            set: { state.setLocale($0) })) {
            ForEach(LanguageChoices.short(supported: state.supportedLocales, current: locale), id: \.self) { id in
                Text(LanguageChoices.displayName(id)).tag(id)
            }
        }
        .onAppear { state.loadLocales() }
        Divider()
        Button("Historique") { WindowSummoner.show() }
        SettingsLink { Text("R\u{00E9}glages\u{2026}") }
        Button("\u{00C0} propos de \(Brand.displayName)") { AboutPanel.show(Brand.identity) }
        Divider()
        Button("Quitter") { NSApp.terminate(nil) }
    }
}

/// Icone de la barre des menus : le glyphe en image modele au repos ; pendant l'ecoute et
/// l'ecriture, la plaque pleine a l'accent (le kit n'a pas de variante remplie de `MenuBarIcon`).
struct MenuBarLabel: View {
    var body: some View {
        switch DictationController.shared.phase {
        case .listening, .writing:
            Image(nsImage: Self.activePlate)
        case .idle, .done, .failed:
            MenuBarIcon(glyph: Brand.glyph)
        }
    }

    /// Plaque de 16 pt (rendue a 3x), comme une icone d'app miniature.
    static let activePlate: NSImage = {
        let image = GlyphImage.plate(Brand.palette, glyph: Brand.glyph, pixels: 48, strokeDeep: Brand.strokeDeep)
        image.size = NSSize(width: 16, height: 16)
        return image
    }()
}
