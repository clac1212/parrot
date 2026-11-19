import XCTest
@testable import ParrotCore

/// fork-021: the recording goes on past the release while the voice is on.
@MainActor
final class SpeechTailTests: XCTestCase {
    private var clock: TimeInterval = 1000

    /// `seconds` of chunks every 10 ms: voice (0.1) or room (0.003).
    private func feed(_ tail: SpeechTail, voice: Bool, seconds: Double) {
        for _ in 0..<Int(seconds * 100) {
            tail.push(voice ? 0.1 : 0.003)
            clock += 0.01
        }
    }

    private func make() -> SpeechTail { SpeechTail(now: { [unowned self] in clock }) }

    func testReleasedInSilenceEndsAtOnce() {
        let tail = make()
        feed(tail, voice: false, seconds: 0.5)
        feed(tail, voice: true, seconds: 2)
        feed(tail, voice: false, seconds: 0.3)
        var ended = false
        tail.release { ended = true }
        XCTAssertTrue(ended)
        XCTAssertFalse(tail.isWaiting)
    }

    func testReleasedMidWordWaitsUntilFlushed() {
        let tail = make()
        feed(tail, voice: false, seconds: 0.5)
        feed(tail, voice: true, seconds: 2)
        var ended = 0
        tail.release { ended += 1 }
        XCTAssertEqual(ended, 0)
        XCTAssertTrue(tail.isWaiting)
        tail.flush()
        XCTAssertEqual(ended, 1)
        tail.flush()
        XCTAssertEqual(ended, 1, "once")
    }

    func testTooShortOrTooFlatNeverWaits() {
        let short = make()
        feed(short, voice: false, seconds: 0.2)
        feed(short, voice: true, seconds: 0.5)
        var ended = false
        short.release { ended = true }
        XCTAssertTrue(ended, "under a second")
        XCTAssertNil(SpeechTail.threshold([Float](repeating: -40, count: 50) + [Float](repeating: -35, count: 50)), "5 dB apart")
        XCTAssertEqual(SpeechTail.threshold([Float](repeating: -50, count: 50) + [Float](repeating: -20, count: 50)) ?? 0, -35, accuracy: 0.1)
    }

    func testTheWaitEndsOnSilence() {
        let tail = make()
        feed(tail, voice: false, seconds: 0.5)
        feed(tail, voice: true, seconds: 2)
        let done = expectation(description: "ended")
        tail.release { done.fulfill() }
        // The room comes back after the word; the clock moves with it.
        feed(tail, voice: false, seconds: 0.2)
        wait(for: [done], timeout: 1)
    }
}
