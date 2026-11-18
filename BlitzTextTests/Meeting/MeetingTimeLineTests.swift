import Foundation
import Testing
@testable import BlitzText

struct MeetingTimeLineTests {

    /// 18.11.2026 08:30 Berliner Zeit (MEZ, UTC+1).
    private let start = Date(timeIntervalSince1970: 1794987000)

    private func document(duration: TimeInterval, endedAt: Date? = nil) -> MeetingDocument {
        var doc = MeetingDocument(startedAt: start, duration: duration, sourceNames: ["Teams"], lines: [],
                                  summary: "- Punkt", notes: [])
        doc.endedAt = endedAt
        return doc
    }

    @Test("Zeitzeile mit Beginn und Ende am selben Tag")
    func sameDay() {
        #expect(MeetingMarkdown.timeLine(for: document(duration: 42 * 60)) == "Zeit: 18.11.2026, 08:30 bis 09:12 Uhr")
    }

    @Test("Über Mitternacht stehen beide Daten")
    func overMidnight() {
        let doc = document(duration: 16 * 3600)
        #expect(MeetingMarkdown.timeLine(for: doc) == "Zeit: 18.11.2026, 08:30 bis 19.11.2026, 00:30 Uhr")
    }

    @Test("Gesetztes Ende geht vor Beginn plus Dauer")
    func explicitEnd() {
        let doc = document(duration: 600, endedAt: start.addingTimeInterval(3600))
        #expect(MeetingMarkdown.timeLine(for: doc).hasSuffix("08:30 bis 09:30 Uhr"))
    }

    @Test("Protokoll und Kopie tragen Beginn und Ende")
    func protocolAndCopy() {
        let doc = document(duration: 42 * 60)
        let protocolText = MeetingMarkdown.render(doc)
        #expect(protocolText.contains("- Beginn: 18.11.2026, 08:30 Uhr"))
        #expect(protocolText.contains("- Ende: 18.11.2026, 09:12 Uhr"))
        #expect(protocolText.contains("## Protokoll\n\nZeit: 18.11.2026, 08:30 bis 09:12 Uhr\n\n- Punkt"))
        #expect(MeetingMarkdown.summaryWithTime(doc) == "Zeit: 18.11.2026, 08:30 bis 09:12 Uhr\n\n- Punkt")
        #expect(VaultExporter.markdown(for: doc, area: "kunde").contains("## Zusammenfassung\n\nZeit: 18.11.2026, 08:30 bis 09:12 Uhr"))
    }
}
