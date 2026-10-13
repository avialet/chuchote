import AppKit

/// Collage direct : simule Cmd-V dans l'app au premier plan. Exige l'autorisation
/// d'accessibilite (Reglages Systeme > Confidentialite et securite > Accessibilite).
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Affiche la demande d'autorisation du systeme.
    @MainActor
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Ecrit `text` dans le presse-papiers general (il y reste : pas de restauration).
    @MainActor
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @discardableResult
    static func simulatePaste() -> Bool {
        guard isTrusted, let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
