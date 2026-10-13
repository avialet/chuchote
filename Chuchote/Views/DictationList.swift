import ChuchoteCore
import SwiftUI
import VialetKit

/// Historique des dictees : recherche, carte d'accueil tant qu'une autorisation manque, dictees
/// groupees par anciennete. Le champ garde le focus : fleches, ↩ (recopier) et ⌘⌫ (supprimer)
/// agissent sur la ligne choisie.
struct DictationList: View {
    @Environment(AppState.self) private var state
    @AppStorage(DictationController.Keys.directPaste) private var directPaste = true
    @FocusState private var searchFocused: Bool

    var body: some View {
        let steps = state.setupSteps(directPaste: directPaste)
        VStack(spacing: 0) {
            if !state.isHistoryEmpty {
                searchBar
                Divider().overlay(Theme.line)
            }
            if !steps.isEmpty {
                WelcomeCard(steps: steps)
                    .padding(.horizontal, 16)
                    .padding(.top, state.isHistoryEmpty ? 22 : 14)
                    .padding(.bottom, state.isHistoryEmpty ? 0 : 4)
            }
            if state.isHistoryEmpty {
                EmptyHistory()
            } else if state.dictations.isEmpty {
                noResult
            } else {
                list
            }
        }
        .onAppear { searchFocused = true }
    }

    // MARK: - Recherche

    private var searchBar: some View {
        @Bindable var state = state
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            TextField("", text: $state.query,
                      prompt: Text("Rechercher dans les dict\u{00E9}es\u{2026}").foregroundStyle(Theme.inkFaint))
                .textFieldStyle(.plain)
                .font(Theme.ui(15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
                .onKeyPress(.downArrow) { state.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { state.moveSelection(by: -1); return .handled }
                .onKeyPress(.return) {
                    if let dictation = state.selected { state.copy(dictation) }
                    return .handled
                }
                .onKeyPress(.escape) {
                    if state.query.isEmpty { return .ignored }
                    state.query = ""
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    guard press.modifiers.contains(.command), press.key == .delete,
                          let dictation = state.selected else { return .ignored }
                    state.delete(dictation)
                    return .handled
                }
            if !state.query.isEmpty {
                Button { state.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
                .help("Effacer la recherche")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Liste

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(state.sections) { section in
                        Section {
                            ForEach(section.items) { dictation in
                                DictationRow(dictation: dictation,
                                             selected: dictation.id == state.selectedId,
                                             copied: dictation.id == state.copiedId)
                                    .id(dictation.id)
                                    .onTapGesture(count: 2) { state.copy(dictation) }
                                    .onTapGesture {
                                        state.selectedId = dictation.id
                                        searchFocused = true
                                    }
                                    .contextMenu {
                                        Button("Copier") { state.copy(dictation) }
                                        Divider()
                                        Button("Supprimer") { state.delete(dictation) }
                                    }
                            }
                        } header: {
                            SectionHeader(section.title)
                                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.ambientPaper.opacity(0.92))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: state.selectedId) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var noResult: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.inkFaint)
            Text(verbatim: "Aucune dict\u{00E9}e ne contient \u{00AB}\u{00A0}\(state.query)\u{00A0}\u{00BB}.")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// Historique vide : grand blob calme et le geste a faire, avec le raccourci reel.
private struct EmptyHistory: View {
    var body: some View {
        VStack(spacing: 0) {
            Blob(level: 0, mode: .calm)
                .frame(width: 150, height: 150)
            Text(verbatim: "Maintenez \(HotKeyController.shared.shortcut.display) et parlez.")
                .font(Theme.display(22))
                .foregroundStyle(Theme.ink)
                .padding(.top, 14)
            Text("Rel\u{00E2}chez : le texte s\u{2019}\u{00E9}crit l\u{00E0} o\u{00F9} est le curseur.\nUn appui bref \u{00E9}coute sans tenir la touche.")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
