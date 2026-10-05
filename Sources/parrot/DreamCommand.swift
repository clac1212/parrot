import ArgumentParser
import Foundation
import ParrotCore

/// `parrot dream prepare|apply`: the two local steps of the nightly review
/// (fork-009), run by the scheduled job around the judge.
struct Dream: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Nightly review of the dictation corpus (fork-009).",
        subcommands: [Prepare.self, Apply.self]
    )

    struct Prepare: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Re-transcribe the corpus with a heavy model and list recurring substitutions."
        )

        func run() throws {
            try runAsync { try await NightlyReview.prepare() }
        }
    }

    struct Apply: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remember the judge's verdicts, add and remove learned dictionary entries, write the report."
        )

        @Option(name: .long, help: "The judge's decisions (JSON).") var judge: String?
        @Option(name: .long, help: "A trial judge's decisions, compared in the report, never applied.") var shadow: String?

        func run() throws {
            let existing = { (path: String?) in
                path.map { URL(fileURLWithPath: $0) }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            }
            try NightlyReview.apply(judge: existing(judge), shadow: existing(shadow))
        }
    }
}

/// Runs `work` while the main run loop keeps turning, so main-actor calls
/// inside it (the spell checker) don't deadlock as they would on a semaphore.
private func runAsync(_ work: @escaping @Sendable () async throws -> Void) throws {
    final class Outcome: @unchecked Sendable { var done = false; var error: Error? }
    let outcome = Outcome()
    Task {
        do { try await work() } catch { outcome.error = error }
        outcome.done = true
    }
    while !outcome.done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    if let error = outcome.error { throw error }
}
