import UIKit

/// Wortvorschläge und Swipe-Auflösung über Apples Rechtschreibprüfung (UITextChecker, Deutsch).
/// Dazu eigene Wörter und Kontaktnamen. Keine Netzverbindung.
@MainActor
final class WordSuggestions {
    private let checker = UITextChecker()
    let language: String = UITextChecker.availableLanguages.first { $0.hasPrefix("de") } ?? "de_DE"

    /// Eigene Wörter aus der App Group (Tastatur und App teilen sie).
    var userWords: [String] = []
    /// Namen aus den Kontakten, die iOS der Tastatur bereitstellt.
    var lexiconWords: [String] = []

    private var extraWords: [String] { userWords + lexiconWords }
    /// Eigene Wortnutzung; oft benutzte Wörter stehen in den Vorschlägen weiter vorn.
    var usage: WordUsage?

    struct Result {
        /// Das getippte Wort, falls es unbekannt ist: erscheint wie bei Apple in „…“ an erster Stelle.
        let typed: String?
        let words: [String]
    }

    func isKnown(_ word: String) -> Bool {
        if extraWords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) { return true }
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language).location == NSNotFound
    }

    /// Vorschläge für das angefangene Wort: eigene Wörter zuerst, dann Korrekturen und Vervollständigungen.
    func suggestions(for partial: String) -> Result {
        guard !partial.isEmpty else { return Result(typed: nil, words: []) }
        // Das Getippte steht immer zur Wahl, auch wenn iOS es kennt (z. B. ein Name neben einem ähnlichen Wörterbuchwort),
        // außer es ist schon ein eigenes Wort.
        let isOwn = userWords.contains { $0.caseInsensitiveCompare(partial) == .orderedSame }
        let typed = partial.count >= 2 && !isOwn ? partial : nil
        let range = NSRange(location: 0, length: (partial as NSString).length)
        var result = extraWords.filter {
            $0.count > partial.count && $0.lowercased().hasPrefix(partial.lowercased())
        }
        if !isKnown(partial) {
            result += checker.guesses(forWordRange: range, in: partial, language: language) ?? []
        }
        result += (checker.completions(forPartialWordRange: range, in: partial, language: language) ?? [])
            .map { Self.matchCase($0, to: partial) }
        let ranked = result.enumerated().sorted { a, b in
            let ua = usage?.count(a.element) ?? 0, ub = usage?.count(b.element) ?? 0
            return ua != ub ? ua > ub : a.offset < b.offset
        }.map(\.element)
        let words = Self.unique(ranked.filter { $0 != partial }, limit: typed == nil ? 3 : 2)
        return Result(typed: typed, words: words)
    }

    /// Wort dauerhaft merken (App Group, auch in der App unter Einstellungen sichtbar).
    func learn(_ word: String) {
        guard !word.isEmpty, !userWords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        userWords.append(word)
        Blitz.userWords = userWords
        UITextChecker.learnWord(word)
    }

    /// Was die letzte Swipe-Auflösung gesehen hat (für die Anzeige, wenn nichts passt).
    private(set) var lastDiagnosis = ""

    /// Kandidaten für eine Swipe-Spur. `path` sind alle überstrichenen Buchstaben, `corners` die Richtungswechsel.
    /// Quellen: Vervollständigungen zu den ersten Buchstaben und Rechtschreib-Vorschläge zur Eckenfolge.
    /// Anfang und Ende dürfen eine Taste daneben liegen (Finger setzt oft knapp neben der Taste auf oder ab).
    func swipeCandidates(path: [String], corners: [String], limit: Int = 4) -> [String] {
        let letters = path.compactMap(\.first)
        guard letters.count >= 2 else { return [] }
        let cornerLetters = Self.collapseDoubles(corners.compactMap(\.first))
        let firsts = Set(letters.prefix(2))
        let lasts = Set(letters.suffix(2))

        var pool: [String] = extraWords
        func complete(_ prefix: String) {
            for variant in [prefix, prefix.prefix(1).uppercased() + prefix.dropFirst()] {
                let range = NSRange(location: 0, length: (variant as NSString).length)
                pool += (checker.completions(forPartialWordRange: range, in: variant, language: language) ?? []).prefix(500)
            }
        }
        func guess(_ word: String) {
            guard word.count >= 2 else { return }
            for variant in [word, word.prefix(1).uppercased() + word.dropFirst()] {
                let range = NSRange(location: 0, length: (variant as NSString).length)
                pool += checker.guesses(forWordRange: range, in: variant, language: language) ?? []
                if checker.rangeOfMisspelledWord(in: variant, range: range, startingAt: 0, wrap: false,
                                                 language: language).location == NSNotFound {
                    pool.append(variant)
                }
            }
        }
        guess(String(cornerLetters))
        for first in firsts {
            var seen = Set<String>()
            for second in letters.dropFirst().prefix(12) where seen.insert(String([first, second])).inserted {
                complete(String([first, second]))
            }
        }

        var scored: [(word: String, score: Double)] = []
        for (rank, word) in pool.enumerated() where word.count >= 2 && !word.contains(" ") {
            let normalized = Self.collapseDoubles(Self.normalize(word))
            guard let first = normalized.first, let last = normalized.last,
                  firsts.contains(first), lasts.contains(last),
                  Self.isSubsequence(normalized, of: letters) else { continue }
            let missingCorners = cornerLetters.count - Self.matchedCount(cornerLetters, in: normalized)
            let skipped = letters.count - normalized.count
            let edgePenalty = (first == letters.first ? 0 : 1.5) + (last == letters.last ? 0 : 1.5)
            scored.append((word, Double(missingCorners) * 3 + Double(skipped) * 0.1 + edgePenalty + Double(rank) * 0.0002))
        }
        let result = Self.unique(scored.sorted { $0.score < $1.score }.map(\.word), limit: limit)
        lastDiagnosis = "Spur \(String(letters)), Ecken \(String(cornerLetters)), \(pool.count) geprüft"
        return result
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
