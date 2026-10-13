import ChuchoteCore
import Foundation

let liveTextTests: (String, [Test]) = ("LiveText", [
    Test("previewNeverEntersPastedText") {
        var buffer = TranscriptBuffer()
        buffer.add(Transcript(text: "bonjour tout", isFinal: false, isPreview: true))
        buffer.add(Transcript(text: "Bonjour tout le monde", isFinal: true, isPreview: true))
        expectEqual(buffer.text, "")
        buffer.add(Transcript(text: "Bonjour tout le monde.", isFinal: true))
        expectEqual(buffer.text, "Bonjour tout le monde.")
    },
    Test("previewJoinsFinalsAndLastVolatile") {
        var buffer = TranscriptBuffer()
        buffer.add(Transcript(text: "pense", isFinal: false, isPreview: true))
        buffer.add(Transcript(text: "pense a rappeler", isFinal: false, isPreview: true))
        expectEqual(buffer.preview, "pense a rappeler")
        buffer.add(Transcript(text: "Pense a rappeler le garage,", isFinal: true, isPreview: true))
        buffer.add(Transcript(text: "avant", isFinal: false, isPreview: true))
        expectEqual(buffer.preview, "Pense a rappeler le garage, avant")
    },
    Test("liveShowsPreviewThenPastedText") {
        var buffer = TranscriptBuffer()
        expectEqual(buffer.live, "")
        buffer.add(Transcript(text: "bonjour", isFinal: false, isPreview: true))
        expectEqual(buffer.live, "bonjour")
        // Sans apercu (texte en direct coupe), le texte du moteur principal s'affiche.
        var plain = TranscriptBuffer()
        plain.add(Transcript(text: "Bonjour.", isFinal: true))
        expectEqual(plain.live, "Bonjour.")
    },
    Test("tailKeepsShortTextAndNormalizesSpaces") {
        expectEqual(LiveText.tail("  bonjour \n tout   le monde ", maxCharacters: 40), "bonjour tout le monde")
        expectEqual(LiveText.tail("", maxCharacters: 10), "")
    },
    Test("tailCutsTheBeginningOnAWordBoundary") {
        let text = "un deux trois quatre cinq six sept"
        let tail = LiveText.tail(text, maxCharacters: 16)
        expectEqual(tail, "\u{2026}cinq six sept")
        expect(tail.count <= 16, "longueur \(tail.count)")
        expect(text.hasSuffix(String(tail.dropFirst())))
    },
    Test("tailCutsAWordTooLongToFit") {
        let tail = LiveText.tail("anticonstitutionnellement", maxCharacters: 10)
        expectEqual(tail, "\u{2026}nellement")
        expectEqual(tail.count, 10)
    },
    Test("listeningStyleDefaultsToDrop") {
        expectEqual(ListeningStyle(stored: nil), .drop)
        expectEqual(ListeningStyle(stored: "inconnu"), .drop)
        expectEqual(ListeningStyle(stored: "pill"), .pill)
        expectEqual(ListeningStyle(stored: ListeningStyle.drop.rawValue), .drop)
    },
    Test("notchGeometryFollowsTheNotch") {
        // Ecran 1512 x 982 a encoche : zones auxiliaires de part et d'autre (0-654 et 857-1512), 32 pt de haut.
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(screenFrame: frame, safeAreaTop: 32,
                                     auxiliaryLeft: CGRect(x: 0, y: 950, width: 654, height: 32),
                                     auxiliaryRight: CGRect(x: 857, y: 950, width: 655, height: 32),
                                     menuBarHeight: 32)
        expect(geometry.hasNotch)
        expectEqual(geometry.notchWidth, 203)
        expectEqual(geometry.bandHeight, 32)
        expectEqual(geometry.centerX, 755.5)
        let window = geometry.windowFrame(size: CGSize(width: 500, height: 200))
        expectEqual(window, CGRect(x: 505.5, y: 782, width: 500, height: 200))
    },
    Test("notchGeometryWithoutNotchSticksToTheTopCenter") {
        // Ecran externe a droite, sans encoche : bande de la hauteur de la barre des menus, au centre.
        let frame = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        let geometry = NotchGeometry(screenFrame: frame, safeAreaTop: 0, auxiliaryLeft: nil, auxiliaryRight: nil,
                                     menuBarHeight: 25)
        expect(!geometry.hasNotch)
        expectEqual(geometry.notchWidth, 0)
        expectEqual(geometry.bandHeight, 28)
        expectEqual(geometry.centerX, 2792)
        expectEqual(geometry.windowFrame(size: CGSize(width: 400, height: 100)).maxY, 1240)
    },
    Test("hitRectIsTheVisibleDropOnly") {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(screenFrame: frame, safeAreaTop: 32,
                                     auxiliaryLeft: CGRect(x: 0, y: 950, width: 654, height: 32),
                                     auxiliaryRight: CGRect(x: 857, y: 950, width: 655, height: 32),
                                     menuBarHeight: 32)
        let hit = geometry.hitRect(expanded: true, dropHeight: 120)
        expectEqual(hit, CGRect(x: 545.5, y: 862, width: 420, height: 120))
        // La fenetre (marges comprises) deborde de la goutte : ses marges ne prennent aucun clic.
        let window = geometry.windowFrame(size: CGSize(width: 476, height: 165))
        expect(window.contains(CGPoint(x: window.minX + 8, y: window.maxY - 70)))
        expect(!hit.contains(CGPoint(x: window.minX + 8, y: window.maxY - 70)))
        expect(!hit.contains(CGPoint(x: window.midX, y: window.minY + 6)))
        expect(hit.contains(CGPoint(x: hit.midX, y: hit.minY + 20)))
    },
    Test("hitRectIsEmptyWhileClosed") {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0,
                                     auxiliaryLeft: nil, auxiliaryRight: nil, menuBarHeight: 24)
        expect(geometry.hitRect(expanded: false, dropHeight: 120).isEmpty)
        expect(geometry.hitRect(expanded: true, dropHeight: 0).isEmpty)
        expectEqual(geometry.hitRect(expanded: true, dropHeight: 28).maxY, 900)
    },
    Test("dropWidthLeavesRoomForBothWings") {
        expectEqual(NotchGeometry.dropWidth(notchWidth: 0), 420)
        expectEqual(NotchGeometry.dropWidth(notchWidth: 203), 420)
        expectEqual(NotchGeometry.dropWidth(notchWidth: 260), 460)
    },
])
