import Foundation
import GRDB

/// Une dictee conservee dans l'historique.
public struct Dictation: Codable, Sendable, Equatable, Identifiable {
    /// Attribue par la base a l'insertion.
    public var id: Int64?
    public var text: String
    public var createdAt: Date
    /// Duree d'ecoute, en secondes.
    public var duration: TimeInterval
    public var words: Int
    /// Langue de la dictee (`fr-FR`, `en-US`...).
    public var locale: String
    /// Nom de l'app au premier plan au moment de la dictee, si connu.
    public var targetApp: String?

    /// `words` est calcule depuis `text`.
    public init(id: Int64? = nil, text: String, createdAt: Date = Date(), duration: TimeInterval,
                locale: String, targetApp: String? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.duration = duration
        self.words = Self.wordCount(text)
        self.locale = locale
        self.targetApp = targetApp
    }

    /// Nombre de mots : morceaux separes par des blancs (insecables compris) qui
    /// contiennent au moins une lettre ou un chiffre. `l'eau`, `peut-etre` et
    /// `10:30` comptent pour un ; une ponctuation isolee ne compte pas.
    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .count
    }
}

extension Dictation: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "dictation"

    /// Colonnes pour les requetes GRDB (`Dictation.Columns.createdAt`...).
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let text = Column(CodingKeys.text)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let duration = Column(CodingKeys.duration)
        public static let words = Column(CodingKeys.words)
        public static let locale = Column(CodingKeys.locale)
        public static let targetApp = Column(CodingKeys.targetApp)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
