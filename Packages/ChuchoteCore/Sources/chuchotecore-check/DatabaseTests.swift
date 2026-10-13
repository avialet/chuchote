import Foundation
import ChuchoteCore

let databaseTests: (String, [Test]) = ("Database", [
    Test("inMemoryDatabaseHasDeviceId") {
        let db = try AppDatabase.inMemory()
        expectEqual(db.deviceId.count, 36)
        expectEqual(db.deviceId, db.deviceId.lowercased())
    },
    Test("metaRoundTrip") {
        let db = try AppDatabase.inMemory()
        try db.write { try Meta.set("theme", "dark", in: $0) }
        expectEqual(try db.read { try Meta.value("theme", in: $0) }, "dark")
        expect(try db.read { try Meta.value("absent", in: $0) } == nil)
    },
])
