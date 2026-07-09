import Testing
@testable import BlitzText

struct SemanticVersionTests {

    @Test("Parst gültige Versionsstrings inkl. führendem v und fehlenden Komponenten",
          arguments: [
            (in: "0.6.1",   major: 0, minor: 6, patch: 1),
            (in: "v0.6.1",  major: 0, minor: 6, patch: 1),
            (in: "V1.0.0",  major: 1, minor: 0, patch: 0),
            (in: "1",       major: 1, minor: 0, patch: 0),
            (in: "1.2",     major: 1, minor: 2, patch: 0),
            (in: " v2.10.3 ", major: 2, minor: 10, patch: 3),
            (in: "0.6.1-beta.2", major: 0, minor: 6, patch: 1),  // Suffix wird ignoriert
          ])
    func parsesValid(pair: (in: String, major: Int, minor: Int, patch: Int)) {
        let v = SemanticVersion(pair.in)
        #expect(v == SemanticVersion(major: pair.major, minor: pair.minor, patch: pair.patch))
    }

    @Test("Verwirft Müll", arguments: ["", "v", "abc", "1..2", "x.y.z", "..."])
    func rejectsGarbage(raw: String) {
        #expect(SemanticVersion(raw) == nil)
    }

    @Test("Ordnet Versionen korrekt (major vor minor vor patch)")
    func ordersCorrectly() {
        #expect(SemanticVersion("0.6.0")! < SemanticVersion("0.6.1")!)
        #expect(SemanticVersion("0.6.1")! < SemanticVersion("0.7.0")!)
        #expect(SemanticVersion("0.9.9")! < SemanticVersion("1.0.0")!)
        #expect(SemanticVersion("0.10.0")! > SemanticVersion("0.9.0")!)   // numerisch, nicht lexikografisch
        #expect(SemanticVersion("1.0.0")! == SemanticVersion("1.0.0")!)
        #expect(!(SemanticVersion("0.6.0")! < SemanticVersion("0.6.0")!))
    }
}
