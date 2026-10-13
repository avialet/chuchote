import Foundation
import GRDB

/// Schema de la base. Une migration par version du schema, jamais modifiee
/// une fois publiee : on en ajoute une nouvelle (`v2`, `v3`...).
enum Migrations {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        #if DEBUG
        m.eraseDatabaseOnSchemaChange = true
        #endif

        m.registerMigration("v1") { db in
            try db.create(table: "meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            // Tables de l'app : a ajouter ici, par exemple
            // try db.create(table: "item") { t in
            //     t.autoIncrementedPrimaryKey("id")
            //     t.column("createdAt", .datetime).notNull()
            //     t.column("title", .text).notNull()
            // }
        }

        m.registerMigration("v2") { db in
            try db.create(table: "dictation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("duration", .double).notNull()
                t.column("words", .integer).notNull()
                t.column("locale", .text).notNull()
                t.column("targetApp", .text)
            }
        }

        return m
    }
}
