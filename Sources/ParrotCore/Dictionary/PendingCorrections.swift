import Foundation

/// The corrections offered and not yet answered (fork-019), newest first:
/// what the notch shows on hover and the menu-bar panel lists. In memory
/// only — a restart empties it — and each one goes away by itself after
/// `lifetime`, unanswered, so the list never becomes a backlog.
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

    nonisolated static let lifetime: TimeInterval = 24 * 3600
    /// Oldest dropped beyond this.
    nonisolated static let maxItems = 20

    @Published private(set) var items: [Item] = []
    private let now: () -> Date
    /// Writes an answer: the dictionary for yes, the refusals for no.
    private let record: (Item, Bool) -> Void

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
        record(item, accepted)
    }

    /// Drops what has waited longer than `lifetime`.
    func prune() {
        let limit = now().addingTimeInterval(-Self.lifetime)
        if items.contains(where: { $0.added < limit }) { items.removeAll { $0.added < limit } }
    }

    nonisolated static func write(_ item: Item, accepted: Bool) {
        do {
            if accepted {
                try DictionaryEditor.add(wrong: item.wrong, right: item.right)
                Log.info("  dictionary: correction added by the user")
            } else {
                var refusals = Refusals.load()
                refusals.note(item.key)
                try refusals.save()
                Log.info("  dictionary: correction refused by the user")
            }
        } catch {
            Log.error("  dictionary: could not record the answer: \(error)")
        }
    }
}
