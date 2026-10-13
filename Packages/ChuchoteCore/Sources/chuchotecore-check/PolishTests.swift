import Foundation
import ChuchoteCore

private let nnbsp = "\u{202F}"   // espace insecable fine
private let nbsp = "\u{00A0}"    // espace insecable
private let apos = "\u{2019}"    // apostrophe typographique

private func fr(_ text: String, typography: Bool = true) -> String {
    Polish.apply(text, locale: "fr-FR", frenchTypography: typography)
}

private func en(_ text: String) -> String {
    Polish.apply(text, locale: "en-US", frenchTypography: true)
}

let polishTests: (String, [Test]) = ("Polish", [
    Test("emptyAndBlank") {
        expectEqual(fr(""), "")
        expectEqual(fr("   \t  \n "), "")
        expectEqual(en("  "), "")
    },
    Test("collapsesSpacesAndTrims") {
        expectEqual(en("  hello    world \t again  "), "Hello world again.")
        expectEqual(fr("un  \n   deux"), "Un\ndeux.")
    },
    Test("capitalizesFirstLetter") {
        expectEqual(fr("bonjour"), "Bonjour.")
        expectEqual(fr("\u{E9}t\u{E9} chaud"), "\u{C9}t\u{E9} chaud.")
        expectEqual(fr("10 pommes"), "10 pommes.")
        expectEqual(en("iPhone is new"), "iPhone is new.")
    },
    Test("finalPeriodOnlyAfterLetterOrDigit") {
        expectEqual(fr("Bonjour."), "Bonjour.")
        expectEqual(fr("il en reste 3"), "Il en reste 3.")
        expectEqual(en("Really?"), "Really?")
        expectEqual(en("Stop!"), "Stop!")
        expectEqual(en("well..."), "Well...")
        expectEqual(en("(aside)"), "(Aside)")
    },
    Test("frenchSpacesBeforeHighPunctuation") {
        expectEqual(fr("\u{E7}a va?"), "\u{C7}a va\(nnbsp)?")
        expectEqual(fr("\u{E7}a va ?"), "\u{C7}a va\(nnbsp)?")
        expectEqual(fr("attention!"), "Attention\(nnbsp)!")
        expectEqual(fr("un; deux"), "Un\(nnbsp); deux.")
        expectEqual(fr("note: voici"), "Note\(nbsp): voici.")
        expectEqual(fr("note : voici"), "Note\(nbsp): voici.")
        expectEqual(fr("quoi?!"), "Quoi\(nnbsp)?!")
    },
    Test("frenchApostrophe") {
        expectEqual(fr("l'eau d'ici"), "L\(apos)eau d\(apos)ici.")
        expectEqual(fr("aujourd'hui"), "Aujourd\(apos)hui.")
    },
    Test("frenchQuotes") {
        expectEqual(fr("il a dit \"bonjour\" hier"), "Il a dit \u{AB}\(nbsp)bonjour\(nbsp)\u{BB} hier.")
        expectEqual(fr("\" oui \""), "\u{AB}\(nbsp)Oui\(nbsp)\u{BB}")
        expectEqual(fr("\u{AB} oui \u{BB}"), "\u{AB}\(nbsp)Oui\(nbsp)\u{BB}")
        expectEqual(fr("il dit \"quoi?\" ici"), "Il dit \u{AB}\(nbsp)quoi\(nnbsp)?\(nbsp)\u{BB} ici.")
    },
    Test("frenchTypographyCanBeTurnedOff") {
        expectEqual(fr("\u{E7}a va? l'eau", typography: false), "\u{C7}a va? l'eau.")
    },
    Test("englishGetsNoFrenchTypography") {
        expectEqual(en("he said \"hi\" ok?"), "He said \"hi\" ok?")
        expectEqual(en("it's: fine; ok!"), "It's: fine; ok!")
    },
    Test("frenchLocaleVariants") {
        expectEqual(Polish.apply("oui?", locale: "fr", frenchTypography: true), "Oui\(nnbsp)?")
        expectEqual(Polish.apply("oui?", locale: "fr_CA", frenchTypography: true), "Oui\(nnbsp)?")
        expectEqual(Polish.apply("oui?", locale: "fy", frenchTypography: true), "Oui?")
        expect(Polish.isFrench("FR-fr"))
        expect(!Polish.isFrench("fry"))
    },
    Test("timesAreUntouched") {
        expectEqual(fr("rendez-vous \u{E0} 10:30"), "Rendez-vous \u{E0} 10:30.")
        expectEqual(fr("de 9:00 \u{E0} 18:45 ok"), "De 9:00 \u{E0} 18:45 ok.")
    },
    Test("urlsAndEmailsAreUntouched") {
        expectEqual(fr("va sur https://exemple.fr/page?x=1&y=2 maintenant"),
                    "Va sur https://exemple.fr/page?x=1&y=2 maintenant.")
        expectEqual(fr("\u{E9}cris \u{E0} jean.dupont@exemple.fr"), "\u{C9}cris \u{E0} jean.dupont@exemple.fr")
        expectEqual(fr("https://exemple.fr est en ligne"), "https://exemple.fr est en ligne.")
        expectEqual(fr("www.exemple.fr est en ligne"), "www.exemple.fr est en ligne.")
        expectEqual(fr("jean@exemple.fr r\u{E9}pond"), "jean@exemple.fr r\u{E9}pond.")
        expectEqual(fr("lien: https://exemple.fr"), "Lien\(nbsp): https://exemple.fr")
    },
    Test("idempotent") {
        let samples = [
            "", "  ", "bonjour", "\u{E7}a va ?", "quoi?! non", "note: voici; la suite!",
            "il a dit \"bonjour\" hier", "\u{AB} oui \u{BB}", "l'eau d'ici", "\u{E0} 10:30",
            "va sur https://exemple.fr/page?x=1 maintenant", "jean@exemple.fr", "un  \n  deux",
            "iPhone", "10 pommes", "well...",
        ]
        for sample in samples {
            for locale in ["fr-FR", "en-US"] {
                for typography in [true, false] {
                    let once = Polish.apply(sample, locale: locale, frenchTypography: typography)
                    let twice = Polish.apply(once, locale: locale, frenchTypography: typography)
                    expectEqual(twice, once, "\(sample) [\(locale) \(typography)]")
                }
            }
        }
    },
])
