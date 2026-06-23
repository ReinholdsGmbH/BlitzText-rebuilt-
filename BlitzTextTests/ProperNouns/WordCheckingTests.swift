import Testing
@testable import BlitzText

struct WordCheckingTests {

    @Test("SystemSpellChecker kennt gängiges deutsches Wort, nicht aber Kunstwort")
    @MainActor
    func systemCheckerDistinguishesKnownFromUnknown() {
        let checker = SystemSpellChecker(language: "de")
        #expect(checker.isKnownWord("Haus"))
        #expect(!checker.isKnownWord("Vardhaman"))
        #expect(!checker.isKnownWord("xqzwkpf"))
    }
}
