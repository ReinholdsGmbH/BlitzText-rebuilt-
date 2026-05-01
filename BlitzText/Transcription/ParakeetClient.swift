import Foundation
import FluidAudio

/// Lokale Transkription via NVIDIA Parakeet TDT v3 (FluidAudio, MLX/CoreML, on-device).
/// Optional Speaker Diarization mit Token-Level-Alignment.
final class ParakeetClient: TranscriptionService, @unchecked Sendable {

    private let settings: SettingsStore
    private let diarizerManager: DiarizerModelManager
    private var asrManager: AsrManager?
    private var diarizer: DiarizerManager?
    private var loadingTask: Task<Void, Never>?

    init(settings: SettingsStore, diarizerManager: DiarizerModelManager) {
        self.settings = settings
        self.diarizerManager = diarizerManager
    }

    func warmUp() async {
        // Wenn Diarization-Setting sich geändert hat, neu laden — sonst fehlt das Modell
        if asrManager != nil {
            let matches = await diarizerStateMatches()
            if matches { return }
        }
        await ensureLoaded()
    }

    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String {
        let needsLoad: Bool
        if asrManager == nil {
            needsLoad = true
        } else {
            let matches = await diarizerStateMatches()
            needsLoad = !matches
        }
        if needsLoad {
            await ensureLoaded()
        }
        guard let asrManager else { throw TranscriptionError.backendNotAvailable }

        // Audio einmal als [Float] @16kHz laden — beide Pipelines nutzen dieselben Samples
        let converter = AudioConverter()
        let samples = try converter.resampleAudioFile(audioURL)

        Log.write("Parakeet: starte ASR (\(samples.count) Samples, ~\(String(format: "%.1f", Double(samples.count)/16000))s)…")
        let t0 = Date()
        var decoderState = TdtDecoderState.make()
        let result = try await asrManager.transcribe(samples, decoderState: &decoderState)
        Log.write("Parakeet: ASR fertig (\(String(format: "%.1f", Date().timeIntervalSince(t0)))s) — \(result.text.count) Zeichen")

        // Wenn Diarization aktiv und Modell geladen: parallel Speaker erkennen
        guard settings.parakeetDiarization, let diarizer else {
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        Log.write("Parakeet: starte Diarization…")
        let tDiar = Date()
        do {
            let diarResult = try await diarizer.performCompleteDiarization(samples)
            Log.write("Parakeet: Diarization fertig (\(String(format: "%.1f", Date().timeIntervalSince(tDiar)))s) — \(diarResult.segments.count) Segmente, \(Set(diarResult.segments.map { $0.speakerId }).count) Sprecher")
            return Self.applyDiarization(asr: result, segments: diarResult.segments)
        } catch {
            Log.write("Parakeet: Diarization fehlgeschlagen — \(error.localizedDescription) (gebe Text ohne Sprecher zurück)")
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Verbindet ASR-Token-Timings mit Diarizer-Segmenten zu einem Speaker-annotierten Text.
    /// Format pro Sprecher-Run: `Sprecher 1: …text…`
    private static func applyDiarization(asr: ASRResult, segments: [TimedSpeakerSegment]) -> String {
        let trimmed = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timings = asr.tokenTimings, !timings.isEmpty, !segments.isEmpty else {
            return trimmed
        }

        // Stabile Sprecher-Nummerierung (Reihenfolge des ersten Auftretens)
        var nameMap: [String: Int] = [:]
        for seg in segments where nameMap[seg.speakerId] == nil {
            nameMap[seg.speakerId] = nameMap.count + 1
        }

        // Pro Token den Sprecher anhand der Token-Mitte ermitteln
        func speaker(at time: TimeInterval) -> String? {
            for seg in segments {
                if Double(seg.startTimeSeconds) <= time && time <= Double(seg.endTimeSeconds) {
                    return seg.speakerId
                }
            }
            // Fallback: nächstes Segment
            return segments.min(by: {
                let dA = min(abs(Double($0.startTimeSeconds) - time), abs(Double($0.endTimeSeconds) - time))
                let dB = min(abs(Double($1.startTimeSeconds) - time), abs(Double($1.endTimeSeconds) - time))
                return dA < dB
            })?.speakerId
        }

        var lines: [String] = []
        var currentSpeaker: String?
        var currentText = ""

        for timing in timings {
            let mid = (timing.startTime + timing.endTime) / 2
            let s = speaker(at: mid) ?? currentSpeaker ?? "?"
            let token = timing.token
                .replacingOccurrences(of: "\u{2581}", with: " ") // SentencePiece ▁ → space

            if s != currentSpeaker {
                if let cur = currentSpeaker {
                    let n = nameMap[cur] ?? 0
                    lines.append("Sprecher \(n): \(currentText.trimmingCharacters(in: .whitespaces))")
                }
                currentSpeaker = s
                currentText = token
            } else {
                currentText += token
            }
        }
        if let cur = currentSpeaker, !currentText.isEmpty {
            let n = nameMap[cur] ?? 0
            lines.append("Sprecher \(n): \(currentText.trimmingCharacters(in: .whitespaces))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Loading

    /// True wenn die aktuell geladene Diarizer-Instanz zur Setting+Manager-Lage passt.
    /// - Setting on + manager.isInstalled + diarizer != nil → match
    /// - Setting off + diarizer == nil → match
    /// - Setting on + manager.isInstalled aber diarizer == nil → mismatch (manager.retry() Erfolg → Re-Init nötig)
    @MainActor
    private func diarizerStateMatches() -> Bool {
        if settings.parakeetDiarization {
            return diarizerManager.isInstalled && diarizer != nil
        } else {
            return diarizer == nil
        }
    }

    private func ensureLoaded() async {
        if let existing = loadingTask {
            await existing.value
            return
        }
        let useDiarization = settings.parakeetDiarization
        let task = Task {
            Log.write("Parakeet: lade Modelle (ASR\(useDiarization ? " + Diarizer" : ""))…")
            let t0 = Date()
            do {
                let manager = AsrManager(config: .default)
                try await manager.loadModels(AsrModels.downloadAndLoad())
                self.asrManager = manager

                if useDiarization {
                    // D-16: Manager ist Single-Source-of-Truth für den Diarizer-Modell-
                    // Lifecycle. Er kümmert sich um Download/Progress/Fehler-Klassifikation.
                    let installed = await self.diarizerManager.ensureInstalled()
                    let cachedModels = await self.diarizerManager.modelsIfInstalled
                    if installed, let models = cachedModels {
                        let diar = DiarizerManager(config: .default)
                        diar.initialize(models: models)
                        self.diarizer = diar
                    } else {
                        // Nicht installiert oder Fehler: graceful degrade auf ASR-only.
                        // applyDiarization-Fallback liefert reinen ASR-Text.
                        self.diarizer = nil
                        let stateDesc = await String(describing: self.diarizerManager.state)
                        Log.write("Parakeet: Diarizer nicht verfügbar (state=\(stateDesc)) — fahre ASR-only fort")
                    }
                } else {
                    self.diarizer = nil
                }
                Log.write("Parakeet: bereit (\(String(format: "%.1f", Date().timeIntervalSince(t0)))s)")
            } catch {
                Log.write("Parakeet: Init-Fehler — \(error.localizedDescription)")
            }
        }
        loadingTask = task
        await task.value
        loadingTask = nil
    }
}
