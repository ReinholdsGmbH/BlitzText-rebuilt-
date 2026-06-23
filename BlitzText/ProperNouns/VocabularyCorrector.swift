import Foundation

/// Problem A — das Herzstück: korrigiert ASR-Output anhand der gespeicherten
/// Eigennamen-Liste (exakt + fuzzy), backend-agnostisch und on-device.
/// Nicht-exakte Treffer melden den Originalwortlaut als neu entdeckten Alias.
struct VocabularyCorrector {

    struct Match: Equatable {
        let termID: UUID
        let original: String   // Wort, wie es im Transkript stand
        let canonical: String  // kanonische Schreibweise (term.text)
        let wasExact: Bool     // true, wenn original bereits eine bekannte Form war
    }

    struct Result: Equatable {
        let text: String
        let matches: [Match]
    }

    /// Wortkerne unter dieser Länge werden nie korrigiert (Schutz für Kurzwörter).
    private static let minCoreLength = 4

    let checker: WordChecking

    init(checker: WordChecking = SystemSpellChecker()) {
        self.checker = checker
    }

    func correct(_ text: String, using nouns: [ProperNoun]) -> Result {
        guard !nouns.isEmpty else { return Result(text: text, matches: []) }

        var matches: [Match] = []
        // An Leerzeichen splitten, Trenner erhalten (Tabs/Newlines bleiben so bestehen).
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        let corrected = tokens.map { token -> String in
            let (prefix, core, suffix) = Self.peel(token)
            guard core.count >= Self.minCoreLength else { return token }

            guard let hit = bestMatch(for: core, in: nouns) else { return token }
            matches.append(
                Match(termID: hit.term.id, original: core, canonical: hit.term.text, wasExact: hit.exact)
            )
            // Exakter Treffer → kanonische Schreibweise direkt übernehmen (Normalisierung).
            // Fuzzy-Treffer → Groß-/Kleinschreibung des Originals auf die Ersetzung übertragen.
            let replacement = hit.exact
                ? hit.term.text
                : Self.applyCasing(of: core, to: hit.term.text)
            return prefix + replacement + suffix
        }

        return Result(text: corrected.joined(separator: " "), matches: matches)
    }

    // MARK: - Matching

    private struct Hit { let term: ProperNoun; let exact: Bool; let distance: Int }

    private func bestMatch(for core: String, in nouns: [ProperNoun]) -> Hit? {
        let lowerCore = core.lowercased()

        // 1. Exakter Treffer (case-insensitiv) über text oder Alias.
        for term in nouns where term.allForms.contains(where: { $0.lowercased() == lowerCore }) {
            return Hit(term: term, exact: true, distance: 0)
        }

        // 2. Fuzzy — nur wenn das Quellwort dem Wörterbuch UNbekannt ist (Über-Korrektur-Guard).
        guard !checker.isKnownWord(core) else { return nil }

        var best: Hit?
        for term in nouns {
            for form in term.allForms where StringSimilarity.isFuzzyMatch(core, form) {
                let d = StringSimilarity.levenshtein(lowerCore, form.lowercased())
                if best == nil || d < best!.distance {
                    best = Hit(term: term, exact: false, distance: d)
                }
            }
        }
        return best
    }

    // MARK: - Token-Zerlegung

    /// Zerlegt „Vardhaman," in ("", "Vardhaman", ","). Kern = führende/folgende
    /// Nicht-Buchstaben abgeschnitten.
    private static func peel(_ token: String) -> (prefix: String, core: String, suffix: String) {
        let chars = Array(token)
        var start = 0
        var end = chars.count
        while start < end, !chars[start].isLetter { start += 1 }
        while end > start, !chars[end - 1].isLetter { end -= 1 }
        let prefix = String(chars[0..<start])
        let core = String(chars[start..<end])
        let suffix = String(chars[end..<chars.count])
        return (prefix, core, suffix)
    }

    /// Überträgt die Groß-/Kleinschreibung des Originals aufs Ersatzwort
    /// (Erstbuchstabe groß → kapitalisieren, sonst kleinschreiben).
    private static func applyCasing(of original: String, to replacement: String) -> String {
        guard let first = original.first else { return replacement }
        if first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        } else {
            return replacement.lowercased()
        }
    }
}
