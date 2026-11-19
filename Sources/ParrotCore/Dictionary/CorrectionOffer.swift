import Foundation

/// Offers to learn a correction the moment the user makes it (fork-019): a
/// word fixed by hand in a pasted dictation ("pip" → "Peep") shows a small
/// panel, "pip → Peep · Ajouter". One click writes it to the dictionary;
/// otherwise the panel goes away on its own. Asks first because the wrong
/// word is often a real one ("vert" → "verre"): only the user knows whether
/// they ever say it.
///
/// Fed by `CorrectionWatch.onEdit`. What the user adds is theirs: the
/// nightly review (fork-009) only ever removes its own entries. A pair let go
/// `maxRefusals` times is never offered again, nor proposed by the review.
@MainActor
final class CorrectionOffer {
    /// More substitutions than this in one edit is a rewrite, not a fix.
    nonisolated static let maxSubstitutions = 2
    /// Times a pair may be closed or left to time out before it is dropped.
    nonisolated static let maxRefusals = 2

    private let panel = CorrectionOfferPanel()

    func consider(pasted: String, edited: String) {
        let dictionary = (try? UserDictionary.parse(Data(contentsOf: Paths.dictionaryFile))) ?? .empty
        guard let offer = Self.offer(pasted: pasted, edited: edited, dictionary: dictionary, refusals: Refusals.load()) else { return }
        // Word counts only: the log never carries text.
        Log.info("  dictionary: offered a correction (\(offer.wrong.split(separator: " ").count) → \(offer.right.split(separator: " ").count) words)")
        panel.show(wrong: offer.wrong, right: offer.right) { accepted in
            Self.answer(offer, accepted: accepted)
        }
    }

    private static func answer(_ offer: WordAlignment.Substitution, accepted: Bool) {
        do {
            if accepted {
                try DictionaryEditor.add(wrong: offer.wrong, right: offer.right)
                Log.info("  dictionary: correction added by the user")
            } else {
                var refusals = Refusals.load()
                refusals.note(NightlyReview.key(wrong: offer.wrong, right: offer.right))
                try refusals.save()
                Log.info("  dictionary: correction let go")
            }
        } catch {
            Log.error("  dictionary: could not record the answer: \(error)")
        }
    }

    // MARK: - Pure, so it is tested

    /// The correction to offer for `pasted` edited into `edited`, or nil.
    ///
    /// One to three words for one to three (`WordAlignment`), the wrong side
    /// with three letters or more (two-letter words are grammar: "en" →
    /// "on", "la" → "le"), the right one with two ("bébé" → "BB"), each at
    /// most 40 characters; not a word being
    /// retyped (the fix a prefix of the paste); not already in the dictionary;
    /// never one of the user's own words as the wrong side; not let go
    /// `maxRefusals` times. The right side takes the dictionary's spelling
    /// when it has the word, and loses a capital that only started the
    /// sentence ("Vert" → "Verre" offers "verre", or every "verre" would be
    /// capitalised).
    nonisolated static func offer(
        pasted: String, edited: String, dictionary: UserDictionary, refusals: Refusals
    ) -> WordAlignment.Substitution? {
        let substitutions = WordAlignment.substitutions(from: pasted, to: edited)
        guard substitutions.count <= maxSubstitutions else { return nil }
        var terms: [String: String] = [:]
        for term in dictionary.terms where terms[term.lowercased()] == nil { terms[term.lowercased()] = term }
        let mapped = Set(dictionary.replacements.flatMap { r in r.from.map { NightlyReview.key(wrong: $0, right: r.to) } })

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
            return WordAlignment.Substitution(wrong: wrong, right: right)
        }
        return nil
    }
}

/// `dictionary-refusals.json`: how many times each offered pair was closed or
/// left to time out. Pairs only, owner-only, like the dictionary itself.
struct Refusals: Codable, Equatable {
    var pairs: [String: Int] = [:]

    func count(_ key: String) -> Int { pairs[key] ?? 0 }
    mutating func note(_ key: String) { pairs[key, default: 0] += 1 }
    /// Let go too often: neither the panel nor the nightly review offers it.
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
