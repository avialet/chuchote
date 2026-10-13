import Foundation

/// Mini-harnais de tests, API volontairement proche de Swift Testing
/// (`expect` -> `#expect`, `Test` -> `@Test`) pour une migration par sed.
struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

struct Test: Sendable {
    let name: String
    let body: @Sendable () throws -> Void
    init(_ name: String, _ body: @escaping @Sendable () throws -> Void) {
        self.name = name
        self.body = body
    }
}

nonisolated(unsafe) var currentFailures: [String] = []

func expect(_ condition: Bool, _ message: @autoclosure () -> String = "",
            file: StaticString = #filePath, line: UInt = #line) {
    if !condition {
        currentFailures.append("\(file):\(line) \(message())")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
    if a != b {
        currentFailures.append("\(file):\(line) \(message()) got \(a) expected \(b)")
    }
}

func expectThrows(_ body: () throws -> Void, _ message: @autoclosure () -> String = "",
                  file: StaticString = #filePath, line: UInt = #line) {
    do {
        try body()
        currentFailures.append("\(file):\(line) expected error \(message())")
    } catch {}
}

func run(_ suites: [(String, [Test])]) -> Never {
    var passed = 0
    var failed = 0
    let filter = CommandLine.arguments.dropFirst().first
    for (suite, tests) in suites {
        for test in tests {
            let fullName = "\(suite).\(test.name)"
            if let filter, !fullName.contains(filter) { continue }
            currentFailures = []
            do {
                try test.body()
            } catch {
                currentFailures.append("threw \(error)")
            }
            if currentFailures.isEmpty {
                passed += 1
            } else {
                failed += 1
                print("FAIL \(fullName)")
                for failure in currentFailures { print("     \(failure)") }
            }
        }
    }
    print("\(passed) passed, \(failed) failed")
    exit(failed == 0 ? 0 : 1)
}
