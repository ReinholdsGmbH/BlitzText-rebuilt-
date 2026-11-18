import Testing
import Foundation
@testable import BlitzText

struct MeetingTranscriberTests {

    @Test("Zwei Spuren ergeben verschränkte Beiträge mit Startzeiten")
    func transcribesBothTracks() async throws {
        let mic = try TestAudio.wav(duration: 12, bursts: [1...3], at: TestAudio.tempURL())
        let other = try TestAudio.wav(duration: 12, bursts: [5...7, 9...11], at: TestAudio.tempURL())
        defer { [mic, other].forEach { try? FileManager.default.removeItem(at: $0) } }

        let fake = SequenceTranscriber(["Mein Beitrag", "Antwort eins", "Antwort zwei"])
        let lines = try await MeetingTranscriber(transcriber: fake, language: "de").transcribe(
            [.init(url: mic, speaker: .me), .init(url: other, speaker: .others)],
            progress: { _, _ in }
        )

        #expect(fake.callCount == 3)
        #expect(lines.map(\.speaker) == [.me, .others, .others])
        #expect(abs(lines[0].start - 0.8) < 0.1)
        #expect(abs(lines[1].start - 4.8) < 0.1)
        #expect(abs(lines[2].start - 8.8) < 0.1)
    }

    @Test("Scheitern alle Abschnitte, kommt ein Fehler statt eines leeren Protokolls")
    func allFailuresThrow() async throws {
        let mic = try TestAudio.wav(duration: 5, bursts: [1...3], at: TestAudio.tempURL())
        defer { try? FileManager.default.removeItem(at: mic) }
        let fake = SequenceTranscriber([])
        fake.error = TranscriptionError.backendNotAvailable

        await #expect(throws: MeetingTranscriber.TranscriberError.self) {
            _ = try await MeetingTranscriber(transcriber: fake, language: nil)
                .transcribe([.init(url: mic, speaker: .me)], progress: { _, _ in })
        }
    }
}

struct MeetingMarkdownTests {

    @Test("Zeitformat", arguments: [(0.0, false, "0:00"), (75.4, false, "1:15"), (3725, false, "01:02:05"), (5, true, "00:00:05")])
    func clock(seconds: Double, hours: Bool, expected: String) {
        #expect(MeetingMarkdown.clock(seconds, alwaysHours: hours) == expected)
    }

    @Test("Protokoll enthält Zusammenfassung, Hinweise und Transkript")
    func rendersDocument() {
        let doc = MeetingDocument(
            startedAt: Date(timeIntervalSince1970: 0),
            duration: 125,
            sourceNames: ["Microsoft Teams"],
            lines: [TranscriptLine(speaker: .others, start: 3, end: 6, text: "Hallo.")],
            summary: "### Zusammenfassung\n- Begrüßung",
            notes: ["Die Gegenseite kam stumm an."]
        )
        let md = MeetingMarkdown.render(doc)
        #expect(md.hasPrefix("# 01.01.70_01:00_Microsoft Teams-Meeting"))
        #expect(md.contains("- Dauer: 2:05"))
        #expect(md.contains("- Hinweis: Die Gegenseite kam stumm an."))
        #expect(md.contains("### Zusammenfassung\n- Begrüßung"))
        #expect(md.contains("**[00:00:03] Andere:** Hallo."))
    }

    @Test("Ordnername ohne Pfadtrenner")
    func folderNameIsSafe() {
        let name = MeetingArchive.folderName(startedAt: Date(), sourceName: "Zoom/Web: Test")
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }

    @Test("Lange Transkripte werden an Zeilengrenzen geteilt")
    func summarizerChunks() {
        let text = (1...10).map { "Zeile \($0) " + String(repeating: "x", count: 20) }.joined(separator: "\n")
        let chunks = MeetingSummarizer.chunks(of: text, limit: 100)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 100 })
        #expect(chunks.joined(separator: "\n") == text)
    }
}

@MainActor
struct MeetingControllerTests {

    private func makeController(
        root: URL,
        transcriber: SequenceTranscriber,
        summary: Result<String, Error>
    ) throws -> (MeetingController, FakeAudioRecorder) {
        let micURL = try TestAudio.wav(duration: 6, bursts: [1...3], at: TestAudio.tempURL())
        let tapURL = try TestAudio.wav(duration: 6, bursts: [4...5.5], at: TestAudio.tempURL())
        let mic = FakeAudioRecorder(fixtureURL: micURL)
        let recorder = MeetingRecorder(
            microphone: mic,
            systemAudio: FakeSystemAudioTap(fixtureURL: tapURL),
            detector: MeetingDetector(),
            processList: FakeAudioProcessList()
        )
        let controller = MeetingController(
            recorder: recorder,
            archive: MeetingArchive(root: root),
            makeTranscriber: { transcriber },
            makeSummarizer: { FakeSummarizer(result: summary) },
            language: { "de" }
        )
        return (controller, mic)
    }

