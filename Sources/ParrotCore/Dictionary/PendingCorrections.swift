import Foundation

/// The corrections offered and not yet answered (fork-019), newest first:
/// what the notch shows on hover and the menu-bar panel lists. In memory
/// only — a restart empties it. Unanswered after `lifetime`, a correction
/// is refused, as if by ✕.
@MainActor
final class PendingCorrections: ObservableObject {
    static let shared = PendingCorrections()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let wrong: String
        let right: String
        let added: Date

        var key: String { NightlyReview.key(wrong: wrong, right: right) }
    }

    /// Unanswered this long, a correction counts as refused: silence is the
    /// user's « no », and saves a click (the user, 2026-11-19; it was 24 h,
    /// and the list stayed in the way).
    nonisolated static let lifetime: TimeInterval = 2 * 60
    /// Oldest dropped beyond this.
    nonisolated static let maxItems = 20

    @Published private(set) var items: [Item] = []
    private let now: () -> Date
    /// Writes an answer: the dictionary for yes, the refusals for no.
    private let record: (Item, Bool) -> Void
    private var expiry: Timer?

    init(now: @escaping () -> Date = Date.init, record: @escaping (Item, Bool) -> Void = PendingCorrections.write) {
        self.now = now
        self.record = record
    }

    /// Queues `offers` on top; one already pending moves to the top and
    /// keeps its identity. Returns the ones that were not pending.
    @discardableResult
    func add(_ offers: [WordAlignment.Substitution]) -> [Item] {
        prune()
        var added: [Item] = []
        for offer in offers.reversed() {
            let key = NightlyReview.key(wrong: offer.wrong, right: offer.right)
            if let i = items.firstIndex(where: { $0.key == key }) {
                items.insert(items.remove(at: i), at: 0)
            } else {
                let item = Item(wrong: offer.wrong, right: offer.right, added: now())
                items.insert(item, at: 0)
                added.insert(item, at: 0)
            }
        }
        if items.count > Self.maxItems { items.removeLast(items.count - Self.maxItems) }
        scheduleExpiry()
        return added
    }

    /// Moves `item` to the top.
    func raise(_ item: Item) {
        guard let i = items.firstIndex(where: { $0.id == item.id }), i > 0 else { return }
        items.insert(items.remove(at: i), at: 0)
    }

    /// The user's answer: `true` adds it to the dictionary, `false` (✕)
    /// drops it for good.
    func answer(_ item: Item, accepted: Bool) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: i)
        Log.info("  dictionary: correction \(accepted ? "added" : "refused") by the user")
        record(item, accepted)
        scheduleExpiry()
    }

    /// Refuses what has waited `lifetime` unanswered.
    func prune() {
        let limit = now().addingTimeInterval(-Self.lifetime)
        let expired = items.filter { $0.added <= limit }
        guard !expired.isEmpty else { return }
        items.removeAll { $0.added <= limit }
        Log.info("  dictionary: \(expired.count) correction(s) unanswered for \(Int(Self.lifetime / 60)) min, refused")
        for item in expired { record(item, false) }
    }

    /// Prunes when the oldest correction runs out.
    private func scheduleExpiry() {
        expiry?.invalidate()
        guard let oldest = items.map(\.added).min() else { return expiry = nil }
        // A delay from `now`, not a date: the tests' clock isn't the wall's.
        let delay = max(0, oldest.addingTimeInterval(Self.lifetime).timeIntervalSince(now()))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prune()
                self?.scheduleExpiry()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiry = timer
    }

    nonisolated static func write(_ item: Item, accepted: Bool) {
        do {
            if accepted {
                try DictionaryEditor.add(wrong: item.wrong, right: item.right)
            } else {
                var refusals = Refusals.load()
                refusals.note(item.key)
                try refusals.save()
            }
        } catch {
            Log.error("  dictionary: could not record the answer: \(error)")
        }
    }
}
