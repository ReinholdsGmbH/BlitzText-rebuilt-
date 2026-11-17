@testable import BlitzText
import XCTest

/// Dispatch-Matrix: 2 Modes × 2 Backends (openAI, ollama).
@MainActor
final class RewriteBackendDispatchTests: XCTestCase {

    private func makeFixtureURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("blitztext-dispatch-fixture-\(UUID().uuidString).wav")
        var bytes: [UInt8] = Array(repeating: 0, count: 44)
        bytes[0] = 0x52; bytes[1] = 0x49; bytes[2] = 0x46; bytes[3] = 0x46
        bytes[8] = 0x57; bytes[9] = 0x41; bytes[10] = 0x56; bytes[11] = 0x45
        try Data(bytes).write(to: url)
        return url
    }

    private func makeProcessor(
        rewriteBackend: RewriteBackend,
        forMode mode: Mode,
        openAIRewriter: RewriteService,
        ollamaRewriter: RewriteService,
        transcriber: TranscriptionService,
        recorder: RecorderProtocol
    ) -> ModeProcessor {
        let settings = SettingsStore()
        settings._testApiKeyOverride = "sk-test-123"
        settings.setRewriteBackend(rewriteBackend, for: mode)
        settings.backend = .openAI
        return ModeProcessor(
            settings: settings,
            history: HistoryStore(),
            modelManager: LocalModelManager(),
            diarizerManager: DiarizerModelManager(loader: FakeDiarizerLoader()),
            openAITranscriber: transcriber,
            rewriter: openAIRewriter,
            ollamaRewriter: ollamaRewriter,
            recorder: recorder
        )
    }

    func test_blitztextPlus_openAI_dispatchesToOpenAIRewriter() async throws {
        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let ollama = FakeRewriter(.success("OLLAMA_OUT"))
        let mp = makeProcessor(
            rewriteBackend: .openAI, forMode: .blitztextPlus,
            openAIRewriter: openAI, ollamaRewriter: ollama,
            transcriber: FakeTranscriptionService(.success("hallo")),
            recorder: FakeAudioRecorder(fixtureURL: try makeFixtureURL())
        )
        await mp.start(mode: .blitztextPlus)
        await mp.stop()
        XCTAssertEqual(openAI.callCount, 1)
        XCTAssertEqual(ollama.callCount, 0)
    }

    func test_blitztextPlus_ollama_dispatchesToOllamaRewriter() async throws {
        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let ollama = FakeRewriter(.success("OLLAMA_OUT"))
        let mp = makeProcessor(
            rewriteBackend: .ollama, forMode: .blitztextPlus,
            openAIRewriter: openAI, ollamaRewriter: ollama,
            transcriber: FakeTranscriptionService(.success("hallo")),
            recorder: FakeAudioRecorder(fixtureURL: try makeFixtureURL())
        )
        await mp.start(mode: .blitztextPlus)
        await mp.stop()
        XCTAssertEqual(ollama.callCount, 1)
        XCTAssertEqual(openAI.callCount, 0)
    }

    func test_blitztextRant_openAI_dispatchesToOpenAIRewriter() async throws {
        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let ollama = FakeRewriter(.success("OLLAMA_OUT"))
        let mp = makeProcessor(
            rewriteBackend: .openAI, forMode: .blitztextRant,
            openAIRewriter: openAI, ollamaRewriter: ollama,
            transcriber: FakeTranscriptionService(.success("ich bin sauer")),
            recorder: FakeAudioRecorder(fixtureURL: try makeFixtureURL())
        )
        await mp.start(mode: .blitztextRant)
        await mp.stop()
        XCTAssertEqual(openAI.callCount, 1)
        XCTAssertEqual(ollama.callCount, 0)
    }

    func test_blitztextRant_ollama_dispatchesToOllamaRewriter() async throws {
        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let ollama = FakeRewriter(.success("OLLAMA_OUT"))
        let mp = makeProcessor(
            rewriteBackend: .ollama, forMode: .blitztextRant,
            openAIRewriter: openAI, ollamaRewriter: ollama,
            transcriber: FakeTranscriptionService(.success("ich bin sauer")),
            recorder: FakeAudioRecorder(fixtureURL: try makeFixtureURL())
        )
        await mp.start(mode: .blitztextRant)
        await mp.stop()
        XCTAssertEqual(ollama.callCount, 1)
        XCTAssertEqual(openAI.callCount, 0)
    }

    /// OpenRouter/Requesty laufen über den Anbieter-Rewriter, nicht über OpenAI oder Ollama.
    func test_blitztextRant_requesty_dispatchesToProviderRewriter() async throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "blitztext-dispatch-\(UUID())")!)
        settings._testApiKeyOverride = "sk-test-123"
        settings.setRewriteBackend(.requesty, for: .blitztextRant)
        settings.backend = .openAI
        let openAI = FakeRewriter(.success("OPENAI_OUT"))
        let ollama = FakeRewriter(.success("OLLAMA_OUT"))
        let provider = FakeRewriter(.success("PROVIDER_OUT"))
        let mp = ModeProcessor(
            settings: settings,
            history: HistoryStore(),
            modelManager: LocalModelManager(),
            diarizerManager: DiarizerModelManager(loader: FakeDiarizerLoader()),
            openAITranscriber: FakeTranscriptionService(.success("hallo")),
            rewriter: openAI,
            ollamaRewriter: ollama,
            providerRewriter: provider,
            recorder: FakeAudioRecorder(fixtureURL: try makeFixtureURL())
        )
        await mp.start(mode: .blitztextRant)
        await mp.stop()
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(openAI.callCount, 0)
        XCTAssertEqual(ollama.callCount, 0)
    }

    func test_providerBackends_mapToSummaryProviders() {
        XCTAssertEqual(RewriteBackend.openRouter.provider, .openRouter)
        XCTAssertEqual(RewriteBackend.requesty.provider, .requesty)
        XCTAssertNil(RewriteBackend.openAI.provider)
        XCTAssertNil(RewriteBackend.ollama.provider)
    }
}
