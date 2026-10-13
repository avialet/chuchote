#if DEBUG
import AppKit
import ChuchoteCore

/// Essai du deroule de la dictee sans micro ni collage (DEBUG) : `Chuchote -ChuchoteFlowCheck`.
/// Joue le controleur avec une source figee et FakeTranscriber : maintien, verrouillage, action rapide, annulation
/// pendant l'ecriture, dictee vide, delai maximal. Imprime chaque verification, puis quitte (1 si echec).
@MainActor
enum FlowCheck {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("-\(Brand.name)FlowCheck") else { return false }
        Task {
            let failures = await run()
            print(failures == 0 ? "deroule : tout est bon" : "deroule : \(failures) echec(s)")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }

    private static var failures = 0

    private static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "ok  " : "ECHEC") \(label)")
        if !condition { failures += 1 }
    }

    private static func controller(_ fake: FakeTranscriber) -> DictationController {
        DictationController(audio: FrozenAudio(level: 0.5), makeTranscriber: { _, _ in fake },
                            store: nil, deliversText: false)
    }

    private static func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    static func run() async -> Int {
        // Maintien : appui, 0,4 s, relachement -> texte poli, << Copie >>, puis repos.
        var c = controller(.progressive("bonjour tout le monde"))
        c.keyPressed()
        await wait(100)
        check(c.phase != .idle && !c.isLocked, "maintien : ecoute en cours")
        await wait(300)
        c.keyReleased()
        await wait(200)
        check(c.phase == .done(pasted: false), "maintien : termine sans collage (\(c.phase))")
        check(c.lastText == "Bonjour tout le monde.", "maintien : texte poli (\(c.lastText ?? "nil"))")
        await wait(2_000)
        check(c.phase == .idle, "maintien : panneau ferme")

        // Verrouillage : appui bref, puis << Dicter >> pour finir.
        c = controller(.progressive("note pour demain"))
        c.keyPressed()
        await wait(50)
        c.keyReleased()
        await wait(100)
        check(c.isLocked, "appui bref : ecoute verrouillee")
        c.toggleLockedDictation()
        await wait(200)
        check(c.lastText == "Note pour demain.", "verrouillage : texte (\(c.lastText ?? "nil"))")

        // Action rapide de Vialet (`chuchote://dicter`) : ecoute verrouillee, un second appel la finit.
        c = controller(.progressive("action rapide"))
        await QuickDictation.toggle(c)
        await wait(100)
        check(c.isLocked && c.phase != .idle, "action rapide : ecoute verrouillee (\(c.phase))")
        await QuickDictation.toggle(c)
        await wait(200)
        check(c.lastText == "Action rapide.", "action rapide : texte (\(c.lastText ?? "nil"))")
        await wait(2_000)

        // Annulation pendant l'ecriture : rien n'est ecrit, meme quand le moteur finit plus tard.
        c = controller(.progressive("ne pas ecrire", delay: .milliseconds(400)))
        c.keyPressed()
        await wait(400)
        c.keyReleased()
        await wait(50)
        check(c.phase == .writing, "annulation : en ecriture (\(c.phase))")
        c.cancel()
        await wait(1_500)
        check(c.phase == .idle && c.lastText == nil, "annulation : rien d'ecrit (\(c.phase))")
        c.keyPressed()
        await wait(100)
        check(c.phase != .idle, "annulation : nouvelle dictee possible")
        c.cancel()

        // Dictee vide : panneau ferme, rien d'ecrit.
        c = controller(FakeTranscriber(script: [Transcript(text: "  ", isFinal: true)]))
        c.keyPressed()
        await wait(400)
        c.keyReleased()
        await wait(400)
        check(c.phase == .idle && c.lastText == nil, "dictee vide : rien d'ecrit (\(c.phase))")

        // Delai maximal : moteur trop lent -> echec lisible, puis repos.
        c = controller(.progressive("trop lent", delay: .seconds(30)))
        c.transcriptionTimeout = .milliseconds(500)
        c.keyPressed()
        await wait(400)
        c.keyReleased()
        await wait(800)
        if case .failed = c.phase { check(true, "delai maximal : echec affiche") } else {
            check(false, "delai maximal : echec affiche (\(c.phase))")
        }
        await wait(3_000)
        check(c.phase == .idle && c.lastText == nil, "delai maximal : repos, rien d'ecrit")
        c.keyPressed()
        await wait(100)
        check(c.phase != .idle, "delai maximal : nouvelle dictee possible")
        c.cancel()
        await wait(300)
        return failures
    }
}
#endif
