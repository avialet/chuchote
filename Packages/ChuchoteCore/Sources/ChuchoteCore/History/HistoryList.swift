import Foundation
import VialetKit

/// Dictees d'une meme periode (<< Aujourd'hui >>, << Hier >>...), dans l'ordre de la liste.
public struct DictationSection: Sendable, Equatable, Identifiable {
    public let title: String
    public let items: [Dictation]
    public var id: String { title }

    /// Regroupe une liste deja triee (de la plus recente a la plus ancienne) par `TimeBucket`.
    public static func group(_ dictations: [Dictation], now: Date = Date(),
                             calendar: Calendar = .current) -> [DictationSection] {
        var sections: [DictationSection] = []
        var title: String?
        var items: [Dictation] = []
        for dictation in dictations {
            let label = TimeBucket.bucket(for: dictation.createdAt, now: now, calendar: calendar).sectionLabel
            if label != title {
                if let title, !items.isEmpty { sections.append(DictationSection(title: title, items: items)) }
                title = label
                items = []
            }
            items.append(dictation)
        }
        if let title, !items.isEmpty { sections.append(DictationSection(title: title, items: items)) }
        return sections
    }
}

/// Textes courts des lignes de l'historique (espaces insecables entre nombre et unite).
public enum DictationFormat {
    private static let nbsp = "\u{00A0}"

    /// << 12 s >>, << 1 min >>, << 1 min 05 >>.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        guard total >= 60 else { return "\(total)\(nbsp)s" }
        let minutes = total / 60
        let rest = total % 60
        if rest == 0 { return "\(minutes)\(nbsp)min" }
        return "\(minutes)\(nbsp)min\(nbsp)" + String(format: "%02d", rest)
    }

    /// << 1 250 >> : espace fine insecable des milliers.
    public static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{202F}"
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// << 1 mot >>, << 24 mots >>, << 1 250 mots >>.
    public static func words(_ count: Int) -> String {
        number(count) + nbsp + (count > 1 ? "mots" : "mot")
    }

    /// Horodatage d'une ligne : l'heure (<< 09:05 >>) aujourd'hui et hier, la date ensuite
    /// (<< 8 oct. >>, << 24 dec. 2025 >> une autre annee).
    public static func stamp(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        if calendar.isDate(date, inSameDayAs: now) || calendar.isDate(date, inSameDayAs: yesterday) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "d MMM"
        } else {
            formatter.dateFormat = "d MMM y"
        }
        return formatter.string(from: date)
    }

    /// << Mail - 12 s - 24 mots >> ; sans app cible : << 12 s - 24 mots >>.
    public static func meta(_ dictation: Dictation) -> String {
        var parts: [String] = []
        if let app = dictation.targetApp?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty {
            parts.append(app)
        }
        parts.append(duration(dictation.duration))
        parts.append(words(dictation.words))
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// Ligne choisie au clavier dans une liste d'identifiants.
public enum ListSelection {
    /// Fleches : ligne suivante ou precedente, bornee ; sans choix valide, la premiere.
    public static func move(in ids: [Int64], from current: Int64?, by delta: Int) -> Int64? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return ids.first }
        return ids[min(max(0, index + delta), ids.count - 1)]
    }

    /// Choix a garder apres un rechargement : le meme s'il est encore la ; sinon la ligne qui le
    /// suivait dans `previous` (ou, a defaut, celle qui le precedait) ; sinon la premiere.
    public static func keep(_ current: Int64?, in ids: [Int64], previous: [Int64]) -> Int64? {
        guard !ids.isEmpty else { return nil }
        guard let current else { return ids.first }
        if ids.contains(current) { return current }
        if let index = previous.firstIndex(of: current) {
            let present = Set(ids)
            if let next = previous[(index + 1)...].first(where: present.contains) { return next }
            if let before = previous[..<index].last(where: present.contains) { return before }
        }
        return ids.first
    }
}

/// Nombre de dictees conservees (reglage << Historique >>).
public enum HistoryLimit: Int, CaseIterable, Sendable {
    case hundred = 100
    case fiveHundred = 500
    /// Tout garder.
    case all = 0

    public static let defaultValue: HistoryLimit = .fiveHundred

    /// Valeur rangee dans les reglages ; inconnue : la valeur par defaut.
    public init(stored: Int) {
        self = HistoryLimit(rawValue: stored) ?? Self.defaultValue
    }

    /// Argument de `DictationStore.prune(keepLast:)` ; nil : ne rien purger.
    public var keepLast: Int? { self == .all ? nil : rawValue }
}
