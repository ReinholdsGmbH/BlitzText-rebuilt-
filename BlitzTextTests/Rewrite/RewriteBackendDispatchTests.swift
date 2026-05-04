@testable import BlitzText
import XCTest

/// Wave-1-Dispatch-Matrix: 2 Modes × 2 Backends + Production-Pfad-Verifikation.
///
/// Pinnt Plan-Verhalten: `ModeProcessor.runPipeline` wählt im
/// `.blitztextPlus, .blitztextRant`-Branch den Rewriter via
/// `settings.rewriteBackend(for: mode)`:
///   - `.appleFoundation` → `foundationRewriter`-Slot
///   - `.openAI`          → `rewriter`-Slot (bestehend)
///
/// Bei `.blitztextRant + .appleFoundation` versucht `runPipeline` zusätzlich
/// einen `as? AppleFoundationRewriteClient`-Cast für den Guided-Pfad
/// (`rewriteGuided`); Test-Fall mit `FakeRewriter` schlägt der Cast fehl
/// (Plain-Fallback aktiv) — der Production-Pfad-Test (Test 5) injiziert einen
/// echten `AppleFoundationRewriteClient` und verifiziert, dass `respondGuided`
/// tatsächlich gerufen wird (WARNING 4).
@MainActor
final class RewriteBackendDispatchTests: XCTestCase {

    // MARK: - Fixture-WAV (analog PipelineErrorPathTests)

