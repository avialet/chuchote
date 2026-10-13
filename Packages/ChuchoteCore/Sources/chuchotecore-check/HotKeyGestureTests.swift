import Foundation
import ChuchoteCore

let hotKeyGestureTests: (String, [Test]) = ("HotKeyGesture", [
    Test("thresholdIs300ms") {
        expectEqual(HotKeyGesture.holdThreshold, 0.3)
    },
    Test("pressStartsListening") {
        var g = HotKeyGesture()
        expectEqual(g.state, .idle)
        expectEqual(g.press(at: 10), .startListening)
        expectEqual(g.state, .holding(since: 10))
    },
    Test("longHoldReleaseFinishes") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        expectEqual(g.release(at: 11.2), .finish)
        expectEqual(g.state, .transcribing)
    },
    Test("releaseExactlyAtThresholdFinishes") {
        var g = HotKeyGesture()
        _ = g.press(at: 0)
        expectEqual(g.release(at: HotKeyGesture.holdThreshold), .finish)
    },
    Test("shortTapLocksListening") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        expectEqual(g.release(at: 10.1), .none)
        expectEqual(g.state, .locked)
    },
    Test("lockedPressFinishesAndItsReleaseIsIgnored") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        _ = g.release(at: 10.1)
        expectEqual(g.press(at: 14), .finish)
        expectEqual(g.state, .transcribing)
        expectEqual(g.release(at: 14.5), .none)
        expectEqual(g.state, .transcribing)
    },
    Test("autoRepeatWhileHoldingIsIgnored") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        expectEqual(g.press(at: 10.05), .none)
        expectEqual(g.press(at: 10.5), .none)
        // Le maintien se mesure depuis le premier appui.
        expectEqual(g.state, .holding(since: 10))
        expectEqual(g.release(at: 11), .finish)
    },
    Test("pressesDuringTranscriptionAreIgnored") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        _ = g.release(at: 11)
        expectEqual(g.press(at: 11.2), .none)
        expectEqual(g.release(at: 11.3), .none)
        expectEqual(g.state, .transcribing)
    },
    Test("finishedReturnsToIdle") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        _ = g.release(at: 11)
        g.finished()
        expectEqual(g.state, .idle)
        expectEqual(g.press(at: 12), .startListening)
    },
    Test("strayReleaseWhenIdleIsIgnored") {
        var g = HotKeyGesture()
        expectEqual(g.release(at: 1), .none)
        expectEqual(g.state, .idle)
    },
    Test("cancelWhileHolding") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        expectEqual(g.cancel(), .cancel)
        expectEqual(g.state, .idle)
        // Le relachement de la touche apres l'annulation ne relance rien.
        expectEqual(g.release(at: 11), .none)
        expectEqual(g.state, .idle)
    },
    Test("cancelWhileLocked") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        _ = g.release(at: 10.1)
        expectEqual(g.cancel(), .cancel)
        expectEqual(g.state, .idle)
    },
    Test("cancelOutsideListeningDoesNothing") {
        var g = HotKeyGesture()
        expectEqual(g.cancel(), .none)
        _ = g.press(at: 10)
        _ = g.release(at: 11)
        expectEqual(g.cancel(), .none)
        expectEqual(g.state, .transcribing)
    },
    Test("autoRepeatAfterCancelWhileKeyHeldIsIgnored") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        _ = g.cancel()
        expectEqual(g.press(at: 10.5), .none)
        expectEqual(g.state, .idle)
        _ = g.release(at: 11)
        expectEqual(g.press(at: 12), .startListening)
    },
    Test("autoRepeatAfterFastFinishWhileKeyHeldIsIgnored") {
        var g = HotKeyGesture()
        _ = g.press(at: 10)
        _ = g.release(at: 10.1)
        _ = g.press(at: 13)
        g.finished()
        expectEqual(g.press(at: 13.5), .none)
        _ = g.release(at: 13.6)
        expectEqual(g.press(at: 15), .startListening)
    },
    Test("isListening") {
        var g = HotKeyGesture()
        expect(!g.isListening)
        _ = g.press(at: 0)
        expect(g.isListening)
        _ = g.release(at: 0.1)
        expect(g.isListening)
        _ = g.press(at: 2)
        expect(!g.isListening)
    },
])
