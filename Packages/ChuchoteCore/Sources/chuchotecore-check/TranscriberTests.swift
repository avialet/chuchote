import Foundation
import ChuchoteCore

/// Flux audio deja termine, de `count` blocs de silence.
private func finishedAudio(count: Int = 2) -> AsyncStream<AudioChunk> {
    AsyncStream { continuation in
        for _ in 0..<count {
            continuation.yield(AudioChunk(samples: [Float](repeating: 0, count: 160), sampleRate: 16_000))
        }
        continuation.finish()
    }
}

private func collect(_ stream: AsyncThrowingStream<Transcript, any Error>) async throws -> [Transcript] {
    var all: [Transcript] = []
    for try await transcript in stream { all.append(transcript) }
    return all
}

/// Journal partage entre taches.
private actor Log {
    var items: [Transcript] = []
    var done = false
    /// Nombre d'elements recus quand le flux s'est termine.
    var doneAfter: Int?
    func append(_ t: Transcript) { items.append(t) }
    func finish() { done = true; doneAfter = items.count }
    func isDone(before count: Int) -> Bool { doneAfter.map { $0 <= count } ?? false }
}

/// Attend que le moteur lise l'audio : avec un tampon nul, un bloc n'est accepte
/// (`enqueued`) que par un lecteur en attente. Synchronisation sans delai fixe.
private func waitUntilReadingAudio(_ continuation: AsyncStream<AudioChunk>.Continuation) async {
    let chunk = AudioChunk(samples: [0], sampleRate: 16_000)
    while true {
        if case .enqueued = continuation.yield(chunk) { return }
        await Task.yield()
    }
}

/// Attend que le journal contienne au moins `count` elements et les renvoie.
private func waitForItems(_ log: Log, count: Int) async -> [Transcript] {
    while true {
        let items = await log.items
        if items.count >= count { return items }
        await Task.yield()
    }
}

let transcriberTests: (String, [Test]) = ("Transcriber", [
    Test("audioChunkDuration") {
        let chunk = AudioChunk(samples: [Float](repeating: 0, count: 8_000), sampleRate: 16_000)
        expectEqual(chunk.duration, 0.5)
        expectEqual(AudioChunk(samples: [], sampleRate: 0).duration, 0)
    },
    Test("fakeEmitsScriptInOrder") {
        let script = [
            Transcript(text: "bonjour", isFinal: false),
            Transcript(text: "bonjour tout", isFinal: false),
            Transcript(text: "bonjour tout le monde", isFinal: true),
        ]
        let fake = FakeTranscriber(script: script)
        let got = try blocking { try await collect(fake.transcribe(finishedAudio())) }
        expectEqual(got, script)
    },
    Test("fakeWaitsForEndOfAudioBeforeFinals") {
        let fake = FakeTranscriber(script: [
            Transcript(text: "un", isFinal: false),
            Transcript(text: "un deux", isFinal: true),
        ])
        let log = Log()
        // Tampon nul : un bloc n'est accepte que si le moteur attend l'audio a cet instant.
        let (audio, continuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(0))
        let snapshot: ([Transcript], Bool) = try blocking {
            let consumer = Task {
                for try await t in fake.transcribe(audio) { await log.append(t) }
                await log.finish()
            }
            await waitUntilReadingAudio(continuation)
            // Le moteur attend la fin de l'audio : il a deja emis le partiel et pas le final.
            let early = await waitForItems(log, count: 1)
            continuation.finish()
            try await consumer.value
            return (early, await log.isDone(before: early.count))
        }
        expectEqual(snapshot.0, [Transcript(text: "un", isFinal: false)])
        expect(!snapshot.1, "le flux ne doit pas se terminer avant la fin de l'audio")
        let all = try blocking { await log.items }
        expectEqual(all.map(\.text), ["un", "un deux"])
    },
    Test("cancellingConsumerStopsTheEngine") {
        let fake = FakeTranscriber(script: [
            Transcript(text: "un", isFinal: false),
            Transcript(text: "un deux", isFinal: true),
        ])
        let (audio, continuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(0))
        let (ended, endedContinuation) = AsyncStream<Void>.makeStream()
        // Fin de l'audio vue par le moteur : sa lecture est annulee, l'audio n'est jamais termine ici.
        continuation.onTermination = { _ in endedContinuation.finish() }
        let received: [Transcript] = try blocking {
            let consumer = Task {
                var got: [Transcript] = []
                for try await t in fake.transcribe(audio) { got.append(t) }
                return got
            }
            await waitUntilReadingAudio(continuation)
            consumer.cancel()
            for await _ in ended {}
            return (try? await consumer.value) ?? []
        }
        expect(received.allSatisfy { !$0.isFinal }, "aucun final apres annulation")
    },
    Test("fakeFailureEndsStreamWithError") {
        struct Boom: Error, Equatable {}
        let fake = FakeTranscriber(script: [Transcript(text: "un", isFinal: false)], failure: Boom())
        let outcome: ([Transcript], Bool) = try blocking {
            var got: [Transcript] = []
            do {
                for try await t in fake.transcribe(finishedAudio()) { got.append(t) }
                return (got, false)
            } catch is Boom {
                return (got, true)
            }
        }
        expectEqual(outcome.0, [Transcript(text: "un", isFinal: false)])
        expect(outcome.1, "le flux doit se terminer par l'erreur")
    },
    Test("fakeDelayBetweenTranscripts") {
        let fake = FakeTranscriber(script: [
            Transcript(text: "a", isFinal: false),
            Transcript(text: "a b", isFinal: true),
        ], delay: .milliseconds(60))
        let start = Date()
        _ = try blocking { try await collect(fake.transcribe(finishedAudio())) }
        expect(Date().timeIntervalSince(start) >= 0.12, "deux delais de 60 ms")
    },
    Test("fakeProgressiveBuildsPartialsThenFinal") {
        let fake = FakeTranscriber.progressive("bonjour tout le monde")
        expectEqual(fake.script, [
            Transcript(text: "bonjour", isFinal: false),
            Transcript(text: "bonjour tout", isFinal: false),
            Transcript(text: "bonjour tout le", isFinal: false),
            Transcript(text: "bonjour tout le monde", isFinal: true),
        ])
        expectEqual(FakeTranscriber.progressive("   ").script, [Transcript(text: "", isFinal: true)])
    },
    Test("fakeEmptyScriptFinishesWithAudio") {
        let fake = FakeTranscriber(script: [])
        let got = try blocking { try await collect(fake.transcribe(finishedAudio())) }
        expect(got.isEmpty)
    },
])