    private func waitUntilDone(_ controller: MeetingController) async {
        for _ in 0..<200 {
            if case .finished = controller.phase { return }
            if case .failed = controller.phase { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test("Stopp schreibt Protokoll mit Zusammenfassung und legt beide Spuren ab")
    func fullRun() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (controller, _) = try makeController(
            root: root,
            transcriber: SequenceTranscriber(["Ich fange an", "Die anderen antworten"]),
            summary: .success("### Zusammenfassung\n- Test")
        )

        controller.start()
        #expect(controller.isRecording)
        controller.stop()
        await waitUntilDone(controller)

        guard case .finished(let folder, let warning, _) = controller.phase else {
            Issue.record("Phase: \(controller.phase)"); return
        }
        #expect(warning == nil)
        let url = folder.appendingPathComponent(MeetingArchive.protocolFile)
        let md = try String(contentsOf: url, encoding: .utf8)
        #expect(md.contains("- Test"))
        #expect(md.contains("Ich:** Ich fange an"))
        #expect(md.contains("Andere:** Die anderen antworten"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("mikrofon.wav").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("gegenseite.wav").path))
    }

    @Test("Fällt Ollama aus, bleibt das Transkript erhalten und es gibt einen Hinweis")
    func summaryFailureKeepsTranscript() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (controller, _) = try makeController(
            root: root,
            transcriber: SequenceTranscriber(["Ich fange an", "Antwort"]),
            summary: .failure(OllamaError.notRunning)
        )

        controller.start()
        controller.stop()
        await waitUntilDone(controller)

        guard case .finished(let folder, let warning, _) = controller.phase else {
            Issue.record("Phase: \(controller.phase)"); return
        }
        #expect(warning?.contains("Zusammenfassung fehlgeschlagen") == true)
        let md = try String(contentsOf: folder.appendingPathComponent(MeetingArchive.protocolFile), encoding: .utf8)
        #expect(md.contains("Ich fange an"))
        #expect(md.contains("Keine Zusammenfassung"))
    }
}

struct SummaryProviderTests {

    @Test("Cloud-Anfrage trägt Schlüssel, Modell und beide Prompts im OpenAI-Format")
    func openAICompatibleRequest() throws {
        let chat = OpenAICompatibleChat(provider: .requesty, apiKey: "sk-test", model: "bedrock/claude-haiku-5-5@eu-central-1")
        let request = try chat.makeRequest(system: "SYS", user: "USER")
        #expect(request.url?.absoluteString == "https://router.requesty.ai/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["model"] as? String == "bedrock/claude-haiku-5-5@eu-central-1")
        let messages = body?["messages"] as? [[String: String]]
        #expect(messages?.map { $0["role"] } == ["system", "user"])
        #expect(messages?.last?["content"] == "USER")
    }

    @Test("Ohne Schlüssel geht keine Anfrage raus")
    func missingKeyThrows() {
        #expect(throws: SummaryError.self) {
            _ = try OpenAICompatibleChat(provider: .openRouter, apiKey: "", model: "x").makeRequest(system: "", user: "")
        }
    }