    private func makeFixtureURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("blitztext-dispatch-fixture-\(UUID().uuidString).wav")
        var bytes: [UInt8] = Array(repeating: 0, count: 44)
        bytes[0] = 0x52; bytes[1] = 0x49; bytes[2] = 0x46; bytes[3] = 0x46
        bytes[8] = 0x57; bytes[9] = 0x41; bytes[10] = 0x56; bytes[11] = 0x45
        try Data(bytes).write(to: url)
        return url
    }

    // MARK: - DI-Helper (zwei Rewriter-Slots)

    private func makeProcessor(
        rewriteBackend: RewriteBackend,
        forMode mode: Mode,
        openAIRewriter: RewriteService,
        foundationRewriter: RewriteService,
        transcriber: TranscriptionService,
        recorder: RecorderProtocol
    ) -> ModeProcessor {
        let provider = FakeFoundationAvailabilityProvider(state: .available)
        let settings = SettingsStore(availabilityProvider: provider)
        // BLOCKER 2 / T-08-02-06: Override IMMER setzen (auch leerer String) damit
        // applyAutoFallbackIfNeeded auf Dev-Maschinen mit echtem Keychain-Key nicht
        // fälschlich greift. Wir setzen einen test-API-Key, weil Settings.backend
        // = .openAI in der Pipeline ohne Key nicht erfolgreich initialisieren würde
        // (Transcriber ist hier zwar Fake, aber consistent).
        settings._testApiKeyOverride = "sk-test-123"
        settings.setRewriteBackend(rewriteBackend, for: mode)
        settings.backend = .openAI  // Transcription-Backend orthogonal zu Rewrite-Backend
        return ModeProcessor(
            settings: settings,
            history: HistoryStore(),
            modelManager: LocalModelManager(),
            diarizerManager: DiarizerModelManager(loader: FakeDiarizerLoader()),
            openAITranscriber: transcriber,
            localTranscriber: nil,
            parakeetTranscriber: nil,
            rewriter: openAIRewriter,
            foundationRewriter: foundationRewriter,
            recorder: recorder
        )
    }

    // MARK: - 4-Pfad-Matrix: Plus×Foundation, Plus×OpenAI, Rant×Foundation, Rant×OpenAI

    func test_blitztextPlus_appleFoundation_dispatchesToFoundationRewriter() async throws {
        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let foundation = FakeRewriter(.success("FOUNDATION_OUT"))
        let transcriber = FakeTranscriptionService(.success("hallo"))
        let recorder = FakeAudioRecorder(fixtureURL: try makeFixtureURL())

        let mp = makeProcessor(
            rewriteBackend: .appleFoundation, forMode: .blitztextPlus,
            openAIRewriter: openAI, foundationRewriter: foundation,
            transcriber: transcriber, recorder: recorder
        )
        await mp.start(mode: .blitztextPlus)
        await mp.stop()

        XCTAssertEqual(foundation.callCount, 1, "Plus + Foundation → foundationRewriter")
        XCTAssertEqual(openAI.callCount, 0, "OpenAI darf NICHT gerufen werden")
    }

    func test_blitztextPlus_openAI_dispatchesToOpenAIRewriter() async throws {
        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let foundation = FakeRewriter(.success("FOUNDATION_OUT"))
        let transcriber = FakeTranscriptionService(.success("hallo"))
        let recorder = FakeAudioRecorder(fixtureURL: try makeFixtureURL())

        let mp = makeProcessor(
            rewriteBackend: .openAI, forMode: .blitztextPlus,
            openAIRewriter: openAI, foundationRewriter: foundation,
            transcriber: transcriber, recorder: recorder
        )
        await mp.start(mode: .blitztextPlus)
        await mp.stop()

        XCTAssertEqual(openAI.callCount, 1, "Plus + OpenAI → bestehender rewriter-Slot")
        XCTAssertEqual(foundation.callCount, 0)
    }

    func test_blitztextRant_appleFoundation_dispatchesToFoundationRewriter() async throws {
        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let foundation = FakeRewriter(.success("FOUNDATION_OUT"))
        let transcriber = FakeTranscriptionService(.success("ich bin sauer"))
        let recorder = FakeAudioRecorder(fixtureURL: try makeFixtureURL())

        let mp = makeProcessor(
            rewriteBackend: .appleFoundation, forMode: .blitztextRant,
            openAIRewriter: openAI, foundationRewriter: foundation,
            transcriber: transcriber, recorder: recorder
        )
        await mp.start(mode: .blitztextRant)
        await mp.stop()

        // Mit FakeRewriter (kein AppleFoundationRewriteClient) schlägt der
        // `as? AppleFoundationRewriteClient`-Cast fehl, der Plain-Fallback
        // `rewrite(...)` greift — foundation.callCount muss 1 sein.
        // Production-Pfad mit echtem Client wird in Test 5 verifiziert.
        XCTAssertEqual(foundation.callCount, 1, "Rant + Foundation → foundationRewriter (Plain-Fallback bei Test-Fake)")
        XCTAssertEqual(openAI.callCount, 0)
    }

    func test_blitztextRant_openAI_dispatchesToOpenAIRewriter() async throws {
        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let foundation = FakeRewriter(.success("FOUNDATION_OUT"))
        let transcriber = FakeTranscriptionService(.success("ich bin sauer"))
        let recorder = FakeAudioRecorder(fixtureURL: try makeFixtureURL())

        let mp = makeProcessor(
            rewriteBackend: .openAI, forMode: .blitztextRant,
            openAIRewriter: openAI, foundationRewriter: foundation,
            transcriber: transcriber, recorder: recorder
        )
        await mp.start(mode: .blitztextRant)
        await mp.stop()

        XCTAssertEqual(openAI.callCount, 1, "Rant + OpenAI → rewriter-Slot")
        XCTAssertEqual(foundation.callCount, 0)
    }

    /// WARNING-4-Verifikation: Production-Pfad mit echtem `AppleFoundationRewriteClient`.
    /// Stellt sicher, dass der `as? AppleFoundationRewriteClient`-Cast in
    /// `ModeProcessor.runPipeline` greift und `rewriteGuided` tatsächlich
    /// gerufen wird (NICHT Plain-Fallback). Schließt die Lücke zwischen
    /// Test 3 (FakeRewriter, Cast schlägt fehl) und Production.
    func test_blitztextRant_appleFoundation_realClient_dispatchesToRespondGuided() async throws {
        let availability = FakeFoundationAvailabilityProvider(state: .available)
        let inferring = FakeLanguageModelInferring()
        inferring.guidedResponse = .success(DeescalatedOutput(neutralText: "ruhig"))
        let foundationClient = AppleFoundationRewriteClient(
            availabilityProvider: availability,
            inferring: inferring
        )

        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let transcriber = FakeTranscriptionService(.success("ich bin sauer"))
        let recorder = FakeAudioRecorder(fixtureURL: try makeFixtureURL())

        let provider = FakeFoundationAvailabilityProvider(state: .available)
        let settings = SettingsStore(availabilityProvider: provider)
        settings._testApiKeyOverride = "sk-test-123"
        settings.setRewriteBackend(.appleFoundation, for: .blitztextRant)
        settings.backend = .openAI
        let mp = ModeProcessor(
            settings: settings,
            history: HistoryStore(),
            modelManager: LocalModelManager(),
            diarizerManager: DiarizerModelManager(loader: FakeDiarizerLoader()),
            openAITranscriber: transcriber,
            localTranscriber: nil,
            parakeetTranscriber: nil,
            rewriter: openAI,
            foundationRewriter: foundationClient,    // ← echter Client, nicht Fake
            recorder: recorder
        )
        await mp.start(mode: .blitztextRant)
        await mp.stop()

        XCTAssertEqual(inferring.respondGuidedCallCount, 1, "Production-Pfad: rewriteGuided MUSS gerufen werden")
        XCTAssertEqual(inferring.respondCallCount, 0, "Plain-respond darf NICHT gerufen werden bei Rant+Foundation")
        XCTAssertEqual(openAI.callCount, 0)
    }
}
