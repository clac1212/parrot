import ApplicationServices
import Foundation
import NaturalLanguage

/// The first letter of a dictation follows the text before the cursor
/// (fork-014): a capital at the start of a field or after a sentence, a small
/// letter in the middle of one ("Bonjour, | je voulais…"). Parakeet capitalizes
/// every transcript as if it started a sentence.
///
/// Runs as a processor, so the corpus and `CorrectionWatch` see the text
/// that was pasted. Changes nothing when the app doesn't say what is before
/// the cursor, or when dictations wait on the clipboard (fork-013), which
/// are pasted first.
struct CapitalizationProcessor: TranscriptProcessor {
    let store: DictionaryStore

    func process(_ transcript: Transcript) -> Transcript {
        // The controller runs processors on the main actor.
        let lead = MainActor.assumeIsolated { () -> Capitalization.Lead in
            guard PendingDictations.shared.isEmpty else { return .unknown }
            let focus = FocusSnapshot.capture()
            guard let element = focus.element, !focus.isSecure else { return .unknown }
            return Capitalization.lead(element.textBefore())
        }
        let dictionary = store.current().dictionary
        var text = transcript
        text.text = Capitalization.adapt(transcript.text, lead: lead) {
            Capitalization.isProperName($0, in: transcript.text, dictionary: dictionary)
        }
        return text
    }
}

enum Capitalization {
    /// What the text before the cursor asks of the next word.
    enum Lead: Equatable {
        /// Start of the field, of a sentence, or of a line: a capital.
        case sentence
        /// The middle of a sentence: a small letter.
        case continuation
        /// The app didn't say, or it's ambiguous: leave the text alone.
        case unknown
    }

    /// The text before the cursor: nil when unknown, "" at the start of the
    /// field. Pure, so it is tested.
    static func lead(_ before: String?) -> Lead {
        guard let before else { return .unknown }
        var sawClosing = false
        for character in before.reversed() {
            if character.isNewline { return .sentence }
            if character.isWhitespace { continue }
            // "fin.» |" or "(voilà.) |": look past what closes.
            if closing.contains(character) { sawClosing = true; continue }
            if sentenceEnds.contains(character) { return .sentence }
            if sawClosing { return .unknown }
            if character.isLetter || character.isNumber || midSentence.contains(character) { return .continuation }
            return .unknown
        }
        // Only spaces, or nothing: the start of the field when the window
        // reached it, which `textBefore` says by returning less than it asked.
        return before.utf16.count < FocusedElement.lookBack ? .sentence : .unknown
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]
    private static let closing: Set<Character> = [")", "]", "»", "”", "’", "\"", "'"]
    /// Not dashes: one that starts a line is a list item.
    private static let midSentence: Set<Character> = [",", ";", ":"]

    /// `text` with its first letter fitted to `lead`. Only a word written
    /// "Like this" loses its capital — not "PR", "PostHog", "I", nor one
    /// `isProperName` keeps; only a word with no capital gains one.
    static func adapt(_ text: String, lead: Lead, isProperName: (String) -> Bool) -> String {
        let word = String(text.prefix { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" })
        guard let first = word.first, first.isLetter else { return text }
        let rest = word.dropFirst()
        switch lead {
        case .unknown:
            return text
        case .sentence:
            guard !word.contains(where: \.isUppercase) else { return text }
            return first.uppercased() + text.dropFirst()
        case .continuation:
            guard first.isUppercase, !rest.contains(where: \.isUppercase), word != "I",
                  !isProperName(word) else { return text }
            return first.lowercased() + text.dropFirst()
        }
    }

    /// A name to keep capitalized: written so in the user's dictionary, or
    /// named a person, place or organization by NaturalLanguage.
    static func isProperName(_ word: String, in text: String, dictionary: UserDictionary) -> Bool {
        let spellings = dictionary.terms + dictionary.replacements.map(\.to)
        if spellings.contains(where: { $0 == word || $0.hasPrefix(word + " ") }) { return true }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .word, scheme: .nameType)
        return tag == .personalName || tag == .placeName || tag == .organizationName
    }
}

extension FocusedElement {
    /// How far back `textBefore` reads, in UTF-16 units.
    static let lookBack = 16

    /// Up to `lookBack` units of text before the insertion point: less when
    /// the field starts sooner, "" at its start, nil when the app doesn't
    /// say. Call after `FocusSnapshot.capture()`, which sets the timeout.
    func textBefore() -> String? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }
        // Terminals report 0 wherever the cursor is (see `textBeforeCursor`):
        // trust it only in an empty field.
        if range.location == 0 { return isEmpty() ? "" : nil }
        let length = min(range.location, Self.lookBack)
        var window = CFRange(location: range.location - length, length: length)
        var text: CFTypeRef?
        if let query = AXValueCreate(.cfRange, &window),
           AXUIElementCopyParameterizedAttributeValue(ref, kAXStringForRangeParameterizedAttribute as CFString, query, &text) == .success,
           let text = text as? String {
            return text
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, kAXValueAttribute as CFString, &value) == .success,
              let value = value as? String else { return nil }
        let units = value.utf16
        guard range.location <= units.count else { return nil }
        let end = units.index(units.startIndex, offsetBy: range.location)
        return String(units[units.index(end, offsetBy: -length)..<end])
    }

    private func isEmpty() -> Bool {
        var count: CFTypeRef?
        if AXUIElementCopyAttributeValue(ref, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
           let count = count as? Int {
            return count == 0
        }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(ref, kAXValueAttribute as CFString, &value) == .success
            && (value as? String)?.isEmpty == true
    }
}
