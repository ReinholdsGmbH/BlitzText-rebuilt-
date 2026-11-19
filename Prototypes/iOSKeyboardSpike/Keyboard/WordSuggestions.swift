import UIKit

/// Wortvorschläge und Swipe-Auflösung über Apples Rechtschreibprüfung (UITextChecker, Deutsch).
/// Kein eigenes Wörterbuch, keine Netzverbindung.
@MainActor
final class WordSuggestions {
    private let checker = UITextChecker()
    let language: String = UITextChecker.availableLanguages.first { $0.hasPrefix("de") } ?? "de_DE"

    /// Bis zu drei Vorschläge für das angefangene Wort.
    func suggestions(for partial: String) -> [String] {
        guard partial.count >= 1 else { return [] }
        let range = NSRange(location: 0, length: (partial as NSString).length)
        var result: [String] = []
        let misspelled = checker.rangeOfMisspelledWord(in: partial, range: range, startingAt: 0, wrap: false, language: language)
        if misspelled.location != NSNotFound {
            result += checker.guesses(forWordRange: range, in: partial, language: language) ?? []
        }
        result += checker.completions(forPartialWordRange: range, in: partial, language: language) ?? []
        return Self.unique(result.map { Self.matchCase($0, to: partial) }.filter { $0 != partial }, limit: 3)
    }

    /// Kandidaten für eine Swipe-Spur. `path` sind alle überstrichenen Buchstaben, `corners` die Richtungswechsel.
    func swipeCandidates(path: [String], corners: [String], limit: Int = 4) -> [String] {
        let letters = path.compactMap(\.first)
        guard let first = letters.first, let last = letters.last, letters.count >= 2 else { return [] }
        let cornerLetters = corners.compactMap(\.first)

        var prefixes = [String(first)]
        for second in letters.dropFirst().prefix(10) where !prefixes.contains(String([first, second])) {
            prefixes.append(String([first, second]))
        }
        var pool: [String] = []
        for prefix in prefixes {
            for variant in [prefix, prefix.prefix(1).uppercased() + prefix.dropFirst()] {
                let range = NSRange(location: 0, length: (variant as NSString).length)
                pool += (checker.completions(forPartialWordRange: range, in: variant, language: language) ?? []).prefix(400)
            }
        }

        var scored: [(word: String, score: Double)] = []
        for (rank, word) in pool.enumerated() where word.count >= 2 && !word.contains(" ") {
            let normalized = Self.normalize(word)
            guard normalized.first == first, normalized.last == last else { continue }
            let collapsed = Self.collapseDoubles(normalized)
            guard Self.isSubsequence(collapsed, of: letters) else { continue }
            let missingCorners = cornerLetters.count - Self.matchedCount(cornerLetters, in: collapsed)
            let skipped = letters.count - collapsed.count
            scored.append((word, Double(missingCorners) * 3 + Double(skipped) * 0.12 + Double(rank) * 0.0004))
        }
        return Self.unique(scored.sorted { $0.score < $1.score }.map(\.word), limit: limit)
    }

    // MARK: - Hilfen

    /// Kleinbuchstaben, ß wie s (kein ß auf der Buchstabenebene), andere Akzente entfernt, Umlaute bleiben.
    static func normalize(_ word: String) -> [Character] {
        word.lowercased().compactMap { character -> Character? in
            if "äöü".contains(character) { return character }
            if character == "ß" { return "s" }
            let folded = String(character).folding(options: .diacriticInsensitive, locale: .current)
            return folded.first.flatMap { $0.isLetter ? $0 : nil }
        }
    }

    static func collapseDoubles(_ letters: [Character]) -> [Character] {
        letters.reduce(into: []) { result, letter in if result.last != letter { result.append(letter) } }
    }

    static func isSubsequence(_ needle: [Character], of haystack: [Character]) -> Bool {
        var index = haystack.startIndex
        for letter in needle {
            guard let found = haystack[index...].firstIndex(of: letter) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }

    /// Wie viele Ecken das Wort in Reihenfolge trifft.
    static func matchedCount(_ corners: [Character], in word: [Character]) -> Int {
        var index = word.startIndex
        var count = 0
        for corner in corners {
            if let found = word[index...].firstIndex(of: corner) {
                count += 1
                index = word.index(after: found)
            }
        }
        return count
    }

    static func matchCase(_ word: String, to partial: String) -> String {
        guard let first = partial.first, first.isUppercase else { return word }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    static func unique(_ words: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for word in words where seen.insert(word.lowercased()).inserted {
            result.append(word)
            if result.count == limit { break }
        }
        return result
    }
}
