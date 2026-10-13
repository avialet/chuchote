import Foundation
import GRDB

/// Historique des dictees. Ordre : de la plus recente a la plus ancienne.
public struct DictationStore: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Enregistre la dictee et la renvoie avec son identifiant.
    @discardableResult
    public func insert(_ dictation: Dictation) throws -> Dictation {
        try database.write { db in
            var saved = dictation
            try saved.insert(db)
            return saved
        }
    }

    /// Vrai si une dictee a ete supprimee.
    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        try database.write { db in try Dictation.deleteOne(db, key: id) }
    }

    /// Vide l'historique ; renvoie le nombre de dictees supprimees.
    @discardableResult
    public func deleteAll() throws -> Int {
        try database.write { db in try Dictation.deleteAll(db) }
    }

    public func recent(limit: Int = 500) throws -> [Dictation] {
        try database.read { db in try Self.newestFirst.limit(limit).fetchAll(db) }
    }

    /// Dictees dont le texte contient chacun des termes de `query`, sans tenir
    /// compte des accents ni de la casse (`SearchNormalizer`). Requete vide : tout.
    /// Filtrage en Swift sur l'historique entier : simple et suffisant pour
    /// quelques milliers de dictees (l'historique est borne par `prune`).
    public func search(_ query: String) throws -> [Dictation] {
        let terms = SearchNormalizer.normalize(query).split(whereSeparator: \.isWhitespace)
        let all = try database.read { db in try Self.newestFirst.fetchAll(db) }
        guard !terms.isEmpty else { return all }
        return all.filter { dictation in
            let text = SearchNormalizer.normalize(dictation.text)
            return terms.allSatisfy { text.contains($0) }
        }
    }

    /// Nombre de dictees du jour calendaire de `now`.
    public func countToday(now: Date = Date(), calendar: Calendar = .current) throws -> Int {
        let day = Self.day(of: now, calendar: calendar)
        return try database.read { db in try day.fetchCount(db) }
    }

    /// Nombre de mots dictes le jour calendaire de `now`.
    public func wordsToday(now: Date = Date(), calendar: Calendar = .current) throws -> Int {
        let day = Self.day(of: now, calendar: calendar)
        return try database.read { db in
            try day.select(sum(Dictation.Columns.words), as: Int.self).fetchOne(db) ?? 0
        }
    }

    /// Ne garde que les `keepLast` dictees les plus recentes ; renvoie le nombre supprime.
    @discardableResult
    public func prune(keepLast: Int) throws -> Int {
        try database.write { db in
            try db.execute(sql: """
                DELETE FROM dictation WHERE id NOT IN (
                    SELECT id FROM dictation ORDER BY createdAt DESC, id DESC LIMIT ?)
                """, arguments: [max(keepLast, 0)])
            return db.changesCount
        }
    }

    // MARK: - Requetes

    private static var newestFirst: QueryInterfaceRequest<Dictation> {
        Dictation.order(Dictation.Columns.createdAt.desc, Dictation.Columns.id.desc)
    }

    private static func day(of now: Date, calendar: Calendar) -> QueryInterfaceRequest<Dictation> {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return Dictation.filter(Dictation.Columns.createdAt >= start && Dictation.Columns.createdAt < end)
    }
}
