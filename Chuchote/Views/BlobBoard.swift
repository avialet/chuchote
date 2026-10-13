#if DEBUG
import AppKit
import SwiftUI
import VialetKit

/// Mode capture : planche du blob aux niveaux 0 ; 0,3 ; 0,7 ; 1, en clair et en sombre, a 120 pt
/// (pour juger la forme) et a 48 pt (taille de la pilule), plus l'ecriture.
struct BlobBoard: View {
    static let levels: [Double] = [0, 0.3, 0.7, 1]

    var body: some View {
        VStack(spacing: 0) {
            row(dark: false)
            row(dark: true)
        }
        .fixedSize()
    }

    private func row(dark: Bool) -> some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(Self.levels, id: \.self) { level in
                cell(Text(verbatim: "niveau " + Self.label(level)), level: level, mode: .listening)
            }
            cell(Text(verbatim: "\u{00E9}criture"), level: 0, mode: .writing)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .background(Theme.card)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func cell(_ title: Text, level: Double, mode: Blob.Mode) -> some View {
        VStack(spacing: 12) {
            Blob(level: level, mode: mode, fixedTime: 2.4)
                .frame(width: 120, height: 120)
            Blob(level: level, mode: mode, fixedTime: 2.4)
                .frame(width: 48, height: 48)
            title.font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
    }

    private static func label(_ level: Double) -> String {
        level == 0 || level == 1 ? String(Int(level)) : String(format: "0,%d", Int((level * 10).rounded()))
    }

    /// Fenetre sans bord qui porte la planche (gardee en vie par l'appelant).
    @MainActor
    static func window() -> NSWindow {
        let host = NSHostingView(rootView: BlobBoard())
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: 80, y: 80))
        window.orderFrontRegardless()
        return window
    }
}

/// Mode capture : icone de la barre des menus au repos et pendant l'ecoute, sur une barre claire
/// et une barre sombre (rendu indicatif : le systeme teinte lui-meme l'image modele).
struct MenuBarBoard: View {
    var body: some View {
        VStack(spacing: 0) {
            bar(dark: false)
            bar(dark: true)
        }
        .fixedSize()
    }

    private func bar(dark: Bool) -> some View {
        HStack(spacing: 18) {
            Image(systemName: "wifi").font(.system(size: 14, weight: .medium))
            MenuBarIcon(glyph: Brand.glyph)
            Image(systemName: "wifi").font(.system(size: 14, weight: .medium))
            Image(nsImage: MenuBarLabel.activePlate)
            Text(verbatim: "lun. 13 oct.  14:32").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(dark ? Color.white : Color.black)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(dark ? Color(hex: 0x2B2B2E) : Color(hex: 0xEDEDED))
    }

    @MainActor
    static func window() -> NSWindow {
        let host = NSHostingView(rootView: MenuBarBoard())
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: 80, y: 80))
        window.orderFrontRegardless()
        return window
    }
}
#endif
