import Foundation
import FluidAudio

/// Lokale Transkription via NVIDIA Parakeet TDT v3 (FluidAudio, MLX/CoreML, on-device).
/// Optional Speaker Diarization mit Token-Level-Alignment und persistenten Sprecher-Profilen.
final class ParakeetClient: TranscriptionService, @unchecked Sendable {

    private let settings: SettingsStore
    private let diarizerManager: DiarizerModelManager
    private let speakerStore: SpeakerProfileStore?
    private var asrManager: AsrManager?
    private var diarizer: DiarizerManager?
    private var loadingTask: Task<Void, Never>?

    init(settings: SettingsStore, diarizerManager: DiarizerModelManager, speakerStore: SpeakerProfileStore? = nil) {
        self.settings = settings
        self.diarizerManager = diarizerManager
        self.speakerStore = speakerStore
    }

    func warmUp() async {
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

        let converter = AudioConverter()
        let samples = try converter.resampleAudioFile(audioURL)

        Log.write("Parakeet: starte ASR (\(samples.count) Samples, ~\(String(format: "%.1f", Double(samples.count)/16000))s)…")
        let t0 = Date()
        var decoderState = TdtDecoderState.make()
        let result = try await asrManager.transcribe(samples, decoderState: &decoderState)
        Log.write("Parakeet: ASR fertig (\(String(format: "%.1f", Date().timeIntervalSince(t0)))s) — \(result.text.count) Zeichen")

        guard settings.parakeetDiarization, let diarizer else {
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        Log.write("Parakeet: starte Diarization…")
        let tDiar = Date()
        do {
            let diarResult = try await diarizer.performCompleteDiarization(samples)
            Log.write("Parakeet: Diarization fertig (\(String(format: "%.1f", Date().timeIntervalSince(tDiar)))s) — \(diarResult.segments.count) Segmente, \(Set(diarResult.segments.map { $0.speakerId }).count) Sprecher")

            let speakers = await diarizer.speakerManager.getSpeakerList()
            speakerStore?.saveSpeakers(speakers)
            let speakerNames = Self.buildSpeakerNames(from: speakers)

            return Self.applyDiarization(asr: result, segments: diarResult.segments, speakerNames: speakerNames)
        } catch {
            Log.write("Parakeet: Diarization fehlgeschlagen — \(error.localizedDescription) (gebe Text ohne Sprecher zurück)")
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Baut eine ID→Name-Map für bekannte (explizit benannte) Sprecher.
    /// Sprecher mit FluidAudio-Standardnamen ("Speaker N") gelten als unbenannt.
    static func buildSpeakerNames(from speakers: [Speaker]) -> [String: String] {
        speakers.reduce(into: [:]) { dict, s in
            if s.name != "Speaker \(s.id)" {
                dict[s.id] = s.name
            }
        }
    }

    /// Verbindet ASR-Token-Timings mit Diarizer-Segmenten zu einem Speaker-annotierten Text.
    /// Benannte Sprecher erscheinen als `Thomas: …`, unbenannte als `Sprecher N: …`.
    static func applyDiarization(
        asr: ASRResult,
        segments: [TimedSpeakerSegment],
        speakerNames: [String: String] = [:]
    ) -> String {
        let trimmed = asr.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timings = asr.tokenTimings, !timings.isEmpty, !segments.isEmpty else {
            return trimmed
        }

        // Stabile Nummerierung für unbenannte Sprecher (Reihenfolge des ersten Auftretens)
        var unnamedMap: [String: Int] = [:]
        for seg in segments where speakerNames[seg.speakerId] == nil && unnamedMap[seg.speakerId] == nil {
            unnamedMap[seg.speakerId] = unnamedMap.count + 1
        }

        func label(for speakerId: String) -> String {
            if let name = speakerNames[speakerId] { return name }
            let n = unnamedMap[speakerId] ?? 0
            return "Sprecher \(n)"
        }

        func speaker(at time: TimeInterval) -> String? {
            for seg in segments {
                if Double(seg.startTimeSeconds) <= time && time <= Double(seg.endTimeSeconds) {
                    return seg.speakerId
                }
            }
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
            let token = timing.token.replacingOccurrences(of: "\u{2581}", with: " ")

            if s != currentSpeaker {
                if let cur = currentSpeaker {
                    lines.append("\(label(for: cur)): \(currentText.trimmingCharacters(in: .whitespaces))")
                }
                currentSpeaker = s
                currentText = token
            } else {
                currentText += token
            }
        }
        if let cur = currentSpeaker, !currentText.isEmpty {
            lines.append("\(label(for: cur)): \(currentText.trimmingCharacters(in: .whitespaces))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Loading

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
                    let installed = await self.diarizerManager.ensureInstalled()
                    let cachedModels = await self.diarizerManager.modelsIfInstalled
                    if installed, let models = cachedModels {
                        let diar = DiarizerManager(config: .default)
                        diar.initialize(models: models)
                        if let store = self.speakerStore {
                            let knownSpeakers = store.loadSpeakers()
                            if !knownSpeakers.isEmpty {
                                await diar.speakerManager.initializeKnownSpeakers(knownSpeakers, mode: .skip)
                                Log.write("Parakeet: \(knownSpeakers.count) Sprecher-Profile geladen")
                            }
                        }
                        self.diarizer = diar
                    } else {
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
