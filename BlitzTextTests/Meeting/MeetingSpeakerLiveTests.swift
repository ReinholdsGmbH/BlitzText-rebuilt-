import Foundation
import Testing
@testable import BlitzText

/// Sprechererkennung mit echten Aufnahmen (z. B. aus MacWhisper), komplett lokal.
/// Läuft nur mit TEST_RUNNER_BLITZTEXT_SPEAKER_A_MIC, …_B_MIC, …_B_APP, …_C_MIXED.
/// Nutzt einen Wegwerf-Profilspeicher, die echte speakers.json bleibt unberührt.
@MainActor
struct MeetingSpeakerLiveTests {

    nonisolated static let env = ProcessInfo.processInfo.environment
    nonisolated static let enabled = env["BLITZTEXT_SPEAKER_A_MIC"] != nil

    private func converted(_ key: String) throws -> URL {
        let target = TestAudio.tempURL()
        try MeetingImport.convert(URL(fileURLWithPath: try #require(Self.env[key])), to: target)
        return target
    }

    /// Anteil der Sprechzeit, den der Name „Thomas“ in einer Spur bekommt.
    private func share(of name: String, in result: MeetingDiarization) -> Double {
        let total = result.segments.reduce(0) { $0 + $1.end - $1.start }
        let named = result.segments.filter { result.knownNames[$0.speakerID] == name }.reduce(0) { $0 + $1.end - $1.start }
        return total > 0 ? named / total : 0
    }

    @Test("Profil aus Mikrofon A erkennt dieselbe Stimme in B und im Mitschnitt C",
          .enabled(if: enabled), .timeLimit(.minutes(20)))
    func learnsAndRecognizes() async throws {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-live-speakers-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let store = SpeakerProfileStore(url: storeURL)
        let diarizer = FluidMeetingDiarizer(modelManager: DiarizerModelManager(), store: store, threshold: { 0.7 })

        // 1. Lernen aus Mikrofon A.
        let micA = try converted("BLITZTEXT_SPEAKER_A_MIC")
        let spansA = SpeechSegmenter().spans(frameRMS: try MeetingTranscriber.frameRMS(of: micA, frameDuration: 0.03))
        try await diarizer.learnProfile(name: "Thomas", from: micA, spans: spansA)
        #expect(store.loadSpeakers().filter(\.isPermanent).map(\.name) == ["Thomas"])

        // 2. Positiv: Mikrofon B.
        let micB = try converted("BLITZTEXT_SPEAKER_B_MIC")
        let resultMic = try await diarizer.diarize(track: micB)
        let mineShare = share(of: "Thomas", in: resultMic)

        // 3. Gegenprobe: Gegenseite B.
        let appB = try converted("BLITZTEXT_SPEAKER_B_APP")
        let resultApp = try await diarizer.diarize(track: appB)
        let foreignShare = share(of: "Thomas", in: resultApp)
        print("LIVE-SPRECHER Mikro B: \(Set(resultMic.segments.map(\.speakerID)).count) Stimmen, Anteil Thomas \(Int(mineShare * 100)) %")
        print("LIVE-SPRECHER Gegenseite B: \(Set(resultApp.segments.map(\.speakerID)).count) Stimmen, Anteil Thomas \(Int(foreignShare * 100)) %")
        #expect(mineShare > 0.6)
        #expect(foreignShare < 0.2)

        // 4. Ganzer Durchlauf mit der Mischspur C.
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "blitztext-live-\(UUID())")!)
        settings.ollamaModel = "phi4-mini"
        let parakeet = ParakeetClient(settings: settings, diarizerManager: DiarizerModelManager())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-live-archive-\(UUID())")
        let controller = MeetingController(
            recorder: MeetingRecorder(microphone: FakeAudioRecorder(fixtureURL: micA),
                                      systemAudio: FakeSystemAudioTap(fixtureURL: micA),
                                      detector: MeetingDetector(), processList: FakeAudioProcessList()),
            archive: MeetingArchive(root: root),
            makeTranscriber: { PlainParakeetTranscriber(client: parakeet) },
            makeSummarizer: { settings.makeMeetingSummarizer() },
            diarizer: diarizer,
            language: { "de" }
        )
        let started = Date()
        controller.importFiles([URL(fileURLWithPath: try #require(Self.env["BLITZTEXT_SPEAKER_C_MIXED"]))])
        for _ in 0..<4800 {
            if case .finished = controller.phase { break }
            if case .failed = controller.phase { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard case .finished(let folder, let warning, let unnamed) = controller.phase else {
            Issue.record("Phase: \(controller.phase)"); return
        }
        let doc = try #require(MeetingArchive(root: root).load(folder: folder))
        let people = doc.speakerIDs.map { "\(doc.label(forSpeaker: $0)) \(Int(doc.speakingTime(of: $0))) s" }
        print("LIVE-SPRECHER Mischspur C: \(String(format: "%.0f", Date().timeIntervalSince(started))) s Verarbeitung für \(Int(doc.duration)) s Audio, \(doc.lines.count) Beiträge, unbenannt \(unnamed), Warnung \(warning ?? "-")")
        print("LIVE-SPRECHER Teilnehmende: \(people.joined(separator: " | "))")
        print("LIVE-SPRECHER Protokoll: \(folder.path)")
        #expect(doc.speakerNames.values.contains("Thomas"))
        #expect(doc.summary != nil)
    }
}
