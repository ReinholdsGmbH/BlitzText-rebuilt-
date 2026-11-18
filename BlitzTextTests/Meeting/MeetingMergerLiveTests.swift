import Foundation
import Testing
@testable import BlitzText

/// Zusammenführen mit echten Meeting-Ordnern, nur auf Kopien. Läuft nur mit
/// TEST_RUNNER_BLITZTEXT_MERGE_ROOT (ein Ordner mit mindestens zwei Meeting-Ordnern).
struct MeetingMergerLiveTests {
    nonisolated static let root = ProcessInfo.processInfo.environment["BLITZTEXT_MERGE_ROOT"]

    @Test("Echte Meetings zusammenführen", .enabled(if: root != nil), .timeLimit(.minutes(5)))
    func mergesRealMeetings() throws {
        let archive = MeetingArchive(root: URL(fileURLWithPath: try #require(Self.root)))
        let parts = archive.loadAll().map { MeetingMerger.Part(folder: $0.folder, document: $0.document) }
        #expect(parts.count >= 2)
        let folder = try MeetingMerger.merge(parts, into: archive)
        let merged = try #require(archive.load(folder: folder))
        let expected = parts.map(\.document.lines.count).reduce(0, +)
        let audio = MeetingMerger.duration(of: folder.appendingPathComponent(MeetingArchive.othersTrackFile))
        print("MERGE: \(folder.lastPathComponent) Zeilen \(merged.lines.count)/\(expected) Dauer \(Int(merged.duration)) s Audio \(Int(audio)) s Sprecher \(merged.speakerIDs.count) Namen \(merged.speakerNames.count)")
        #expect(merged.lines.count == expected)
        #expect(abs(audio - merged.duration) < 1)
        // Hörprobe der letzten Zeile liegt innerhalb der Tonspur.
        #expect((merged.lines.last?.end ?? 0) <= audio + 1)
    }
}
