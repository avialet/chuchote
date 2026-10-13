import ChuchoteCore
import SwiftUI
import VialetKit

/// Ligne de l'historique : le texte (3 lignes au plus), puis << app cible · duree · mots >> et
/// l'horodatage ; << Copie >> remplace l'horodatage un instant apres une recopie.
struct DictationRow: View {
    let dictation: Dictation
    let selected: Bool
    let copied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dictation.text)
                .font(Theme.ui(13.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text(verbatim: DictationFormat.meta(dictation))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if copied {
                    Label("Copi\u{00E9}", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .font(Theme.ui(11.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
                } else {
                    Text(verbatim: DictationFormat.stamp(dictation.createdAt))
                        .foregroundStyle(Theme.inkFaint)
                        .monospacedDigit()
                }
            }
            .font(Theme.ui(11.5, weight: .medium))
            .animation(.easeOut(duration: 0.15), value: copied)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            .fill(selected ? Theme.accentSelection : .clear))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }
}
