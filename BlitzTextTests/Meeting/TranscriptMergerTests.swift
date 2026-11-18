import Testing
@testable import BlitzText

struct TranscriptMergerTests {

    private func line(_ speaker: TranscriptLine.Speaker, _ start: Double, _ end: Double, _ text: String) -> TranscriptLine {
        TranscriptLine(speaker: speaker, start: start, end: end, text: text)
    }

    @Test("Beiträge beider Spuren werden nach Startzeit verschränkt")
    func interleavesByStart() {
        let merged = TranscriptMerger.merge([
            line(.me, 20, 25, "Dann machen wir das so."),
            line(.others, 0, 5, "Hallo zusammen."),
            line(.me, 6, 8, "Hallo."),
            line(.others, 30, 35, "Prima, bis morgen.")
        ])
        #expect(merged.map(\.speaker) == [.others, .me, .me, .others])
        #expect(merged.first?.text == "Hallo zusammen.")
    }

    @Test("Echo der Lautsprecher im Mikrofon fliegt raus")
    func dropsEcho() {
        let merged = TranscriptMerger.merge([
            line(.others, 10, 15, "Wir verschieben den Release auf Donnerstag"),
            line(.me, 10.3, 15.2, "verschieben den Release auf Donnerstag"),
            line(.me, 40, 42, "Einverstanden")
        ])
        #expect(merged.count == 2)
        #expect(merged.allSatisfy { !($0.speaker == .me && $0.text.contains("Release")) })
    }

    @Test("Gleicher Text ohne zeitliche Überlappung ist kein Echo")
    func sameTextLaterIsNotEcho() {
        let merged = TranscriptMerger.merge([
            line(.others, 10, 12, "Alles klar"),
            line(.me, 60, 62, "Alles klar")
        ])
        #expect(merged.count == 2)
    }

    @Test("Aufeinanderfolgende Beiträge derselben Seite werden zu einem Absatz")
    func joinsConsecutive() {
        let merged = TranscriptMerger.merge([
            line(.others, 0, 5, "Erster Satz."),
            line(.others, 6, 9, "Zweiter Satz."),
            line(.others, 40, 42, "Viel später.")
        ])
        #expect(merged.count == 2)
        #expect(merged[0].text == "Erster Satz. Zweiter Satz.")
        #expect(merged[0].end == 9)
    }

    @Test("Ähnlichkeit misst den Anteil des kürzeren Textes")
    func similarity() {
        #expect(TranscriptMerger.similarity("den Release verschieben", "Wir wollen den Release verschieben") == 1)
        #expect(TranscriptMerger.similarity("Kaffee", "Release verschieben") == 0)
    }
}
