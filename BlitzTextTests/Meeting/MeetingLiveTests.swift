import AVFoundation
import Foundation
import Testing
@testable import BlitzText

/// Ende-zu-Ende mit echten Modellen: Parakeet lokal, Ollama lokal.
///
/// Läuft nur auf Anforderung, weil es Modelle, eine laufende Ollama-Instanz und echte
/// Sprachdateien braucht:
///   TEST_RUNNER_BLITZTEXT_LIVE_DIR=<Ordner mit me.wav und other.wav> xcodebuild test …
/// Beide Dateien: 16 kHz mono, je ein gesprochener Satz.
@MainActor
struct MeetingLiveTests {

    nonisolated static let liveDir = ProcessInfo.processInfo.environment["BLITZTEXT_LIVE_DIR"]

    @Test("Echte Sprache: zwei Spuren, Parakeet und Ollama ergeben ein Protokoll",
          .enabled(if: liveDir != nil), .timeLimit(.minutes(10)))
    func realModels() async throws {
        let dir = URL(fileURLWithPath: try #require(Self.liveDir))
        let micTrack = try place(dir.appendingPathComponent("me.wav"), at: 1, total: 14)
        let otherTrack = try place(dir.appendingPathComponent("other.wav"), at: 7.5, total: 14)

        let settings = SettingsStore()
        let parakeet = ParakeetClient(settings: settings, diarizerManager: DiarizerModelManager())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-live-\(UUID())")

        let recorder = MeetingRecorder(
            microphone: FakeAudioRecorder(fixtureURL: micTrack),
            systemAudio: FakeSystemAudioTap(fixtureURL: otherTrack),
            detector: MeetingDetector(),
            processList: FakeAudioProcessList()
        )
        let controller = MeetingController(
            recorder: recorder,
            archive: MeetingArchive(root: root),
            makeTranscriber: { PlainParakeetTranscriber(client: parakeet) },
            makeSummarizer: { settings.makeMeetingSummarizer() },
            language: { "de" }
        )

        controller.start()
        controller.stop()
        for _ in 0..<2400 {
            if case .finished = controller.phase { break }
            if case .failed = controller.phase { break }
            try await Task.sleep(for: .milliseconds(250))
        }

        guard case .finished(let folder, let warning, _) = controller.phase else {
            Issue.record("Phase: \(controller.phase)"); return
        }
        let url = folder.appendingPathComponent(MeetingArchive.protocolFile)
        let markdown = try String(contentsOf: url, encoding: .utf8)
        print("LIVE-PROTOKOLL \(url.path)\n\(markdown)")
        #expect(warning == nil)
        #expect(markdown.contains("Ich:**"))
        #expect(markdown.contains("Andere:**"))
        #expect(markdown.lowercased().contains("donnerstag"))
        #expect(markdown.contains("### Aufgaben"))
    }

    @Test("Echte Modelllisten aller drei Anbieter lassen sich laden",
          .enabled(if: liveDir != nil), arguments: SummaryProvider.allCases)
    func realCatalogs(provider: SummaryProvider) async throws {
        let models = try await ModelCatalog.fetch(provider, ollamaBaseURL: "http://localhost:11434")
        print("KATALOG \(provider.rawValue): \(models.count) Modelle, Standard enthalten: \(models.contains { $0.id == provider.defaultModel })")
        #expect(!models.isEmpty)
        if !provider.isLocal { #expect(models.contains { $0.id == provider.defaultModel }) }
    }

    /// Legt eine Sprachdatei mit Stille davor und danach in eine Spur fester Länge.
    private func place(_ source: URL, at offset: TimeInterval, total: TimeInterval) throws -> URL {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let speech = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length))!
        try input.read(into: speech)

        let frames = AVAudioFrameCount(total * format.sampleRate)
        let track = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        track.frameLength = frames
        let out = track.floatChannelData![0], src = speech.floatChannelData![0]
        for i in 0..<Int(frames) { out[i] = 0 }
        let start = Int(offset * format.sampleRate)
        for i in 0..<Int(speech.frameLength) where start + i < Int(frames) { out[start + i] = src[i] }

        let url = TestAudio.tempURL()
        let file = try AVAudioFile(forWriting: url, settings: input.fileFormat.settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        try file.write(from: track)
        return url
    }
}

@MainActor
struct LiveTranscriberRealTests {
    @Test("Live-Transkript mit echtem Parakeet aus dem Puffer", .enabled(if: MeetingLiveTests.liveDir != nil), .timeLimit(.minutes(5)))
    func realLive() async throws {
        let dir = URL(fileURLWithPath: try #require(MeetingLiveTests.liveDir))
        let file = try AVAudioFile(forReading: dir.appendingPathComponent("me.wav"))
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: pcm)
        let buffer = LiveAudioBuffer()
        buffer.append(pcm)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "blitztext-livet-\(UUID())")!)
        let live = LiveTranscriber()
        live.start(tracks: [(buffer, .me)], transcriber: PlainParakeetTranscriber(client: ParakeetClient(settings: settings, diarizerManager: DiarizerModelManager())))
        for _ in 0..<120 where live.lines.isEmpty { try await Task.sleep(for: .milliseconds(500)) }
        live.stop()
        print("LIVE-VORSCHAU: \(live.lines.map(\.text))")
        #expect(live.lines.first?.text.lowercased().contains("donnerstag") == true)
    }
}
