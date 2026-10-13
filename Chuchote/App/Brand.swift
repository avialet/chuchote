import SwiftUI
import VialetKit

/// Identite de l'app : le seul fichier Swift qui connait son nom, ses teintes et son glyphe.
enum Brand {
    static let name = "Chuchote"
    static let displayName = "Chuchote"
    /// Teintes de l'affiche (sites, plaques, DMG, interface), calculees par scripts/teintes.py :
    /// texte `deep` sur `background`. Une teinte par ligne `cle: 0x...` (lue par les scripts du socle).
    static let palette = AccentPalette(accent: 0xD9486B, background: 0xD9486B,
                                       deep: 0x2F000D, pale: 0xFFEDEF,
                                       night: 0x2C1116, nightInk: 0xFCC8CE)
    /// Pictogramme de la plaque : sous-ensemble SVG absolu (M L H V C Q Z), boite 0-100, trait non rempli.
    /// Vide = initiale en repli. Dessiner le trace, verifier avec `swift ../scripts/plaque.swift planche`, puis `make icon`.
    static let glyph = "M 20 46 V 54 M 35 30 V 70 M 50 40 V 60 M 65 22 V 78 M 80 42 V 58"
    /// Trait du glyphe en `deep` plutot qu'en blanc (accent trop clair pour un trait blanc).
    static let strokeDeep = false
    static let identity = AppIdentity(name: name, displayName: displayName, repository: "avialet/chuchote",
                                      bundleIdentifier: "fr.vialet.chuchote", palette: palette, glyph: glyph,
                                      strokeDeep: strokeDeep)
    static let updater = UpdaterConfiguration(identity)

    /// Cles UserDefaults, prefixees par le nom de l'app.
    static func key(_ suffix: String) -> String { identity.key(suffix) }
}

extension Updater {
    static let shared = Updater(configuration: Brand.updater)
}

extension HotKeyController {
    /// ⌃⌥Espace : libre dans le portefeuille (⇧⌘ Pico, ⌃⌥⌘ Allege, ⌃⇧ Pince, ⌥⇧ Brouillon) et pour macOS.
    static let shared = HotKeyController(defaultsKey: Brand.key("HotKey"), logName: Brand.displayName,
                                         initial: .space([.control, .option]))
}
