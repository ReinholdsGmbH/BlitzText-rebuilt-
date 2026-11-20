import Foundation
import Testing
@testable import BlitzText

struct CallTitleTests {

    @Test("Erstes Feld des Call-Fensters ist der Besprechungsname", arguments: [
        ("TEST BlitzText | Firma AG | konto@firma.de", "TEST BlitzText"),
        ("Teams Sync Weekly | Firma AG | konto@firma.de", "Teams Sync Weekly"),
        ("Daily", "Daily")
    ])
    func readsName(title: String, expected: String) {
        #expect(TeamsCallControls.meetingName(fromWindowTitle: title) == expected)
    }

    @Test("Ansichten und Ad-hoc-Anrufe liefern keinen Namen", arguments: [
        "Chat | Firma AG | konto@firma.de",
        "Calendar | Firma AG | konto@firma.de",
        "Besprechung mit Anna Muster | Firma AG | konto@firma.de",
        "Meeting with Anna | Firma | x",
        " | Firma",
        ""
    ])
    func rejectsGeneric(title: String) {
        #expect(TeamsCallControls.meetingName(fromWindowTitle: title) == nil)
    }

    @Test("Besprechungsname ist Titel, solange kein eigener oder KI-Titel gesetzt ist")
    func titleFallsBackToCallTitle() {
        var doc = MeetingDocument(startedAt: Date(), duration: 60, sourceNames: ["Microsoft Teams"],
                                  lines: [], summary: nil, notes: [])
        doc.callTitle = "Team Daily"
        #expect(MeetingMarkdown.baseTitle(for: doc) == "Team Daily")
        #expect(doc.summaryInput.hasPrefix("Name der Besprechung laut Teams: Team Daily"))
        doc.aiTitle = "Eigener Titel"
        #expect(MeetingMarkdown.baseTitle(for: doc) == "Eigener Titel")
    }

    @Test("„Notizen neu erstellen“ hängt bei Serien das Thema an")
    @MainActor
    func summaryKeepsCallTitle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-calltitle-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = MeetingArchive(root: root)
        let folder = try archive.makeFolder(startedAt: Date(), sourceName: "Teams")
        var doc = MeetingDocument(startedAt: Date(), duration: 30, sourceNames: ["Microsoft Teams"],
                                  lines: [TranscriptLine(speaker: .others, start: 1, end: 3, text: "Hallo", speakerID: "1")],
                                  summary: nil, notes: [])
        doc.callTitle = "Team Daily"
        try archive.writeProtocol(doc, in: folder)
        let library = MeetingLibrary(archive: archive, diarizer: nil,
                                     makeSummarizer: { FakeSummarizer(result: .success("TITEL: KI-Titel\n### Zusammenfassung\n- A")) })
        library.reload()
        await library.regenerateSummary(in: folder)
        let saved = try #require(archive.load(folder: folder))
        #expect(MeetingMarkdown.baseTitle(for: saved) == "Team Daily: KI-Titel")
    }
}

struct SeriesTitleTests {

    @Test("Serie an Schlagwort oder an Wiederholung im Archiv", arguments: [
        ("Team Daily", ["Team Daily"], true),
        ("[Services] Weekly", ["[Services] Weekly"], true),
        ("Projektstart", ["Projektstart"], false),
        ("Projektstart", ["projektstart", "Projektstart"], true)
    ])
    func detectsSeries(call: String, titles: [String], expected: Bool) {
        #expect(MeetingDocument.isSeries(call, archiveTitles: titles) == expected)
    }

    @Test("Thema wird angehängt, ohne den Namen zu verdoppeln", arguments: [
        ("Releaseplanung", "Team Daily: Releaseplanung"),
        ("Team Daily – Releaseplanung", "Team Daily: Releaseplanung"),
        ("team daily", "Team Daily")
    ])
    func composes(topic: String, expected: String) {
        #expect(MeetingDocument.seriesTitle(call: "Team Daily", topic: topic) == expected)
    }

    private func doc(call: String?, chosen: Bool? = nil) -> MeetingDocument {
        var doc = MeetingDocument(startedAt: Date(), duration: 60, sourceNames: ["Microsoft Teams"],
                                  lines: [], summary: nil, notes: [])
        doc.callTitle = call
        doc.titleChosenByUser = chosen
        return doc
    }

    @Test("KI-Titel: Serie mit Thema, Einzeltermin behält Namen, eigener Titel bleibt")
    func appliesRules() {
        var series = doc(call: "Team Daily")
        series.applySummaryTitle("Releaseplanung", isSeries: true)
        #expect(MeetingMarkdown.baseTitle(for: series) == "Team Daily: Releaseplanung")

        var single = doc(call: "Projektstart")
        single.applySummaryTitle("Kickoff mit Kunde", isSeries: false)
        #expect(MeetingMarkdown.baseTitle(for: single) == "Projektstart")

        var none = doc(call: nil)
        none.applySummaryTitle("Kickoff", isSeries: false)
        #expect(MeetingMarkdown.baseTitle(for: none) == "Kickoff")

        var own = doc(call: "Team Daily", chosen: true)
        own.aiTitle = "Mein Titel"
        own.applySummaryTitle("Releaseplanung", isSeries: true)
        #expect(MeetingMarkdown.baseTitle(for: own) == "Mein Titel")
    }
}
