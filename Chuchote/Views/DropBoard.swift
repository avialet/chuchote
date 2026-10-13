#if DEBUG
import AppKit
import ChuchoteCore
import SwiftUI
import VialetKit

/// Mode capture : la goutte sur un faux haut d'ecran (fond d'ecran, barre des menus, encoche) pour juger
/// la forme : encoche seule, ecoute avec texte en direct, ecriture, collage, texte en direct coupe,
/// barre sombre, puis un ecran externe sans encoche.
struct DropBoard: View {
    static let size = CGSize(width: 900, height: 178)
    static let notchWidth: CGFloat = 200
    static let notchHeight: CGFloat = 32

    static let longPreview = DictationController.snapshotPreview
        + " merci et \u{00E0} bient\u{00F4}t et n\u{2019}oublie pas la r\u{00E9}union de mardi matin avec toute l\u{2019}\u{00E9}quipe dans la grande salle"

    private var since: Date { Date().addingTimeInterval(-9) }

    var body: some View {
        VStack(spacing: 2) {
            row("encoche au repos", content: nil)
            row("\u{00E9}coute, texte en direct",
                content: DropContent(phase: .listening(since: since), level: 0.62,
                                     liveText: LiveText.tail(DictationController.snapshotPreview,
                                                             maxCharacters: DictationController.liveTextLimit)))
            row("texte long : le d\u{00E9}but s\u{2019}efface",
                content: DropContent(phase: .listening(since: Date().addingTimeInterval(-24)), level: 0.62,
                                     liveText: LiveText.tail(Self.longPreview,
                                                             maxCharacters: DictationController.liveTextLimit)))
            row("d\u{00E9}but de l\u{2019}\u{00E9}coute",
                content: DropContent(phase: .listening(since: Date().addingTimeInterval(-1)), level: 0.3, liveText: ""))
            row("\u{00E9}criture",
                content: DropContent(phase: .writing, level: 0, liveText: DictationController.snapshotPreview))
            row("coll\u{00E9}",
                content: DropContent(phase: .done(pasted: true), level: 0, liveText: DictationController.snapshotFinal))
            row("sans texte en direct",
                content: DropContent(phase: .listening(since: since), level: 0.62, liveText: "", showsLiveText: false))
            row("barre sombre", dark: true,
                content: DropContent(phase: .listening(since: since), level: 0.62, liveText: "je te confirme notre rendez-vous de jeudi"))
            row("\u{00E9}cran sans encoche", notch: false,
                content: DropContent(phase: .listening(since: since), level: 0.62, liveText: "je te confirme notre rendez-vous de jeudi"))
        }
        .background(Color.black)
        .fixedSize()
    }

    private func row(_ title: String, notch: Bool = true, dark: Bool = false, content: DropContent?) -> some View {
        let frame = CGRect(origin: .zero, size: Self.size)
        let barHeight: CGFloat = notch ? Self.notchHeight : 24
        let half = (Self.size.width - Self.notchWidth) / 2
        let geometry = notch
            ? NotchGeometry(screenFrame: frame, safeAreaTop: Self.notchHeight,
                            auxiliaryLeft: CGRect(x: 0, y: Self.size.height - barHeight, width: half, height: barHeight),
                            auxiliaryRight: CGRect(x: half + Self.notchWidth, y: Self.size.height - barHeight,
                                                   width: half, height: barHeight),
                            menuBarHeight: barHeight)
            : NotchGeometry(screenFrame: frame, safeAreaTop: 0, auxiliaryLeft: nil, auxiliaryRight: nil,
                            menuBarHeight: barHeight)
        let window = DropPanelController.windowSize(for: geometry)
        return ZStack(alignment: .top) {
            wallpaper(dark: dark)
            menuBar(height: barHeight, dark: dark)
            if notch {
                DropShape(flare: 6, bottomRadius: 9)
                    .fill(.black)
                    .frame(width: Self.notchWidth + 12, height: Self.notchHeight)
            }
            if let content {
                DropView(content: content, geometry: geometry, expanded: true)
                    .frame(width: window.width, height: window.height)
            }
            Text(title)
                .font(Theme.ui(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.35)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(10)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private func wallpaper(dark: Bool) -> some View {
        LinearGradient(colors: dark ? [Color(hex: 0x1D2440), Color(hex: 0x3A2346)]
                                    : [Color(hex: 0x9FC3E8), Color(hex: 0xE9C6D6)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func menuBar(height: CGFloat, dark: Bool) -> some View {
        let ink: Color = dark ? .white.opacity(0.92) : .black.opacity(0.82)
        return HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 14, weight: .semibold))
            Text("Notes").font(.system(size: 13, weight: .bold))
            Text("Fichier").font(.system(size: 13))
            Text("\u{00C9}dition").font(.system(size: 13))
            Text("Format").font(.system(size: 13))
            Spacer()
            Image(systemName: "wifi").font(.system(size: 13, weight: .medium))
            Image(systemName: "battery.75percent").font(.system(size: 14))
            Text("mar. 13 oct. 23:40").font(.system(size: 13))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 18)
        .frame(height: height)
        .background(dark ? Color.black.opacity(0.25) : Color.white.opacity(0.3))
    }

    static func window() -> NSWindow {
        let host = NSHostingView(rootView: DropBoard().fontDesign(.rounded))
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
