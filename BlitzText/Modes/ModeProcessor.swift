import Foundation
import AppKit

/// Orchestriert die Pipeline: Aufnahme → Whisper → (optional Rewrite) → Output (Clipboard / Auto-Paste).
@MainActor
final class ModeProcessor: ObservableObject {

    enum State: Equatable {
        case idle
        case recording(Mode)
        case transcribing(Mode)
        case rewriting(Mode)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    private let settings: SettingsStore
    let history: HistoryStore
    /// Konkreter Recorder fuer UI-Zugriff (z. B. `currentLevel` im HUD).
    /// In Pipeline-Tests wird stattdessen `_injectedRecorder` verwendet (siehe `activeRecorder`).
    let recorder = AudioRecorder()
    let suggestionPresenter: SuggestionPresenter
    let modelManager: LocalModelManager
    let diarizerManager: DiarizerModelManager
    let speakerStore: SpeakerProfileStore

    // MARK: - Injection-Slots (Test-Seams, additive Defaults = nil)
    private let _injectedOpenAITranscriber: TranscriptionService?
    private let _injectedLocalTranscriber: TranscriptionService?
    private let _injectedParakeetTranscriber: TranscriptionService?
    private let _injectedRewriter: RewriteService?
    private let _injectedOllamaRewriter: RewriteService?
    private let _injectedRecorder: RecorderProtocol?

    private lazy var defaultOpenAITranscriber: TranscriptionService = WhisperAPIClient(settings: settings)
    private lazy var localClient = LocalWhisperClient(modelManager: modelManager)
    private lazy var defaultLocalTranscriber: TranscriptionService = localClient
    lazy var parakeetClient = ParakeetClient(settings: settings, diarizerManager: diarizerManager, speakerStore: speakerStore)
    private lazy var defaultParakeetTranscriber: TranscriptionService = parakeetClient
    private lazy var defaultRewriter: RewriteService = OpenAIChatClient(settings: settings)
    private lazy var defaultOllamaRewriter: RewriteService = OllamaRewriteClient(settings: settings)
    private let inserter = TextInserter()

    private var openAITranscriber: TranscriptionService {
        _injectedOpenAITranscriber ?? defaultOpenAITranscriber
    }
    private var localTranscriber: TranscriptionService {
        _injectedLocalTranscriber ?? defaultLocalTranscriber
    }
    private var parakeetTranscriber: TranscriptionService {
        _injectedParakeetTranscriber ?? defaultParakeetTranscriber
    }
    private var rewriter: RewriteService {
        _injectedRewriter ?? defaultRewriter
    }
    private var ollamaRewriter: RewriteService {
        _injectedOllamaRewriter ?? defaultOllamaRewriter
    }
    private var activeRecorder: RecorderProtocol {
        _injectedRecorder ?? recorder
    }

    private var activeMode: Mode?
    private var currentRecordingURL: URL?

    init(
        settings: SettingsStore,
        history: HistoryStore,
        modelManager: LocalModelManager,
        diarizerManager: DiarizerModelManager,
        speakerStore: SpeakerProfileStore = SpeakerProfileStore(),
        // NEW (Test-Seams) — Produktion behaelt existierende Lazy-Defaults wenn nil:
        openAITranscriber: TranscriptionService? = nil,
        localTranscriber: TranscriptionService? = nil,
        parakeetTranscriber: TranscriptionService? = nil,
        rewriter: RewriteService? = nil,
        ollamaRewriter: RewriteService? = nil,
        recorder: RecorderProtocol? = nil
    ) {
        self.settings = settings
        self.history = history
        self.modelManager = modelManager
        self.diarizerManager = diarizerManager
        self.speakerStore = speakerStore
        self.suggestionPresenter = SuggestionPresenter(settings: settings)
        self._injectedOpenAITranscriber = openAITranscriber
        self._injectedLocalTranscriber = localTranscriber
        self._injectedParakeetTranscriber = parakeetTranscriber
        self._injectedRewriter = rewriter
        self._injectedOllamaRewriter = ollamaRewriter
        self._injectedRecorder = recorder
    }

    /// Lädt das aktuell aktivierte lokale Modell vorab (im Hintergrund). Nach Modell-Aktivierung
    /// oder beim App-Start aufrufen, damit die erste echte Aufnahme nicht 1–3 min wartet.
    func preloadLocalModelIfActive() {
        switch settings.backend {
        case .openAI:
            return
        case .local:
            guard modelManager.activeID != nil else { return }
            let client = localClient
            Task.detached { await client.warmUp() }
        case .parakeet:
            let client = parakeetClient
            Task.detached { await client.warmUp() }
        }
    }

    // MARK: - Public API

    func start(mode: Mode) async {
        guard activeMode == nil else { return }
        activeMode = mode
        do {
            let url = try activeRecorder.start()
            currentRecordingURL = url
            state = .recording(mode)
        } catch {
            state = .error(humanReadable(error))
            activeMode = nil
            currentRecordingURL = nil
        }
    }

    func stop() async {
        guard let mode = activeMode else { return }
        let url = activeRecorder.stop()
        activeMode = nil
        currentRecordingURL = nil
        guard let url else {
            // zu kurz / zu leise → still verwerfen, kein Whisper-Call (verhindert Halluzinationen)
            state = .idle
            return
        }
        await runPipeline(mode: mode, audioURL: url)
    }

    func toggle(mode: Mode) async {
        if activeMode == nil {
            await start(mode: mode)
        } else if activeMode == mode {
            await stop()
        } else {
            await stop()
            await start(mode: mode)
        }
    }

