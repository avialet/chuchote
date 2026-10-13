import Foundation
import ChuchoteCore

let setupTests: (String, [Test]) = ("Setup", [
    Test("tout est en ordre : aucune etape") {
        expectEqual(SetupChecklist.steps(microphone: .authorized, accessibilityTrusted: true, directPaste: true,
                                         language: .ready), [])
        // Moteur en preparation : pas d'alerte (etat transitoire du lancement).
        expectEqual(SetupChecklist.steps(microphone: .authorized, accessibilityTrusted: true, directPaste: true,
                                         language: .preparing), [])
    },

    Test("micro : a demander ou refuse") {
        expectEqual(SetupChecklist.steps(microphone: .notDetermined, accessibilityTrusted: true, directPaste: true,
                                         language: .ready), [.microphone(denied: false)])
        expectEqual(SetupChecklist.steps(microphone: .denied, accessibilityTrusted: true, directPaste: true,
                                         language: .ready), [.microphone(denied: true)])
    },

    Test("accessibilite : seulement si le collage direct est voulu") {
        expectEqual(SetupChecklist.steps(microphone: .authorized, accessibilityTrusted: false, directPaste: true,
                                         language: .ready), [.accessibility])
        expectEqual(SetupChecklist.steps(microphone: .authorized, accessibilityTrusted: false, directPaste: false,
                                         language: .ready), [])
    },

    Test("langue : a installer, en cours, non prise en charge, echec") {
        for state in [LanguageReadiness.needsInstall, .installing(0.4), .unsupported, .failed("x")] {
            expectEqual(SetupChecklist.steps(microphone: .authorized, accessibilityTrusted: true, directPaste: true,
                                             language: state), [.language(state)])
        }
    },

    Test("ordre : micro, accessibilite, langue") {
        expectEqual(SetupChecklist.steps(microphone: .notDetermined, accessibilityTrusted: false, directPaste: true,
                                         language: .needsInstall),
                    [.microphone(denied: false), .accessibility, .language(.needsInstall)])
    },

    Test("progression bornee") {
        expectEqual(LanguageReadiness.installing(1.7).progress, 1)
        expectEqual(LanguageReadiness.installing(-1).progress, 0)
        expectEqual(LanguageReadiness.installing(0.25).progress, 0.25)
        expectEqual(LanguageReadiness.ready.progress, nil)
    },

    Test("langues : identifiant canonique") {
        expectEqual(LanguageChoices.canonical("fr-FR"), "fr_FR")
        expectEqual(LanguageChoices.canonical("en_US"), "en_US")
    },

    Test("langues : noms en francais, majuscule initiale") {
        expectEqual(LanguageChoices.displayName("fr_FR"), "Fran\u{00E7}ais (France)")
        expectEqual(LanguageChoices.displayName("en-US"), "Anglais (\u{00C9}tats-Unis)")
    },

    Test("langues : liste courte du menu") {
        let supported = ["de-DE", "en-GB", "en-US", "fr-CA", "fr-FR", "ja-JP", "pt-BR"]
        expectEqual(LanguageChoices.short(supported: supported, current: "fr_FR"),
                    ["fr_FR", "en_US", "en_GB", "de_DE"])
        // Langue courante hors des preferees : ajoutee en tete.
        expectEqual(LanguageChoices.short(supported: supported, current: "ja-JP"),
                    ["ja_JP", "fr_FR", "en_US", "en_GB", "de_DE"])
        // Liste encore inconnue : au moins la langue courante.
        expectEqual(LanguageChoices.short(supported: [], current: "fr_FR"), ["fr_FR"])
    },

    Test("langues : liste complete triee par nom, sans doublon") {
        let all = LanguageChoices.all(supported: ["fr-FR", "en-US", "de-DE", "fr_FR", "es-ES"], current: "fr_FR")
        expectEqual(all, ["de_DE", "en_US", "es_ES", "fr_FR"])
        expectEqual(LanguageChoices.all(supported: [], current: "it_IT"), ["it_IT"])
    },
])
