import ChuchoteCore
import SwiftUI
import VialetKit

/// Carte d'accueil : un point par autorisation ou ressource manquante, chacun avec le bouton qui la
/// demande ou ouvre la bonne page des Reglages Systeme. Disparait quand tout est en ordre.
struct WelcomeCard: View {
    @Environment(AppState.self) private var state
    let steps: [SetupStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Avant de dicter")
                .font(Theme.display(17))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 4)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Divider().overlay(Theme.line) }
                row(step)
                    .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Theme.line, lineWidth: 1))
    }

    @ViewBuilder private func row(_ step: SetupStep) -> some View {
        switch step {
        case .microphone(let denied):
            line(icon: "mic.fill", title: "Micro",
                 detail: denied
                    ? "Acc\u{00E8}s refus\u{00E9}. \u{00C0} rouvrir dans R\u{00E9}glages Syst\u{00E8}me \u{203A} Confidentialit\u{00E9} et s\u{00E9}curit\u{00E9} \u{203A} Micro."
                    : "Chuchote n\u{2019}\u{00E9}coute que pendant que vous dictez. Rien ne quitte ce Mac.") {
                if denied {
                    action("Ouvrir les R\u{00E9}glages") { AppState.openPrivacySettings("Privacy_Microphone") }
                } else {
                    action("Autoriser", primary: true) { state.requestMicrophone() }
                }
            }
        case .accessibility:
            line(icon: "character.cursor.ibeam", title: "Collage direct",
                 detail: "Pour \u{00E9}crire l\u{00E0} o\u{00F9} est le curseur. Sans cette autorisation (Accessibilit\u{00E9}), le texte reste dans le presse-papiers\u{00A0}: \u{2318}V.") {
                action("Ouvrir les R\u{00E9}glages") {
                    Paster.requestTrust()
                    AppState.openPrivacySettings("Privacy_Accessibility")
                }
            }
        case .language(let readiness):
            language(readiness)
        }
    }

    @ViewBuilder private func language(_ readiness: LanguageReadiness) -> some View {
        let name = LanguageChoices.displayName(state.currentLocale)
        switch readiness {
        case .installing:
            line(icon: "globe", title: name,
                 detail: "T\u{00E9}l\u{00E9}chargement du mod\u{00E8}le de dict\u{00E9}e (Apple, une seule fois).") {
                HStack(spacing: 8) {
                    ProgressBar(fraction: readiness.progress ?? 0)
                        .frame(width: 72)
                    Text(verbatim: "\(Int(((readiness.progress ?? 0) * 100).rounded()))\u{00A0}%")
                        .font(Theme.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
        case .unsupported:
            line(icon: "globe", title: name,
                 detail: "Langue non prise en charge par la dict\u{00E9}e de macOS. Choisissez-en une autre.") {
                SettingsLink { pill("R\u{00E9}glages\u{2026}", primary: false) }
                    .buttonStyle(.plain)
            }
        case .failed(let message):
            line(icon: "globe", title: name, detail: message) {
                action("R\u{00E9}essayer") { DictationController.shared.reloadEngine() }
            }
        case .needsInstall, .ready, .preparing:
            line(icon: "globe", title: name,
                 detail: "Le mod\u{00E8}le de dict\u{00E9}e de cette langue n\u{2019}est pas encore sur ce Mac (t\u{00E9}l\u{00E9}chargement Apple, une seule fois).") {
                action("Installer", primary: true) { DictationController.shared.installLanguage() }
            }
        }
    }

    private func line<Trailing: View>(icon: String, title: String, detail: String,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }

    private func action(_ title: String, primary: Bool = false, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) { pill(title, primary: primary) }
            .buttonStyle(.plain)
    }

    /// Bouton en pastille : principal (comme sur les sites) ou discret.
    private func pill(_ title: String, primary: Bool) -> some View {
        Text(title)
            .font(Theme.ui(12, weight: .semibold))
            .foregroundStyle(primary ? Theme.accentPrimaryButtonForeground : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(primary ? Theme.accentPrimaryButtonBackground : Theme.ink.opacity(0.07)))
            .fixedSize()
            .contentShape(Capsule())
    }
}

/// Barre de progression fine a l'accent (la tinte de ProgressView ne s'applique pas partout).
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.08))
                Capsule().fill(Theme.accent)
                    .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
    }
}
