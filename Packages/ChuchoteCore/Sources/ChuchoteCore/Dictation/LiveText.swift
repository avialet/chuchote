import CoreGraphics
import Foundation

/// Texte en direct de la goutte : seuls les derniers mots restent visibles.
public enum LiveText {
    /// Fin de `text` en `maxCharacters` caracteres au plus (points de suspension compris), blancs reduits
    /// a une espace. Coupe au debut d'un mot quand c'est possible, sinon dans le mot.
    public static func tail(_ text: String, maxCharacters: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let flat = words.joined(separator: " ")
        guard flat.count > maxCharacters else { return flat }
        guard maxCharacters > 1 else { return "\u{2026}" }
        let keep = flat.suffix(maxCharacters - 1)
        let start = keep.startIndex
        // Coupe au milieu d'un mot : on repart du mot suivant, s'il y en a un.
        if start > flat.startIndex, flat[flat.index(before: start)] != " ",
           let space = keep.firstIndex(of: " ") {
            return "\u{2026}" + keep[keep.index(after: space)...]
        }
        return "\u{2026}" + keep
    }
}

/// Affichage pendant la dictee (Reglages).
public enum ListeningStyle: String, CaseIterable, Sendable {
    /// Goutte noire qui sort de l'encoche, en haut de l'ecran.
    case drop
    /// Pilule en bas de l'ecran (0.1).
    case pill

    public static let defaultValue = ListeningStyle.drop

    public init(stored: String?) {
        self = stored.flatMap(ListeningStyle.init(rawValue:)) ?? .defaultValue
    }
}

/// Place de la goutte en haut d'un ecran (coordonnees AppKit, origine en bas a gauche) : centree sur
/// l'encoche s'il y en a une, sinon au centre du bord haut, sous une bande de la hauteur de la barre des menus.
public struct NotchGeometry: Equatable, Sendable {
    public let screenFrame: CGRect
    public let hasNotch: Bool
    /// Largeur de l'encoche (0 sans encoche).
    public let notchWidth: CGFloat
    /// Hauteur de la rangee du haut (encoche, ou barre des menus) : blob et minuteur y prennent place.
    public let bandHeight: CGFloat
    public let centerX: CGFloat

    /// Bande minimale sans encoche (barre des menus tres fine ou masquee).
    public static let minimumBand: CGFloat = 28

    /// `auxiliaryLeft` et `auxiliaryRight` : `NSScreen.auxiliaryTopLeftArea` et `auxiliaryTopRightArea`.
    public init(screenFrame: CGRect, safeAreaTop: CGFloat, auxiliaryLeft: CGRect?, auxiliaryRight: CGRect?,
                menuBarHeight: CGFloat) {
        self.screenFrame = screenFrame
        if safeAreaTop > 0, let left = auxiliaryLeft, let right = auxiliaryRight, right.minX > left.maxX {
            hasNotch = true
            notchWidth = right.minX - left.maxX
            bandHeight = safeAreaTop
            centerX = (left.maxX + right.minX) / 2
        } else {
            hasNotch = false
            notchWidth = 0
            bandHeight = max(menuBarHeight, Self.minimumBand)
            centerX = screenFrame.midX
        }
    }

    /// Cadre d'une fenetre de taille `size` collee au bord haut, centree sur l'encoche.
    public func windowFrame(size: CGSize) -> CGRect {
        CGRect(x: centerX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Largeur de la goutte ouverte : 420 pt, ou plus pour laisser 100 pt de chaque cote d'une large encoche.
    public static func dropWidth(notchWidth: CGFloat) -> CGFloat {
        max(420, notchWidth + 200)
    }
}
