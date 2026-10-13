import Foundation
import ChuchoteCore

private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

/// Date a la seconde (la base garde les millisecondes, pas au-dela).
private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
    paris.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

private func makeStore() throws -> DictationStore {
    DictationStore(database: try AppDatabase.inMemory())
}

@discardableResult
private func add(_ store: DictationStore, _ text: String, at createdAt: Date,
                 app: String? = nil) throws -> Dictation {
    try store.insert(Dictation(text: text, createdAt: createdAt, duration: 2.5, locale: "fr-FR", targetApp: app))
}

let dictationStoreTests: (String, [Test]) = ("DictationStore", [
    Test("wordCount") {
        expectEqual(Dictation.wordCount(""), 0)
        expectEqual(Dictation.wordCount("   \n "), 0)
        expectEqual(Dictation.wordCount("  bonjour   tout le\nmonde "), 4)
        expectEqual(Dictation.wordCount("l'eau, c'est \u{E7}a\u{202F}?"), 3)
        expectEqual(Dictation.wordCount("\u{AB}\u{00A0}oui\u{00A0}\u{BB} \u{2014} 10:30 peut-\u{EA}tre"), 3)
    },
    Test("initCountsWords") {
        let d = Dictation(text: "un deux trois", duration: 1, locale: "fr-FR")
        expectEqual(d.words, 3)
        expect(d.id == nil)
        expect(d.targetApp == nil)
    },
    Test("insertAssignsIdAndRoundTrips") {
        let store = try makeStore()
        let saved = try add(store, "Bonjour tout le monde.", at: date(2026, 10, 13), app: "Mail")
        expect(saved.id != nil)
        let other = try add(store, "Sans app.", at: date(2026, 10, 13, 13))
        expect(other.id != saved.id)
        let all = try store.recent()
        expectEqual(all, [other, saved])
        expectEqual(all.last?.targetApp, "Mail")
        expectEqual(all.last?.words, 4)
        expectEqual(all.last?.duration, 2.5)
        expectEqual(all.last?.locale, "fr-FR")
        expect(all.first?.targetApp == nil)
    },
    Test("recentIsNewestFirstWithLimit") {
        let store = try makeStore()
        try add(store, "ancien", at: date(2026, 10, 1))
        try add(store, "recent", at: date(2026, 10, 12))
        try add(store, "milieu", at: date(2026, 10, 5))
        expectEqual(try store.recent().map(\.text), ["recent", "milieu", "ancien"])
        expectEqual(try store.recent(limit: 2).map(\.text), ["recent", "milieu"])
    },
    Test("deleteById") {
        let store = try makeStore()
        let a = try add(store, "a", at: date(2026, 10, 1))
        try add(store, "b", at: date(2026, 10, 2))
        expect(try store.delete(id: a.id!))
        expect(!(try store.delete(id: a.id!)))
        expectEqual(try store.recent().map(\.text), ["b"])
    },
    Test("deleteAll") {
        let store = try makeStore()
        try add(store, "a", at: date(2026, 10, 1))
        try add(store, "b", at: date(2026, 10, 2))
        expectEqual(try store.deleteAll(), 2)
        expect(try store.recent().isEmpty)
    },
    Test("searchIgnoresAccentsAndCase") {
        let store = try makeStore()
        try add(store, "R\u{E9}union \u{E0} l\u{2019}\u{E9}cole demain.", at: date(2026, 10, 1))
        try add(store, "Courses du march\u{E9}.", at: date(2026, 10, 2))
        try add(store, "Rappeler l\u{2019}\u{C9}COLE.", at: date(2026, 10, 3))
        expectEqual(try store.search("reunion").map(\.text), ["R\u{E9}union \u{E0} l\u{2019}\u{E9}cole demain."])
        expectEqual(try store.search("ECOLE").count, 2)
        expectEqual(try store.search("MARCHE").map(\.text), ["Courses du march\u{E9}."])
        // Tous les termes doivent figurer, dans n'importe quel ordre.
        expectEqual(try store.search("  ecole   reunion ").count, 1)
        expect(try store.search("piscine").isEmpty)
        // Requete vide : tout, du plus recent au plus ancien.
        expectEqual(try store.search("  ").count, 3)
        expectEqual(try store.search("").first?.text, "Rappeler l\u{2019}\u{C9}COLE.")
    },
    Test("todayCountersUseCalendarDay") {
        let store = try makeStore()
        let now = date(2026, 10, 13, 15)
        try add(store, "hier soir tard", at: date(2026, 10, 12, 23, 59))
        try add(store, "minuit pile", at: date(2026, 10, 13, 0, 0))
        try add(store, "en journee aujourd'hui", at: date(2026, 10, 13, 14))
        try add(store, "demain", at: date(2026, 10, 14, 0, 0))
        expectEqual(try store.countToday(now: now, calendar: paris), 2)
        expectEqual(try store.wordsToday(now: now, calendar: paris), 5)
        expectEqual(try store.countToday(now: date(2026, 9, 1), calendar: paris), 0)
        expectEqual(try store.wordsToday(now: date(2026, 9, 1), calendar: paris), 0)
    },
    Test("pruneKeepsNewest") {
        let store = try makeStore()
        for day in 1...5 { try add(store, "jour \(day)", at: date(2026, 10, day)) }
        expectEqual(try store.prune(keepLast: 2), 3)
        expectEqual(try store.recent().map(\.text), ["jour 5", "jour 4"])
        expectEqual(try store.prune(keepLast: 10), 0)
        expectEqual(try store.prune(keepLast: 0), 2)
        expect(try store.recent().isEmpty)
    },
])
