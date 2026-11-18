import Foundation
import Testing
@testable import BlitzText

/// Abgleich an einer Kopie eines echten Meetings mit einer Kopie der Stimmprofile.
/// Läuft nur mit TEST_RUNNER_BLITZTEXT_REMATCH_ROOT und …_REMATCH_PROFILES.
@MainActor
struct SpeakerRematchLiveTests {
    nonisolated static let env = ProcessInfo.processInfo.environment

    @Test("Echtes Meeting neu abgleichen", .enabled(if: env["BLITZTEXT_REMATCH_ROOT"] != nil), .timeLimit(.minutes(10)))
    func rematchesRealMeeting() async throws {
        let archive = MeetingArchive(root: URL(fileURLWithPath: try #require(Self.env["BLITZTEXT_REMATCH_ROOT"])))
        let store = SpeakerProfileStore(url: URL(fileURLWithPath: try #require(Self.env["BLITZTEXT_REMATCH_PROFILES"])))
        let diarizer = FluidMeetingDiarizer(modelManager: DiarizerModelManager(), store: store, threshold: { 0.7 })
        let library = MeetingLibrary(archive: archive, diarizer: diarizer, makeSummarizer: { FakeSummarizer(result: .success("")) })
        library.reload()
        let entry = try #require(library.entries.first)
        let before = entry.document
        await library.rematchSpeakers(in: entry.folder)
        let after = try #require(archive.load(folder: entry.folder))
        print("REMATCH: Stimmen \(before.speakerIDs.count) → \(after.speakerIDs.count), offen \(before.unconfirmedSpeakerIDs.count) → \(after.unconfirmedSpeakerIDs.count), Namen \(Set(after.speakerNames.values).sorted())")
        #expect(after.lines.count == before.lines.count)
        #expect(after.speakerIDs.count <= before.speakerIDs.count)
    }
}
