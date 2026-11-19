import Foundation
import Testing
@testable import BlitzText

@MainActor
struct PhoneDictionarySyncTests {

    @Test("Vereinigung: neue Wörter von beiden Seiten, Aliase zusammengeführt, keine Doppelten")
    func mergeUnion() {
        let phone = [SharedDictionary.Entry(text: "Raba", aliases: []), .init(text: "Kursbar", aliases: [])]
        let mac = [SharedDictionary.Entry(text: "kursbar", aliases: ["Kurs bar"]), .init(text: "Libra", aliases: [])]
        let merged = SharedDictionary.merge(phone, mac)
        #expect(merged.map(\.text) == ["Kursbar", "Libra", "Raba"])
        #expect(merged.first { $0.text == "Kursbar" }?.aliases == ["Kurs bar"])
    }

    @Test("Abgleich übernimmt iPhone-Wörter in die Eigennamen und schreibt die Mac-Wörter in die Datei")
    func syncBothWays() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-dict-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file = temp.appendingPathComponent("woerterbuch.json")
        try Data("""
        {"format":"blitztext-dictionary","version":1,"updatedAt":"2026-11-19T12:00:00Z",
         "entries":[{"text":"Raba","aliases":[]}]}
        """.utf8).write(to: file)

        var nouns = [ProperNoun(text: "Libra", aliases: ["Liebra"])]
        let sync = PhoneDictionarySync(rootPath: { temp.path }, nouns: { nouns }, setNouns: { nouns = $0 })
        #expect(sync.sync() == 1)
        #expect(nouns.map(\.text).sorted() == ["Libra", "Raba"])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let written = try decoder.decode(SharedDictionary.self, from: Data(contentsOf: file))
        #expect(written.entries.map(\.text) == ["Libra", "Raba"])
        #expect(written.entries.first?.aliases == ["Liebra"])
        #expect(sync.sync() == 0)
    }
}
