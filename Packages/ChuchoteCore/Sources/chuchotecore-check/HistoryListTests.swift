import Foundation
import ChuchoteCore

private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

private func at(_ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: mi))!
}

private func dictation(_ id: Int64, _ date: Date, _ text: String = "Bonjour.", duration: TimeInterval = 4,
                       app: String? = nil) -> Dictation {
    Dictation(id: id, text: text, createdAt: date, duration: duration, locale: "fr_FR", targetApp: app)
}

let historyListTests: (String, [Test]) = ("HistoryList", [
    Test("sections par anciennete, dans l'ordre de la liste") {
        let now = at(13, 15)
        let list = [
            dictation(8, at(13, 14, 59)),
            dictation(7, at(13, 14, 30)),
            dictation(6, at(13, 9)),
            dictation(5, at(12, 18)),
            dictation(4, at(10, 11)),
            dictation(3, at(9, 8)),
            dictation(2, at(1, 8)),
        ]
        let sections = DictationSection.group(list, now: now, calendar: paris)
        expectEqual(sections.map(\.title),
                    ["\u{00C0} l'instant", "Aujourd'hui", "Hier", "Cette semaine", "Plus ancien"])
        expectEqual(sections.map { $0.items.compactMap(\.id) }, [[8, 7], [6], [5], [4, 3], [2]])
        expectEqual(sections.map(\.id), sections.map(\.title))
    },

    Test("sections : liste vide") {
        expect(DictationSection.group([], now: at(13, 15), calendar: paris).isEmpty)
    },

    Test("duree : secondes, puis minutes") {
        expectEqual(DictationFormat.duration(0), "0\u{00A0}s")
        expectEqual(DictationFormat.duration(0.4), "0\u{00A0}s")
        expectEqual(DictationFormat.duration(4.6), "5\u{00A0}s")
        expectEqual(DictationFormat.duration(59.4), "59\u{00A0}s")
        expectEqual(DictationFormat.duration(60), "1\u{00A0}min")
        expectEqual(DictationFormat.duration(65), "1\u{00A0}min\u{00A0}05")
        expectEqual(DictationFormat.duration(754), "12\u{00A0}min\u{00A0}34")
        expectEqual(DictationFormat.duration(-3), "0\u{00A0}s")
    },

    Test("mots : singulier et pluriel") {
        expectEqual(DictationFormat.words(0), "0\u{00A0}mot")
        expectEqual(DictationFormat.words(1), "1\u{00A0}mot")
        expectEqual(DictationFormat.words(2), "2\u{00A0}mots")
        expectEqual(DictationFormat.words(1250), "1\u{202F}250\u{00A0}mots")
    },

    Test("meta : app cible, duree, mots") {
        let d = dictation(1, at(13, 9), "Un deux trois quatre.", duration: 12, app: "Mail")
        expectEqual(DictationFormat.meta(d), "Mail \u{00B7} 12\u{00A0}s \u{00B7} 4\u{00A0}mots")
        let noApp = dictation(2, at(13, 9), "Un.", duration: 3)
        expectEqual(DictationFormat.meta(noApp), "3\u{00A0}s \u{00B7} 1\u{00A0}mot")
        let blankApp = dictation(3, at(13, 9), "Un.", duration: 3, app: "  ")
        expectEqual(DictationFormat.meta(blankApp), "3\u{00A0}s \u{00B7} 1\u{00A0}mot")
    },

    Test("selection : fleches bornees") {
        let ids: [Int64] = [5, 4, 3]
        expectEqual(ListSelection.move(in: ids, from: nil, by: 1), 5)
        expectEqual(ListSelection.move(in: ids, from: nil, by: -1), 5)
        expectEqual(ListSelection.move(in: ids, from: 5, by: 1), 4)
        expectEqual(ListSelection.move(in: ids, from: 3, by: 1), 3)
        expectEqual(ListSelection.move(in: ids, from: 5, by: -1), 5)
        expectEqual(ListSelection.move(in: ids, from: 99, by: 1), 5)
        expectEqual(ListSelection.move(in: [], from: 5, by: 1), nil)
    },

    Test("selection : apres suppression ou filtre") {
        let ids: [Int64] = [5, 4, 3]
        expectEqual(ListSelection.keep(4, in: ids, previous: [5, 4, 3]), 4)
        // La ligne choisie a disparu : la suivante, sinon la precedente.
        expectEqual(ListSelection.keep(4, in: [5, 3], previous: [5, 4, 3]), 3)
        expectEqual(ListSelection.keep(3, in: [5, 4], previous: [5, 4, 3]), 4)
        expectEqual(ListSelection.keep(nil, in: ids, previous: []), 5)
        expectEqual(ListSelection.keep(9, in: ids, previous: []), 5)
        expectEqual(ListSelection.keep(4, in: [], previous: [5, 4, 3]), nil)
    },

    Test("historique : 100, 500 ou tout") {
        expectEqual(HistoryLimit.allCases, [.hundred, .fiveHundred, .all])
        expectEqual(HistoryLimit.hundred.keepLast, 100)
        expectEqual(HistoryLimit.fiveHundred.keepLast, 500)
        expectEqual(HistoryLimit.all.keepLast, nil)
        expectEqual(HistoryLimit(stored: 100), .hundred)
        expectEqual(HistoryLimit(stored: 0), .all)
        expectEqual(HistoryLimit(stored: 42), .fiveHundred)
        expectEqual(HistoryLimit.defaultValue, .fiveHundred)
        expectEqual(HistoryLimit.all.rawValue, 0)
    },
])
