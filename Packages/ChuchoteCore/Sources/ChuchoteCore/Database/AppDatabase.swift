import Foundation
import GRDB

/// Acces unique a la base SQLite de l'app.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter
    /// Notification distribuee postee apres chaque ecriture, pour qu'un autre
    /// processus de l'app (CLI, extension) recharge.
    public static let didChangeNotification = "fr.vialet.chuchote.databaseDidChange"
    private let notifiesOtherProcesses: Bool

    public init(writer: any DatabaseWriter, notifiesOtherProcesses: Bool) throws {
        self.writer = writer
        self.notifiesOtherProcesses = notifiesOtherProcesses
        try Migrations.migrator.migrate(writer)
        try writer.write { db in
            if try Meta.value("deviceId", in: db) == nil {
                try Meta.set("deviceId", UUID().uuidString.lowercased(), in: db)
            }
        }
    }

    /// Base en memoire, pour les tests.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue(), notifiesOtherProcesses: false)
    }

    /// Emplacement standard : ~/Library/Application Support/Chuchote/chuchote.sqlite,
    /// ou la variable d'environnement CHUCHOTE_DB_PATH / l'argument `-ChuchoteDBPath chemin`
    /// (demo, tests manuels).
    public static var defaultURL: URL {
        let custom = ProcessInfo.processInfo.environment["CHUCHOTE_DB_PATH"]
            ?? UserDefaults.standard.string(forKey: "ChuchoteDBPath")
        if let custom, !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Chuchote", isDirectory: true).appendingPathComponent("chuchote.sqlite")
    }

    /// Ouvre (ou cree) la base sur disque, en mode WAL.
    public static func open(at url: URL = defaultURL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        return try AppDatabase(writer: pool, notifiesOtherProcesses: true)
    }

    public func read<T: Sendable>(_ block: (Database) throws -> T) throws -> T {
        try writer.read(block)
    }

    public func write<T: Sendable>(_ block: (Database) throws -> T) throws -> T {
        let result = try writer.write(block)
        if notifiesOtherProcesses {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(Self.didChangeNotification), object: nil, userInfo: nil,
                deliverImmediately: true)
        }
        return result
    }

    public var deviceId: String {
        (try? read { db in try Meta.value("deviceId", in: db) }) ?? "unknown"
    }
}

/// Petites valeurs persistantes (identifiant d'appareil, reglages du noyau).
public enum Meta {
    public static func value(_ key: String, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key])
    }

    public static func set(_ key: String, _ value: String, in db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", arguments: [key, value])
    }
}
