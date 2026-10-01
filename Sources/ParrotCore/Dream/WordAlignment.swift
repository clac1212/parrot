import Foundation

/// Word-level alignment of two versions of a dictation, for the nightly
/// review (fork-009): what Parrot pasted against what the user kept, or
/// against a heavier model's re-transcription. Pure, so it is tested.
enum WordAlignment {
    /// A word as written, and the form compared: lowercased, straight
    /// apostrophe, no surrounding punctuation.
    struct Token: Equatable {
        var text: String
        var key: String
    }

    /// A substitution of up to `maxWords` words by up to `maxWords` words.
    struct Substitution: Equatable, Hashable {
        /// As the first text wrote it.
        var wrong: String
        /// As the second text wrote it.
        var right: String
    }

    static let maxWords = 3

    static func tokens(_ text: String) -> [Token] {
        let normalized = text.replacingOccurrences(of: "’", with: "'")
        let pattern = #"[\p{L}\p{N}][\p{L}\p{N}'\-]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = normalized as NSString
        return regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)).map {
            let word = ns.substring(with: $0.range)
            return Token(text: word, key: word.lowercased())
        }
    }

    /// The substitutions that turn `from` into `to`: replaced runs of one to
    /// `maxWords` words on each side, plus words that only changed casing
    /// into a spelling with capitals inside or all capitals (`posthog` →
    /// `PostHog`, `pr` → `PR`), which a dictionary entry can enforce.
    static func substitutions(from: String, to: String) -> [Substitution] {
        let a = tokens(from), b = tokens(to)
        var out: [Substitution] = []
        for op in opcodes(a.map(\.key), b.map(\.key)) {
            switch op {
            case .replace(let ar, let br):
                guard ar.count <= maxWords, br.count <= maxWords else { continue }
                out.append(Substitution(
                    wrong: a[ar].map(\.text).joined(separator: " "),
                    right: b[br].map(\.text).joined(separator: " ")
                ))
            case .equal(let ar, let br):
                for (i, j) in zip(ar, br) where a[i].text != b[j].text && isDistinctiveCasing(b[j].text) {
                    out.append(Substitution(wrong: a[i].text, right: b[j].text))
                }
            }
        }
        return out
    }

    /// `PostHog`, `PR`, `N8N`: capitals a dictionary entry can enforce, unlike
    /// a capital that only starts a sentence.
    static func isDistinctiveCasing(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        guard letters.count >= 2 else { return false }
        let upper = letters.filter(\.isUppercase).count
        return upper == letters.count || letters.dropFirst().contains(where: \.isUppercase)
    }

    enum Opcode: Equatable {
        case equal(Range<Int>, Range<Int>)
        case replace(Range<Int>, Range<Int>)
    }

    /// Longest-common-subsequence alignment. Inserted or deleted runs with
    /// nothing opposite are dropped: a missing word is not a substitution.
    static func opcodes(_ a: [String], _ b: [String]) -> [Opcode] {
        let n = a.count, m = b.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var ops: [Opcode] = []
        var i = 0, j = 0, gapA = 0, gapB = 0
        func flush() {
            if i > gapA, j > gapB { ops.append(.replace(gapA..<i, gapB..<j)) }
        }
        while i < n, j < m {
            if a[i] == b[j] {
                flush()
                let startA = i, startB = j
                while i < n, j < m, a[i] == b[j] { i += 1; j += 1 }
                ops.append(.equal(startA..<i, startB..<j))
                gapA = i; gapB = j
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        i = n; j = m
        flush()
        return ops
    }

    /// A few words around `phrase` in `text`, for the judge's evidence.
    static func excerpt(_ text: String, around phrase: String, words: Int = 6) -> String? {
        let all = tokens(text)
        let target = tokens(phrase).map(\.key)
        guard !target.isEmpty, all.count >= target.count else { return nil }
        for start in 0...(all.count - target.count) where all[start..<(start + target.count)].map(\.key) == target {
            let from = max(0, start - words), to = min(all.count, start + target.count + words)
            return all[from..<to].map(\.text).joined(separator: " ")
        }
        return nil
    }
}

/// A rough French phonetic key, to tell a mishearing ("Vercelle" for
/// "Vercel") from a different word. Pure, so it is tested.
enum FrenchPhonetics {
    static func key(_ text: String) -> String {
        var s = text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        s = s.filter { $0.isLetter || $0.isNumber || $0 == " " }
        let rules: [(String, String)] = [
            ("eaux", "o"), ("eau", "o"), ("aux", "o"), ("au", "o"), ("ph", "f"), ("qu", "k"), ("ck", "k"),
            ("ch", "x"), ("sh", "x"), ("gu", "g"), ("ge", "je"), ("gi", "ji"), ("ce", "se"), ("ci", "si"),
            ("cy", "si"), ("c", "k"), ("ss", "s"), ("th", "t"), ("w", "v"), ("y", "i"), ("z", "s"),
            ("ai", "e"), ("ei", "e"), ("er ", "e "), ("ez ", "e "), ("et ", "e "), ("h", ""),
            ("ll", "l"), ("tt", "t"), ("nn", "n"), ("mm", "m"), ("pp", "p"), ("rr", "r"), ("ff", "f"),
        ]
        s += " "
        for (from, to) in rules { s = s.replacingOccurrences(of: from, with: to) }
        // Silent final letters.
        let words = s.split(separator: " ").map { word -> String in
            var w = String(word)
            if w.count > 1, let last = w.last, "estdxp".contains(last) { w.removeLast() }
            return w
        }
        return words.joined()
    }

    /// 1 for the same key, toward 0 for unrelated sounds.
    static func similarity(_ a: String, _ b: String) -> Double {
        let ka = Array(key(a)), kb = Array(key(b))
        guard !ka.isEmpty || !kb.isEmpty else { return 1 }
        var row = Array(0...kb.count)
        for i in 1...max(1, ka.count) where !ka.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: kb.count, by: 1) {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (ka[i - 1] == kb[j - 1] ? 0 : 1))
                previous = current
            }
        }
        let distance = ka.isEmpty ? kb.count : row[kb.count]
        return 1 - Double(distance) / Double(max(ka.count, kb.count))
    }
}
