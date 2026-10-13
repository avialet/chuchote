import ChuchoteCore
import SwiftUI
import VialetKit

/// Reglages : les quatre cartes standard du kit, puis << Dictee >> et << Historique >>.
struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        SettingsScreen(app: Brand.identity, hotKey: HotKeyController.shared, updater: Updater.shared,
                       menuBar: MenuBarPresence.shared,
                       hotKeyHint: "Maintenir pour dicter, appui bref pour une \u{00E9}coute verrouill\u{00E9}e.",
                       width: 480) {
            DictationCard()
            HistoryCard()
        }
        // Interrupteurs et selection a l'accent de l'app plutot qu'au bleu du systeme.
        .tint(Theme.accent)
        .onAppear {
            state.loadLocales()
            state.refreshSetup()
        }
    }
}

private struct DictationCard: View {
    @Environment(AppState.self) private var state
    @AppStorage(DictationController.Keys.locale) private var locale = DictationController.defaultLocale
    @AppStorage(DictationController.Keys.directPaste) private var directPaste = true
    @AppStorage(DictationController.Keys.frenchTypography) private var frenchTypography = true
    @AppStorage(DictationController.Keys.listeningStyle) private var listeningStyle = ListeningStyle.defaultValue.rawValue
    @AppStorage(DictationController.Keys.liveText) private var liveText = true

    var body: some View {
        SettingsCard(icon: "waveform", color: Theme.accent, title: "Dict\u{00E9}e") {
            Picker("Langue", selection: Binding(get: { LanguageChoices.canonical(locale) },
                                                set: { state.setLocale($0) })) {
                ForEach(LanguageChoices.all(supported: state.supportedLocales, current: locale), id: \.self) { id in
                    Text(LanguageChoices.displayName(id)).tag(id)
                }
            }
            .fixedSize()
            languageStatus

            Picker("Affichage pendant la dict\u{00E9}e", selection: $listeningStyle) {
                Text("Goutte d\u{2019}encoche").tag(ListeningStyle.drop.rawValue)
                Text("Pilule en bas").tag(ListeningStyle.pill.rawValue)
            }
            .fixedSize()
            .onChange(of: listeningStyle) { DictationController.shared.displaySettingsChanged() }
            Toggle("Afficher le texte en direct", isOn: $liveText)
                .disabled(ListeningStyle(stored: listeningStyle) == .pill)
                .onChange(of: liveText) { DictationController.shared.displaySettingsChanged() }
            note(ListeningStyle(stored: listeningStyle) == .pill
                 ? "Une pilule en bas de l\u{2019}\u{00E9}cran, sans texte en direct."
                 : "Une goutte sort de l\u{2019}encoche (en haut au centre sur un \u{00E9}cran sans encoche). Le texte en direct est un aper\u{00E7}u\u{00A0}: le texte coll\u{00E9} vient du mod\u{00E8}le complet.")

            Toggle("Coller l\u{00E0} o\u{00F9} est le curseur", isOn: $directPaste)
                .onChange(of: directPaste) { _, on in
                    if on && !Paster.isTrusted { Paster.requestTrust() }
                    state.refreshSetup()
                }
            pasteStatus

            Toggle("Typographie fran\u{00E7}aise", isOn: $frenchTypography)
            note("Espaces fines avant ; : ! ?, apostrophes et guillemets typographiques. En fran\u{00E7}ais seulement.")
        }
    }

    @ViewBuilder private var languageStatus: some View {
        switch state.language {
        case .needsInstall:
            HStack(spacing: 6) {
                Text("Mod\u{00E8}le de dict\u{00E9}e \u{00E0} installer (t\u{00E9}l\u{00E9}chargement Apple, une seule fois).")
                    .font(Theme.ui(12)).foregroundStyle(Theme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Installer") { DictationController.shared.installLanguage() }
                    .buttonStyle(.link).font(Theme.ui(12, weight: .semibold))
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressBar(fraction: state.language.progress ?? 0).frame(width: 120)
                note("Installation\u{2026} \(Int(((state.language.progress ?? 0) * 100).rounded()))\u{00A0}%")
            }
        case .unsupported:
            Text("Langue non prise en charge par la dict\u{00E9}e de macOS.")
                .font(Theme.ui(12)).foregroundStyle(Theme.coral)
        case .failed(let message):
            Text(message).font(Theme.ui(12)).foregroundStyle(Theme.coral)
                .fixedSize(horizontal: false, vertical: true)
        case .ready, .preparing:
            note("Reconnaissance sur ce Mac, sans r\u{00E9}seau.")
        }
    }

    @ViewBuilder private var pasteStatus: some View {
        if !directPaste {
            note("Le texte reste dans le presse-papiers\u{00A0}: collez-le avec \u{2318}V.")
        } else if state.accessibilityTrusted {
            note("Le texte est coll\u{00E9} et reste aussi dans le presse-papiers.")
        } else {
            HStack(spacing: 6) {
                Text("\u{00C0} autoriser dans R\u{00E9}glages Syst\u{00E8}me \u{203A} Confidentialit\u{00E9} et s\u{00E9}curit\u{00E9} \u{203A} Accessibilit\u{00E9}.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ouvrir") { AppState.openPrivacySettings("Privacy_Accessibility") }
                    .buttonStyle(.link).font(Theme.ui(12, weight: .semibold))
            }
        }
    }
}

private struct HistoryCard: View {
    @Environment(AppState.self) private var state
    @AppStorage(DictationController.Keys.keepHistory) private var keepHistory = true
    @AppStorage(DictationController.Keys.historyLimit) private var limit = HistoryLimit.defaultValue.rawValue
    @State private var confirmClear = false

    var body: some View {
        SettingsCard(icon: "clock.arrow.circlepath", color: Theme.stone, title: "Historique") {
            Toggle("Conserver les dict\u{00E9}es", isOn: $keepHistory)
            Picker("Garder", selection: Binding(get: { HistoryLimit(stored: limit) },
                                                set: { limit = $0.rawValue; state.applyHistoryLimit($0) })) {
                Text("Les 100 derni\u{00E8}res").tag(HistoryLimit.hundred)
                Text("Les 500 derni\u{00E8}res").tag(HistoryLimit.fiveHundred)
                Text("Toutes").tag(HistoryLimit.all)
            }
            .fixedSize()
            .disabled(!keepHistory)
            Text(keepHistory
                 ? "Tout reste sur ce Mac. Chaque dict\u{00E9}e reste aussi dans le presse-papiers jusqu\u{2019}\u{00E0} la copie suivante."
                 : "Les prochaines dict\u{00E9}es ne seront pas enregistr\u{00E9}es. Celles d\u{00E9}j\u{00E0} gard\u{00E9}es restent jusqu\u{2019}\u{00E0} ce que vous les effaciez.")
                .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("Effacer l\u{2019}historique\u{2026}") { confirmClear = true }
                .controlSize(.small)
                .disabled(state.dictations.isEmpty && state.query.isEmpty)
                .confirmationDialog("Effacer toutes les dict\u{00E9}es\u{00A0}?", isPresented: $confirmClear) {
                    Button("Effacer", role: .destructive) { state.clearHistory() }
                } message: {
                    Text("Elles seront supprim\u{00E9}es de ce Mac. Cette action est d\u{00E9}finitive.")
                }
        }
        .onAppear { state.reload() }
    }
}

/// Texte d'aide des cartes.
@MainActor
private func note(_ text: String) -> some View {
    Text(text)
        .font(Theme.ui(12))
        .foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)
}
