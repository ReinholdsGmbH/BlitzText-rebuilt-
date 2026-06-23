import Foundation

/// Geteilte Fuzzy-String-Hilfen für Korrektur (VocabularyCorrector) und
/// Erkennung (EigennamenAnalyzer). Längenabhängige Schwelle, damit kurze
/// Wörter nicht über-korrigiert werden.
enum StringSimilarity {

    /// Maximal erlaubte Edit-Distanz für ein Wort dieser Länge.
    static func maxDistance(forLength length: Int) -> Int {
        switch length {
        case ...5: return 1
        case 6...8: return 2
        default: return 3
        }
    }

    /// Case-insensitiver Fuzzy-Vergleich. True, wenn die Edit-Distanz die
    /// längenbasierte Schwelle nicht überschreitet und der Längenunterschied
    /// nicht schon allein größer als die Schwelle ist.
    static func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
        let lowerA = a.lowercased()
        let lowerB = b.lowercased()
        let threshold = maxDistance(forLength: max(lowerA.count, lowerB.count))
        guard abs(lowerA.count - lowerB.count) <= threshold else { return false }
        return levenshtein(lowerA, lowerB) <= threshold
    }

    /// Klassische Levenshtein-Distanz (Einfüge/Lösch/Ersetz = je 1).
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let n = aChars.count, m = bChars.count
        if n == 0 { return m }
        if m == 0 { return n }
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                dp[i][j] = Swift.min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
            }
        }
        return dp[n][m]
    }
}
