import Foundation

/// Offers to learn a correction the moment the user makes it (fork-019): a
/// word fixed by hand in a pasted dictation ("pip" → "Peep") comes out of the
/// notch, "pip → Peep · Ajouter". Every correction of the edit waits in
/// `PendingCorrections` until the user answers, from the notch or the
/// menu-bar panel. Asks first because the wrong word is often a real one
/// ("vert" → "verre"): only the user knows whether they ever say it.
///
/// Fed by `CorrectionWatch.onEdit`. What the user adds is theirs: the
/// nightly review (fork-009) only ever removes its own entries. A pair the
/// user closed (✕), or left unanswered for `PendingCorrections.lifetime`, is
/// never offered again, nor proposed by the review.
enum CorrectionOffer {
    /// More substitutions than this in one edit is a rewrite, not a fix.
    static let maxSubstitutions = 2
    /// A ✕ is deliberate: one is final. The live offer's 5 s running out is
    /// no answer; it stays pending until `PendingCorrections.lifetime`.
    static let maxRefusals = 1

    /// Queues the corrections in `edited`; returns those that are new.
    @MainActor
    @discardableResult
    static func consider(pasted: String, edited: String) -> [PendingCorrections.Item] {
        let pending = PendingCorrections.shared
        let dictionary = (try? UserDictionary.parse(Data(contentsOf: Paths.dictionaryFile))) ?? .empty
        let found = offers(pasted: pasted, edited: edited, dictionary: dictionary, refusals: Refusals.load())
        let added = pending.add(found)
        // Counts only: the log never carries text.
        if !added.isEmpty { Log.info("  dictionary: \(added.count) correction(s) offered, \(pending.items.count) pending") }
        return added
    }

    // MARK: - Pure, so it is tested

    /// The corrections to offer for `pasted` edited into `edited`, in order.
    ///
    /// One to three words for one to three (`WordAlignment`), the wrong side
    /// with three letters or more (two-letter words are grammar: "en" →
    /// "on", "la" → "le"), the right one with two ("bébé" → "BB"), each at
    /// most 40 characters; not a word being retyped (the fix a prefix of the
    /// paste); not already in the dictionary; never one of the user's own
    /// words as the wrong side; not closed by the user (✕). The right side
    /// takes the dictionary's spelling when it has the word, and loses a
    /// capital that only started the sentence ("Vert" → "Verre" offers
    /// "verre", or every "verre" would be capitalised).
    static func offers(
        pasted: String, edited: String, dictionary: UserDictionary, refusals: Refusals
    ) -> [WordAlignment.Substitution] {
        let substitutions = WordAlignment.substitutions(from: pasted, to: edited)
        guard substitutions.count <= maxSubstitutions else { return [] }
        var terms: [String: String] = [:]
        for term in dictionary.terms where terms[term.lowercased()] == nil { terms[term.lowercased()] = term }
        let mapped = Set(dictionary.replacements.flatMap { r in r.from.map { NightlyReview.key(wrong: $0, right: r.to) } })

        var out: [WordAlignment.Substitution] = []
        for substitution in substitutions {
            let wrong = substitution.wrong
            var right = substitution.right
            if let known = terms[right.lowercased()] {
                right = known
            } else if wrong.first?.isUppercase == true, right.first?.isUppercase == true,
                      !WordAlignment.isDistinctiveCasing(right) {
                right = right.prefix(1).lowercased() + right.dropFirst()
            }
            let key = NightlyReview.key(wrong: wrong, right: right)
            guard wrong.filter(\.isLetter).count >= 3, right.filter(\.isLetter).count >= 2,
                  wrong.count <= 40, right.count <= 40,
                  !wrong.lowercased().hasPrefix(right.lowercased()),
                  !mapped.contains(key), terms[wrong.lowercased()] == nil,
                  !refusals.dropped(key)
            else { continue }
            out.append(WordAlignment.Substitution(wrong: wrong, right: right))
        }
        return out
    }
}

/// `dictionary-refusals.json`: the offered pairs the user closed (✕). Pairs
/// only, owner-only, like the dictionary itself.
struct Refusals: Codable, Equatable {
    var pairs: [String: Int] = [:]

    func count(_ key: String) -> Int { pairs[key] ?? 0 }
    mutating func note(_ key: String) { pairs[key, default: 0] += 1 }
    /// Closed by the user: neither the offer nor the nightly review brings it back.
    func dropped(_ key: String) -> Bool { count(key) >= CorrectionOffer.maxRefusals }

    static var file: URL { Paths.appSupport.appendingPathComponent("dictionary-refusals.json") }
    static func load() -> Refusals {
        (try? JSONDecoder().decode(Refusals.self, from: Data(contentsOf: file))) ?? Refusals()
    }
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Paths.preparePrivateFile(Self.file))
    }
}
