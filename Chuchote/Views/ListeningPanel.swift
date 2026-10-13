import SwiftUI
import VialetKit

/// Contenu du panneau d'ecoute : pilule `PanelCard` 360 x 76 (marge d'ombre autour), blob de 48 pt a gauche,
/// marque et etat au centre, touches d'aide a droite (<< esc annuler >> est aussi un bouton).
struct ListeningPanel: View {
    let controller: DictationController

    var body: some View {
        PanelCard {
            HStack(spacing: Theme.Space.m) {
                Blob(level: controller.level, mode: blobMode, fixedTime: controller.fixedBlobTime)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Wordmark.Mini(Brand.displayName)
                    status
                }
                Spacer(minLength: Theme.Space.s)
                hints
            }
            .padding(.horizontal, Theme.Space.l)
            .frame(width: DictationController.pillSize.width, height: DictationController.pillSize.height)
        }
        .padding(DictationController.shadowMargin)
    }

    private var blobMode: Blob.Mode {
        switch controller.phase {
        case .writing: .writing
        case .done: .pasted
        case .failed: .frozen
        case .idle, .listening: .listening
        }
    }

    @ViewBuilder private var status: some View {
        switch controller.phase {
        case .idle:
            label("")
        case .listening(let since):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                label("J\u{2019}\u{00E9}coute")
                ElapsedTime(since: since)
            }
        case .writing:
            label("J\u{2019}\u{00E9}cris\u{2026}")
        case .done(let pasted):
            label(pasted ? "Coll\u{00E9}" : "Copi\u{00E9}\u{00A0}: \u{2318}V")
        case .failed(let message):
            Text(message)
                .font(Theme.ui(12.5, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.ui(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
    }

    @ViewBuilder private var hints: some View {
        switch controller.phase {
        case .listening, .writing:
            VStack(alignment: .trailing, spacing: 5) {
                if case .listening = controller.phase {
                    if controller.isLocked {
                        KeyHint(HotKeyController.shared.shortcut.display, "finir")
                    } else {
                        KeyHint("rel\u{00E2}cher", "coller")
                    }
                }
                Button { controller.cancel() } label: { KeyHint("esc", "annuler") }
                    .buttonStyle(.plain)
                    .help("Annuler la dict\u{00E9}e")
            }
        case .idle, .done, .failed:
            EmptyView()
        }
    }
}

/// Minuteur m:ss en chiffres tabulaires, rafraichi chaque seconde.
private struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(Theme.ui(12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSoft)
        }
    }
}
