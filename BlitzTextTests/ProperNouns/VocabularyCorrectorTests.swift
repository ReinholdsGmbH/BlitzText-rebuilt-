import Testing
@testable import BlitzText

private struct FakeChecker: WordChecking {
    let known: Set<String>
    func isKnownWord(_ word: String) -> Bool { known.contains(word.lowercased()) }
}

struct VocabularyCorrectorTests {

    private func corrector(known: Set<String> = []) -> VocabularyCorrector {
        VocabularyCorrector(checker: FakeChecker(known: known))
    }

    @Test("Fuzzy-Variante eines Eigennamens wird zur kanonischen Schreibweise korrigiert")
    func correctsFuzzyVariant() {
        let nouns = [ProperNoun(text: "Vardhaman")]
        let result = corrector().correct("Ich treffe Wardhaman heute.", using: nouns)
        #expect(result.text == "Ich treffe Vardhaman heute.")
        #expect(result.matches.count == 1)
        #expect(result.matches.first?.wasExact == false)
        #expect(result.matches.first?.original == "Wardhaman")
        #expect(result.matches.first?.termID == nouns[0].id)
    }

    @Test("Satzzeichen am Wort bleiben erhalten")
    func preservesPunctuation() {
        let nouns = [ProperNoun(text: "Vardhaman")]
        let result = corrector().correct("Hallo Wardhaman!", using: nouns)
        #expect(result.text == "Hallo Vardhaman!")
    }

    @Test("Bekanntes Wörterbuchwort wird NICHT zu einem Eigennamen über-korrigiert")
    func doesNotOvercorrectKnownWord() {
        let nouns = [ProperNoun(text: "Garden")]
        // "Garten" ist im Wörterbuch bekannt → Guard greift, keine Ersetzung.
        let result = corrector(known: ["garten"]).correct("Im Garten.", using: nouns)
        #expect(result.text == "Im Garten.")
        #expect(result.matches.isEmpty)
    }

    @Test("Exakter Treffer normalisiert die Schreibweise und markiert wasExact")
    func exactMatchNormalizesCasing() {
        let nouns = [ProperNoun(text: "Vardhaman")]
        let result = corrector().correct("vardhaman kommt.", using: nouns)
        #expect(result.text == "Vardhaman kommt.")
        #expect(result.matches.first?.wasExact == true)
    }

    @Test("Leere Liste ist No-Op")
    func emptyListIsNoOp() {
        let result = corrector().correct("Beliebiger Text.", using: [])
        #expect(result.text == "Beliebiger Text.")
        #expect(result.matches.isEmpty)
    }

    @Test("Treffer über einen Alias verwendet die kanonische Schreibweise")
    func aliasMatchUsesCanonical() {
        let nouns = [ProperNoun(text: "Vardhaman", aliases: ["Wardhaman"])]
        let result = corrector().correct("Wardhaman", using: nouns)
        #expect(result.text == "Vardhaman")
        #expect(result.matches.first?.wasExact == true) // Alias = bekannte Form
    }
}
