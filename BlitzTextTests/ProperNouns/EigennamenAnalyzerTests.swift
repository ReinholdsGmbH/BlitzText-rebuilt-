import Testing
@testable import BlitzText

private struct FakeDict: WordChecking {
    let known: Set<String>
    func isKnownWord(_ word: String) -> Bool { known.contains(word.lowercased()) }
}

struct EigennamenAnalyzerTests {

    @Test("Mehr-Wort-NER-Treffer werden in Einzelwörter gesplittet")
    func splitsMultiWordChains() {
        // "Hey Clara" darf nie als ein Eintrag erscheinen.
        let result = EigennamenAnalyzer.candidates(
            rawTranscript: "Hey Clara wie geht es dir",
            polished: nil,
            checker: FakeDict(known: ["hey", "wie", "geht", "es", "dir"])
        )
        #expect(!result.contains("Hey Clara"))
        #expect(!result.contains(where: { $0.contains(" ") }))
        #expect(result.contains("Clara"))
    }

    @Test("Bekannte Wörterbuchwörter werden herausgefiltert")
    func dropsDictionaryWords() {
        let result = EigennamenAnalyzer.candidates(
            rawTranscript: "Garten Vardhaman",
            polished: nil,
            checker: FakeDict(known: ["garten"])
        )
        #expect(!result.contains("Garten"))
    }

    @Test("Wörter kürzer als 4 Zeichen werden verworfen")
    func dropsShortWords() {
        let result = EigennamenAnalyzer.candidates(
            rawTranscript: "Ott und Ann",
            polished: nil,
            checker: FakeDict(known: [])
        )
        #expect(result.allSatisfy { $0.count >= 4 })
    }
}
