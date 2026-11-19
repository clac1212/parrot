import Foundation

/// The last word after the key (fork-021). Released while the user is still
/// speaking, the recording goes on until the voice stops — `quiet` without
/// it, `cap` at most — instead of cutting the word. Released in silence, it
/// stops at once, as before: the wait costs only the dictations that need it.
///
/// It hears the level of each chunk the capture delivers (`push`, on the
/// input's realtime thread) and tells voice from the room by the recording's
/// own levels: halfway between its quiet (10th percentile) and its loud
/// (90th) chunks.
final class SpeechTail: @unchecked Sendable {
    /// The voice is on at release when the last `recent` seconds are loud.
    static let recent: TimeInterval = 0.1
    /// Silence that ends the wait.
    static let quiet: TimeInterval = 0.15
    /// The longest wait.
    static let cap: TimeInterval = 0.4
    /// Below this, voice and room are too close to tell apart: no wait.
    static let minimumSpread: Float = 10
    /// Shorter recordings have too little to set the levels from.
    static let minimumDuration: TimeInterval = 1
    private static let tick: TimeInterval = 0.025

    private let lock = NSLock()
    /// dB of each chunk since the press, and when it arrived.
    private var levels: [(at: TimeInterval, db: Float)] = []
    private var pending: (@MainActor () -> Void)?
    private var timer: Timer?
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = CFAbsoluteTimeGetCurrent) {
        self.now = now
    }

    /// A chunk's RMS level, linear; called on the input's thread.
    func push(_ rms: Float) {
        let db = 20 * log10(max(rms, 1e-6))
        let at = now()
        lock.lock()
        levels.append((at, db))
        lock.unlock()
    }

    /// At each press: the levels start over.
    func reset() {
        lock.lock()
        levels.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    /// At release: `end` now if the voice is off, or once it is.
    @MainActor
    func release(_ end: @escaping @MainActor () -> Void) {
        let released = now()
        guard let threshold = threshold(), loud(since: released - Self.recent, threshold: threshold) else { return end() }
        pending = end
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = self.now()
                if t - released >= Self.cap || self.silent(since: t - Self.quiet, threshold: threshold) {
                    Log.info(String(format: "  voice on at release: recorded %.0f ms more", (t - released) * 1000))
                    self.flush()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Ends a wait now (a new press); nothing if none runs.
    @MainActor
    func flush() {
        timer?.invalidate()
        timer = nil
        let end = pending
        pending = nil
        end?()
    }

    @MainActor
    var isWaiting: Bool { pending != nil }

    /// Halfway between the recording's quiet and loud chunks, or nil when it
    /// is too short or too flat to tell voice from room.
    func threshold() -> Float? {
        lock.lock()
        let all = levels
        lock.unlock()
        guard let first = all.first, let last = all.last, last.at - first.at >= Self.minimumDuration else { return nil }
        return Self.threshold(all.map(\.db))
    }

    static func threshold(_ db: [Float]) -> Float? {
        guard db.count >= 10 else { return nil }
        let sorted = db.sorted()
        let low = sorted[sorted.count / 10], high = sorted[sorted.count * 9 / 10]
        guard high - low >= minimumSpread else { return nil }
        return low + (high - low) / 2
    }

    /// The chunks since `start` are loud on average.
    private func loud(since start: TimeInterval, threshold: Float) -> Bool {
        let recent = chunks(since: start)
        guard !recent.isEmpty else { return false }
        return recent.reduce(0, +) / Float(recent.count) > threshold
    }

    /// Every chunk since `start` is quiet, and there is at least one.
    private func silent(since start: TimeInterval, threshold: Float) -> Bool {
        let recent = chunks(since: start)
        return !recent.isEmpty && recent.allSatisfy { $0 <= threshold }
    }

    private func chunks(since start: TimeInterval) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return levels.reversed().prefix { $0.at >= start }.map(\.db)
    }
}
