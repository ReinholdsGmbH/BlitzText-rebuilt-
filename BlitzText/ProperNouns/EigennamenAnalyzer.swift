import Foundation
import NaturalLanguage

/// Eigennamen-Erkennung (Variante 1 + 2).
/// - Variante 1: NLTagger Named Entity Recognition (Personen / Firmen / Orte) — on-device
/// - Variante 2: Wörter, die zwischen Roh und Poliert in der Schreibweise differieren
enum EigennamenAnalyzer {

    static func candidates(
        rawTranscript: String,
        polished: String?,
        checker: WordChecking = SystemSpellChecker()
    ) -> [String] {
        var found = Set<String>()

        for word in namedEntities(in: rawTranscript) {
            found.insert(word)
        }
        if let polished {
            for word in namedEntities(in: polished) {
                found.insert(word)
            }
            for word in correctedSpellings(raw: rawTranscript, polished: polished) {
                found.insert(word)
            }
        }

        // Gates: Ketten splitten, Mindestlänge 4, bekannte Wörterbuchwörter raus.
        var result = Set<String>()
        for entry in found {
            for piece in entry.split(separator: " ").map(String.init) {
                let token = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                guard token.count >= 4 else { continue }
                guard !checker.isKnownWord(token) else { continue }
                result.insert(token)
            }
        }
        return result.sorted()
    }

    // MARK: - Variante 1: Apple NLTagger NER

    private static func namedEntities(in text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let target: Set<NLTag> = [.personalName, .organizationName, .placeName]
        var entities: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            if let tag, target.contains(tag) {
                let word = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !word.isEmpty {
                    entities.append(word)
                }
            }
            return true
        }
        return entities
    }

    // MARK: - Variante 2

    /// Wenn Polished ein Wort enthält, das im Raw als ähnliche, aber abweichende
    /// Schreibung auftaucht, ist es ein Hinweis auf einen Eigennamen, den das LLM korrigiert hat.
    private static func correctedSpellings(raw: String, polished: String) -> [String] {
        let rawWords = words(raw)
        let polishedWords = Set(words(polished))
        var corrected: [String] = []
        for pw in polishedWords where pw.count >= 4 {
            guard let first = pw.first, first.isUppercase else { continue }
            // Wenn kein exakt gleiches Wort im Roh-Transkript steht, aber ein ähnliches → Korrektur
            if !rawWords.contains(pw) {
                if rawWords.contains(where: { similar($0, pw) }) {
                    corrected.append(pw)
                }
            }
        }
        return corrected
    }

    private static func words(_ text: String) -> [String] {
        let stripChars = ",;:.!?\"\u{201E}\u{201C}\u{201D}()\u{00AB}\u{00BB}\u{2014}-"
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: stripChars)) }
            .filter { !$0.isEmpty }
    }

    /// Sehr einfache Levenshtein-basierte Ähnlichkeit (≤2 Edits) für ähnlich klingende Wörter
    private static func similar(_ a: String, _ b: String) -> Bool {
        guard abs(a.count - b.count) <= 2 else { return false }
        return levenshtein(a.lowercased(), b.lowercased()) <= 2
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let n = aChars.count, m = bChars.count
        if n == 0 { return m }
        if m == 0 { return n }
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
                dp[i][j] = Swift.min(
                    dp[i-1][j] + 1,
                    dp[i][j-1] + 1,
                    dp[i-1][j-1] + cost
                )
            }
        }
        return dp[n][m]
    }
}
