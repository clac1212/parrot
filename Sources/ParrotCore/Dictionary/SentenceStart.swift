import Foundation

/// A dictionary replacement keeps the capital that started a sentence
/// (fork-019): "C'est bon. Vert d'eau." with "vert → verre" gives "C'est bon.
/// Verre d'eau.", not "verre". Replacements are written in lowercase when
/// their word is a common one (fork-019 drops a capital that only started the
/// sentence), so without this every one met at a sentence start lost it.
enum SentenceStart {
    /// `to` as it should stand where `matched` was found, at `location` in
    /// `text`: with its first letter raised when `matched` began with a
    /// capital at a sentence start and `to` begins with a small letter.
    /// Anywhere else, `to` as the user wrote it.
    static func replacement(_ to: String, for matched: String, at location: Int, in text: NSString) -> String {
        guard let first = to.first, first.isLowercase,
              matched.first?.isUppercase == true,
              starts(at: location, in: text) else { return to }
        return first.uppercased() + to.dropFirst()
    }

    /// True if only spaces and opening quotes or brackets stand between
    /// `location` and the start of `text`, or the end of a sentence (. ! ? …)
    /// or a line.
    static func starts(at location: Int, in text: NSString) -> Bool {
        var i = location
        while i > 0 {
            guard let scalar = Unicode.Scalar(text.character(at: i - 1)) else { return false }
            if CharacterSet.whitespaces.contains(scalar) || "«“\"'(‘[".unicodeScalars.contains(scalar) {
                i -= 1
                continue
            }
            return CharacterSet.newlines.contains(scalar) || ".!?…".unicodeScalars.contains(scalar)
        }
        return true
    }
}
