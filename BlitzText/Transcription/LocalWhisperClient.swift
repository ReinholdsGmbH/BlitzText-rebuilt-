import Foundation
import WhisperKit

/// Lokale Whisper-Inferenz via WhisperKit (CoreML, on-device).
/// Lädt das im LocalModelManager als "aktiv" gesetzte Modell beim ersten Use,
/// hält es danach im Speicher.
final class LocalWhisperClient: TranscriptionService, @unchecked Sendable {

    private let modelManager: LocalModelManager
    private var pipeline: WhisperKit?
    private var loadedID: String?
    private var loadingTask: Task<Void, Never>?

    init(modelManager: LocalModelManager) {
        self.modelManager = modelManager
    }

    /// Lädt das aktuell aktive Modell vorab in den Speicher (CoreML-Compile + Init).
    /// Beim ersten Mal pro Modell 1–3 min, danach <1 s. Idempotent — mehrfacher Aufruf ist OK.
    func warmUp() async {
        let activeID = await MainActor.run { modelManager.activeID }
        guard let activeID else { return }
        if loadedID == activeID && pipeline != nil { return }
        await ensureLoaded(activeID: activeID)
    }

    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String {
        let activeID = await MainActor.run { modelManager.activeID }
        guard let activeID else {
            throw TranscriptionError.backendNotAvailable
        }

        if loadedID != activeID || pipeline == nil {
            await ensureLoaded(activeID: activeID)
        }
        guard let pipeline else { throw TranscriptionError.backendNotAvailable }

        // Sprache explizit setzen — sonst rät Whisper bei kurzen Aufnahmen oft Englisch.
        // Bei `.en`-Modellen ist language=nil OK (Modell unterstützt nur Englisch).
        let decodeLang = (language?.isEmpty == false) ? language : nil
        var options = DecodingOptions()
        options.verbose = false
        options.task = .transcribe
        options.language = decodeLang
        options.temperature = 0
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        options.withoutTimestamps = true

        Log.write("WhisperKit: starte Inferenz (lang=\(decodeLang ?? "auto"))…")
        let tInfer = Date()
        let results = try await pipeline.transcribe(audioPath: audioURL.path, decodeOptions: options)
        let text: String = results.map { $0.text as String }.joined(separator: " ")
        Log.write("WhisperKit: Inferenz fertig (\(String(format: "%.1f", Date().timeIntervalSince(tInfer)))s) — \(text.count) Zeichen")
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    /// Garantiert, dass `pipeline` für `activeID` initialisiert ist.
    /// Mehrfache parallele Aufrufe warten auf denselben Load-Vorgang.
    private func ensureLoaded(activeID: String) async {
        if loadedID == activeID && pipeline != nil { return }

        // Wenn schon ein Load läuft, warte darauf
        if let existing = loadingTask {
            await existing.value
            return
        }

        let manager = modelManager
        let folder = await MainActor.run { manager.folder(for: activeID) }

        let task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                manager.isPreloading = true
                manager.preloadedID = nil
            }
            Log.write("WhisperKit: lade Modell \(activeID) (CoreML-Compile beim ersten Mal 1–3 min)…")
            let t0 = Date()
            do {
                let config = WhisperKitConfig(model: activeID, modelFolder: folder.path)
                self.pipeline = try await WhisperKit(config)
                self.loadedID = activeID
                let dur = Date().timeIntervalSince(t0)
                Log.write("WhisperKit: Modell geladen (\(String(format: "%.1f", dur))s)")
                await MainActor.run {
                    manager.isPreloading = false
                    manager.preloadedID = activeID
                    manager.preloadDurationSeconds = dur
                    manager.lastError = nil
                }
            } catch {
                Log.write("WhisperKit: Modell-Load fehlgeschlagen — \(error.localizedDescription)")
                await MainActor.run {
                    manager.isPreloading = false
                    manager.preloadedID = nil
                    manager.lastError = "Modell-Load: \(error.localizedDescription)"
                }
            }
        }
        loadingTask = task
        await task.value
        loadingTask = nil
    }
}