    @Test("Unbekannter Anbieter aus späterem Build fällt auf lokal zurück")
    func unknownProviderIsLocal() throws {
        let decoded = try JSONDecoder().decode([SummaryProvider].self, from: Data(#"["mistralCloud"]"#.utf8))
        #expect(decoded == [.ollama])
    }

    @Test("Modelllisten: Requesty nur Chat-Modelle, OpenRouter mit Namen, Ollama aus tags")
    func parsesCatalogs() throws {
        let requesty = Data(#"{"data":[{"id":"b/model","api":"chat"},{"id":"a/embed","api":"embedding"}]}"#.utf8)
        #expect(try ModelCatalog.parse(requesty, provider: .requesty).map(\.id) == ["b/model"])

        let openRouter = Data(#"{"data":[{"id":"z/one","name":"Z: One"},{"id":"a/two","name":"A: Two"}]}"#.utf8)
        let parsed = try ModelCatalog.parse(openRouter, provider: .openRouter)
        #expect(parsed.map(\.id) == ["a/two", "z/one"])
        #expect(parsed.first?.name == "A: Two")

        let ollama = Data(#"{"models":[{"name":"phi4-mini:latest"}]}"#.utf8)
        #expect(try ModelCatalog.parse(ollama, provider: .ollama).map(\.id) == ["phi4-mini:latest"])
    }

    @Test("Einstellungen bauen den Zusammenfasser des gewählten Anbieters")
    @MainActor
    func settingsPickProvider() throws {
        let defaults = try #require(UserDefaults(suiteName: "blitztext-test-\(UUID())"))
        let settings = SettingsStore(defaults: defaults)
        settings.meetingSummaryProvider = .openRouter
        settings.openRouterModel = "anthropic/claude-haiku-5.5"
        let summarizer = try #require(settings.makeMeetingSummarizer() as? MeetingSummarizer)
        let chat = try #require(summarizer.chat as? OpenAICompatibleChat)
        #expect(chat.provider == .openRouter)
        #expect(chat.model == "anthropic/claude-haiku-5.5")

        settings.meetingSummaryProvider = .ollama
        let local = try #require(settings.makeMeetingSummarizer() as? MeetingSummarizer)
        #expect(local.chat is OllamaNativeChat)
    }
}

struct MeetingEndWatchTests {

    @Test("Vorschlag erst nach der Schonfrist, nicht bei kurzer Lücke")
    func graceAndShortGap() {
        var watch = MeetingEndWatch()
        let t0 = Date()
        let r1 = watch.update(appActive: true, at: t0)
        #expect(!r1)
        let r2 = watch.update(appActive: false, at: t0.addingTimeInterval(5))
        #expect(!r2)
        let r3 = watch.update(appActive: true, at: t0.addingTimeInterval(10))
        #expect(!r3)
        let r4 = watch.update(appActive: false, at: t0.addingTimeInterval(15))
        #expect(!r4)
        let r5 = watch.update(appActive: false, at: t0.addingTimeInterval(25))
        #expect(!r5)
        let r6 = watch.update(appActive: false, at: t0.addingTimeInterval(30))
        #expect(r6)
    }

    @Test("„Weiter“ unterdrückt den Vorschlag, bis die App wieder aktiv war")
    func dismissUntilActiveAgain() {
        var watch = MeetingEndWatch()
        let t0 = Date()
        _ = watch.update(appActive: false, at: t0)
        let r7 = watch.update(appActive: false, at: t0.addingTimeInterval(20))
        #expect(r7)
        watch.dismiss()
        let r8 = watch.update(appActive: false, at: t0.addingTimeInterval(60))
        #expect(!r8)
        _ = watch.update(appActive: true, at: t0.addingTimeInterval(70))
        _ = watch.update(appActive: false, at: t0.addingTimeInterval(80))
        let r9 = watch.update(appActive: false, at: t0.addingTimeInterval(96))
        #expect(r9)
    }
}

struct SpeakerSampleTests {
    @Test("Diagnose sammelt nur kachelähnliche Beschriftungen")
    func candidates() {
        #expect(ActiveSpeakerPoller.isCandidate("Anna Müller, Mikrofon stummgeschaltet"))
        #expect(ActiveSpeakerPoller.isCandidate("Video von Bernd"))
        #expect(!ActiveSpeakerPoller.isCandidate("Chat"))
        #expect(!ActiveSpeakerPoller.isCandidate(String(repeating: "Video ", count: 40)))
    }
}

struct TeamsTileLabelTests {
    @Test("Name aus Teams-Kacheln, eigene Kachel ausgenommen", arguments: [
        ("Echo, Kontextmenü ist verfügbar", "Echo"),
        ("Max Muster, Kontextmenü ist verfügbar", "Max Muster"),
        ("Muster, Max (ABC_EXTERN), Kontextmenü ist verfügbar", "Max Muster"),
        ("Video von mir selbst, Beispiel, Erika (ABC_EXTERN), Stummschaltung aufgehoben, Video ist ein, Frame ausfüllen, Hat Kontextmenü", nil),
        ("Mikrofon stummschalten", nil)
    ] as [(String, String?)])
    func tileNames(label: String, expected: String?) {
        #expect(TeamsTileLabel.name(in: label) == expected)
    }
}

struct MeetingVocabularyTests {
    @Test("Meeting-Transkription wendet das Wörterbuch an, ohne Treffer zu zählen")
    func correctingTranscriber() async throws {
        let base = SequenceTranscriber(["Wir besprechen das mit Kursbaar morgen"])
        let nouns = [ProperNoun(text: "Kursbar")]
        let transcriber = CorrectingTranscriber(base: base, vocabulary: { nouns })
        let text = try await transcriber.transcribe(audioURL: URL(fileURLWithPath: "/dev/null"), language: nil, prompt: nil)
        #expect(text.contains("Kursbar"))
        #expect(!text.contains("Kursbaar"))
    }
}
