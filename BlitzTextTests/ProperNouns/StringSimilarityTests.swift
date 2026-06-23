import Testing
@testable import BlitzText

struct StringSimilarityTests {

    @Test("levenshtein zählt Einzel-Edits korrekt")
    func levenshteinCountsEdits() {
        #expect(StringSimilarity.levenshtein("kitten", "sitting") == 3)
        #expect(StringSimilarity.levenshtein("Vardhaman", "Vardhaman") == 0)
        #expect(StringSimilarity.levenshtein("", "abc") == 3)
    }

    @Test("maxDistance skaliert mit Wortlänge")
    func maxDistanceScalesWithLength() {
        #expect(StringSimilarity.maxDistance(forLength: 4) == 1)
        #expect(StringSimilarity.maxDistance(forLength: 7) == 2)
        #expect(StringSimilarity.maxDistance(forLength: 12) == 3)
    }

    @Test("isFuzzyMatch akzeptiert nahe Varianten, lehnt entfernte ab")
    func fuzzyMatchAcceptsCloseRejectsFar() {
        // "Vardhaman" (9) → maxDistance 3; "Wardhaman" = 1 Edit
        #expect(StringSimilarity.isFuzzyMatch("Vardhaman", "Wardhaman"))
        #expect(StringSimilarity.isFuzzyMatch("vardhaman", "VARDAMAN")) // case-insensitiv, 1 Edit
        // Kurzwort: "Ott" (3) → maxDistance 1; "Akt" = 2 Edits → kein Match
        #expect(!StringSimilarity.isFuzzyMatch("Ott", "Akt"))
        // Sehr verschiedene Wörter
        #expect(!StringSimilarity.isFuzzyMatch("Garten", "Vardhaman"))
    }
}