    // MARK: - Pipeline

    private func runPipeline(mode: Mode, audioURL: URL) async {
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let transcriber: TranscriptionService = {
            switch settings.backend {
            case .openAI:   return openAITranscriber
            case .local:    return localTranscriber
            case .parakeet: return parakeetTranscriber
            }
        }()
        Log.write("Pipeline: backend=\(settings.backend.rawValue) mode=\(mode)")
        state = .transcribing(mode)
        let raw: String
        do {
            raw = try await transcriber.transcribe(
                audioURL: audioURL,
                language: settings.transcriptionLanguage.isEmpty ? nil : settings.transcriptionLanguage,
                prompt: makeWhisperPrompt()
            )
        } catch {
            state = .error(humanReadable(error))
            return
        }
        guard !raw.isEmpty else {
            state = .idle
            return
        }
        if isLikelyHallucination(raw) {
            Log.write("Whisper-Halluzination erkannt, verworfen: \(raw)")
            state = .idle
            return
        }

        let output: String
        let polished: String?
        switch mode {
        case .blitztext:
            output = raw
            polished = nil
        case .blitztextPlus, .blitztextRant:
            state = .rewriting(mode)
            do {
                let backend = settings.rewriteBackend(for: mode)
                let activeRewriter: RewriteService = backend == .ollama ? ollamaRewriter : rewriter
                var systemPrompt = makeRewriteSystemPrompt(for: mode, backend: backend)
                if backend == .ollama {
                    systemPrompt += "\n\nAntworte ausschließlich auf Deutsch."
                }
                let p = try await activeRewriter.rewrite(
                    input: raw,
                    systemPrompt: systemPrompt,
                    model: settings.rewriteModel
                )
                output = p
                polished = p
            } catch {
                state = .error(humanReadable(error))
                return
            }
        }

        deliver(output)
        history.append(mode: mode, rawTranscript: raw, polished: polished)
        state = .idle

        // Eigennamen-Vorschläge: Heuristik (sofort) + AI (asynchron), beide enqueued.
        let heuristic = EigennamenAnalyzer.candidates(rawTranscript: raw, polished: polished)
        if !heuristic.isEmpty {
            suggestionPresenter.enqueue(heuristic)
        }
        if settings.aiSuggestProperNouns {
            let textForAI = polished ?? raw
            let apiKey = settings.apiKey
            let presenter = suggestionPresenter
            Task.detached {
                let aiCandidates = await EigennamenAISuggester.extract(from: textForAI, apiKey: apiKey)
                if !aiCandidates.isEmpty {
                    await MainActor.run { presenter.enqueue(aiCandidates) }
                }
            }
        }
    }

    // MARK: - Prompt-Komposition

    private func makeWhisperPrompt() -> String? {
        var pieces: [String] = []
        if !settings.context.isEmpty {
            pieces.append(settings.context)
        }
        if !settings.properNouns.isEmpty {
            pieces.append("Eigennamen: " + settings.properNouns.joined(separator: ", "))
        }
        let combined = pieces.joined(separator: "\n")
        return combined.isEmpty ? nil : combined
    }

    private func makeRewriteSystemPrompt(for mode: Mode, backend: RewriteBackend) -> String {
        var parts: [String] = []
        switch mode {
        case .blitztextPlus:
            parts.append(settings.customPromptPlus.isEmpty ? Mode.blitztextPlus.defaultRewritePrompt : settings.customPromptPlus)
            parts.append(settings.styleForPlus.promptHint)
        case .blitztextRant:
            parts.append(settings.customPromptRant.isEmpty ? Mode.blitztextRant.defaultRewritePrompt : settings.customPromptRant)
        case .blitztext:
            break
        }
        if !settings.context.isEmpty {
            parts.append("Kontext der sprechenden Person: \(settings.context)")
        }
        if !settings.properNouns.isEmpty {
            parts.append("Schreibe folgende Eigennamen exakt richtig: " + settings.properNouns.joined(separator: ", ") + ".")
        }
        parts.append("Gib ausschließlich den umgeschriebenen Text zurück, keine Vorbemerkungen, keine Anführungszeichen.")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Output

    private func deliver(_ text: String) {
        inserter.copyToClipboard(text)
        if settings.autoInsert {
            inserter.simulatePaste()
        }
    }

    // MARK: - Hallucination filter

    /// Whisper halluziniert bei Stille gerne YouTube-Untertitel-Phrasen.
    /// Wir filtern bekannte Phrasen heuristisch (Substring-Match, case-insensitive).
    private func isLikelyHallucination(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let needles = [
            "amara.org",
            "untertitel der amara",
            "untertitel im auftrag",
            "untertitelung des zdf",
            "untertitel von stephanie geiges",
            "vielen dank fürs zuschauen",
            "vielen dank für eure aufmerksamkeit",
            "untertitel der videos",
            "thanks for watching",
            "subtitles by the amara.org",
            "♪",
            "[musik]",
            "[music]"
        ]
        return needles.contains { lowered.contains($0) }
    }

    // MARK: - Helpers

    private func humanReadable(_ error: Error) -> String {
        if let e = error as? OllamaError, let msg = e.errorDescription { return msg }
        if let e = error as? TranscriptionError, let msg = e.errorDescription { return msg }
        if let e = error as? AudioRecorder.RecorderError {
            switch e {
            case .micDenied: return "Mikrofon-Zugriff verweigert. Bitte in Systemeinstellungen → Datenschutz → Mikrofon erlauben."
            }
        }
        return error.localizedDescription
    }
}
