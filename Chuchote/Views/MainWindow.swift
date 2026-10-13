import ChuchoteCore
import SwiftUI
import VialetKit

/// Fenetre principale (grammaire de Pince) : barre laterale (marque, compteurs du jour, langue,
/// mise a jour, raccourci) et, a droite, l'historique des dictees.
struct MainWindow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 200)
                .frame(maxHeight: .infinity)
                .background(Theme.sidebar)
            DictationList()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AmbientBackground())
        }
        .onAppear { state.reload() }
        .onChange(of: DictationController.shared.historyVersion) { _, _ in state.reload() }
    }
}

private struct Sidebar: View {
    @Environment(AppState.self) private var state
    @AppStorage(DictationController.Keys.locale) private var locale = DictationController.defaultLocale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(Brand.displayName)
                .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Aujourd'hui")
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    stat(state.countToday, state.countToday > 1 ? "dict\u{00E9}es" : "dict\u{00E9}e")
                    stat(state.wordsToday, state.wordsToday > 1 ? "mots" : "mot")
                }
            }
            .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Langue")
                languageMenu
            }
            .padding(.horizontal, 18)
            .padding(.top, 26)

            Spacer(minLength: 0)
            UpdateBanner(updater: Updater.shared)
            ShortcutFooter(HotKeyController.shared.shortcut)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: DictationFormat.number(value))
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(label)
                .font(Theme.ui(12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var languageMenu: some View {
        Menu {
            Picker("Langue", selection: Binding(get: { LanguageChoices.canonical(locale) },
                                                set: { state.setLocale($0) })) {
                ForEach(LanguageChoices.short(supported: state.supportedLocales, current: locale), id: \.self) { id in
                    Text(LanguageChoices.displayName(id)).tag(id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            SettingsLink { Text("Autres langues\u{2026}") }
        } label: {
            HStack(spacing: 5) {
                Text(LanguageChoices.displayName(locale))
                    .font(Theme.ui(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { state.loadLocales() }
    }
}
