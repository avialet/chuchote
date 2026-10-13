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
    func append(_ t: Transcript) { items.append(t) }
    func finish() { done = true }
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
        let (audio, continuation) = AsyncStream<AudioChunk>.makeStream()
        let snapshot: ([Transcript], Bool) = try blocking {
            let consumer = Task {
                for try await t in fake.transcribe(audio) { await log.append(t) }
                await log.finish()
            }
            try await Task.sleep(for: .milliseconds(150))
            let early = (await log.items, await log.done)
            continuation.finish()
            try await consumer.value
            return early
        }
        // Audio encore ouvert : seuls les partiels sont sortis.
        expectEqual(snapshot.0, [Transcript(text: "un", isFinal: false)])
        expect(!snapshot.1, "le flux ne doit pas se terminer avant la fin de l'audio")
        let all = try blocking { await log.items }
        expectEqual(all.map(\.text), ["un", "un deux"])
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
