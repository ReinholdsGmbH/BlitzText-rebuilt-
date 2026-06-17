import Foundation
import FluidAudio

// MARK: - Enrollment

enum EnrollmentError: Error {
    /// Diarizer-Modell ist nicht geladen oder nicht initialisiert.
    case diarizerNotReady
    /// Audio ist kürzer als 5 Sekunden.
    case tooShort
    /// Audio-Pegel (RMS) zu niedrig (< 0.005).
    case tooQuiet
}

// MARK: - ParakeetClient

/// Lokale Transkription via NVIDIA Parakeet TDT v3 (FluidAudio, MLX/CoreML, on-device).
/// Optional Speaker Diarization mit Token-Level-Alignment und persistenten Sprecher-Profilen.
final class ParakeetClient: TranscriptionService, @unchecked Sendable {

    private let settings: SettingsStore
    private let diarizerManager: DiarizerModelManager
    private let speakerStore: SpeakerProfileStore?
    private var asrManager: AsrManager?
    private var diarizer: DiarizerManager?
    private var loadingTask: Task<Void, Never>?
    /// Schützt das Check-and-Set von `loadingTask` gegen TOCTOU bei parallelen
    /// `warmUp()`/`transcribe()`-Aufrufen. Wird NIE über ein `await` gehalten.
    private let loadLock = NSLock()

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

        // SPK-07: Threshold vor jeder Session aktuell setzen — greift sofort für nächste Aufnahme.
        let threshold = Float(settings.speakerMatchThreshold)
        await diarizer.speakerManager.setSpeakerThreshold(threshold)

        Log.write("Parakeet: starte Diarization (threshold=\(threshold))…")
        let tDiar = Date()
        do {
            let diarResult = try await diarizer.performCompleteDiarization(samples)
            Log.write("Parakeet: Diarization fertig (\(String(format: "%.1f", Date().timeIntervalSince(tDiar)))s) — \(diarResult.segments.count) Segmente, \(Set(diarResult.segments.map { $0.speakerId }).count) Sprecher")

            let runtimeSpeakers = await diarizer.speakerManager.getSpeakerList()
            let sessionSpeakerIDs = Array(Set(diarResult.segments.map { $0.speakerId }))
            Log.write("Parakeet: \(runtimeSpeakers.count) Runtime-Sprecher, \(sessionSpeakerIDs.count) Session-IDs, tokenTimings=\(result.tokenTimings?.count ?? -1)")

            // Wenn der User in der UI einen Sprecher umbenannt hat, liegt der neue Name nur
            // auf Disk — der in-memory SpeakerManager kennt ihn nicht. Hier werden
            // benutzerdefinierte Namen aus dem Store in die Runtime-Liste eingeblendet,
            // bevor gespeichert und der Output gebaut wird.
            let mergedSpeakers = Self.mergePersistedNames(runtimeSpeakers, from: speakerStore)
            speakerStore?.saveSession(speakers: mergedSpeakers, sessionSpeakerIDs: sessionSpeakerIDs)
            let speakerNames = Self.buildSpeakerNames(from: mergedSpeakers)
            Log.write("Parakeet: \(speakerNames.count) benannte Sprecher, applyDiarization mit \(diarResult.segments.count) Segmenten")

            return Self.applyDiarization(asr: result, segments: diarResult.segments, speakerNames: speakerNames)
        } catch {
            Log.write("Parakeet: Diarization fehlgeschlagen — \(error.localizedDescription) (gebe Text ohne Sprecher zurück)")
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Erstellt ein permanentes Sprecher-Profil aus einer Audio-Datei (SPK-08).
    /// Extrahiert ein 256-dim Speaker-Embedding via FluidAudio und persistiert das Profil.
    /// - Parameters:
    ///   - audioURL: Pfad zur Audio-Datei (wird auf 16 kHz Mono resampled).
    ///   - name: Anzeigename des neuen Profils.
    /// - Returns: Der neu angelegte `Speaker` mit `isPermanent = true`.
    /// - Throws: `EnrollmentError.diarizerNotReady`, `.tooShort` oder `.tooQuiet`.
    func enrollSpeaker(audioURL: URL, name: String) async throws -> Speaker {
        // 1. Diarizer sicherstellen
        if diarizer == nil {
            await ensureLoaded()
        }
        guard let diarizer else {
            throw EnrollmentError.diarizerNotReady
        }

        // 2. Audio resamplen (identisches Muster wie transcribe)
        let converter = AudioConverter()
        let samples = try converter.resampleAudioFile(audioURL)

        // 3. Längenprüfung (T-06-01: Mindestdauer 5 Sekunden)
        let durationSeconds = Double(samples.count) / 16_000.0
        guard durationSeconds >= 5.0 else {
            throw EnrollmentError.tooShort
        }

        // 4. Pegelprüfung — RMS über alle Samples (T-06-01: selbe Schwelle wie AudioRecorder)
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrtf(sumOfSquares / Float(samples.count))
        guard rms >= 0.005 else {
            throw EnrollmentError.tooQuiet
        }

        // 5. Embedding extrahieren (synchron-throws; läuft korrekt im async-Kontext)
        let embedding = try diarizer.extractSpeakerEmbedding(from: samples)

        // 6. Speaker-Struct anlegen
        let newID = UUID().uuidString
        let speaker = Speaker(
            id: newID,
            name: name,
            currentEmbedding: embedding,
            isPermanent: true
        )

        // 7. In-Memory-SpeakerManager aktualisieren (Convenience-Variante)
        await diarizer.speakerManager.upsertSpeaker(speaker)

        // 8. Auf Disk persistieren (Deduplizierung per ID)
        if let store = speakerStore {
            var current = store.loadSpeakers()
            current.removeAll { $0.id == newID }
            current.append(speaker)
            store.saveSpeakers(current)
        }

        Log.write("Enrollment erfolgreich: id=\(newID) (\(name.count) Zeichen Name)")
        return speaker
    }

    /// Übernimmt benutzerdefinierte Namen und isPermanent aus dem persistierten Store
    /// in die Runtime-Speaker-Liste. Einbettungen und Statistiken kommen aus der Runtime.
    static func mergePersistedNames(_ runtimeSpeakers: [Speaker], from store: SpeakerProfileStore?) -> [Speaker] {
        guard let store else { return runtimeSpeakers }
        let persisted = store.loadSpeakers()
        let namedByID: [String: Speaker] = persisted.reduce(into: [:]) { d, s in
            let isDefault = s.name == "Speaker \(s.id)" || s.name == s.id
            if !isDefault { d[s.id] = s }
        }
        return runtimeSpeakers.map { s in
            guard let p = namedByID[s.id] else { return s }
            var updated = s
            updated.name = p.name
            updated.isPermanent = p.isPermanent
            return updated
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
            let detectedSpeaker = speaker(at: mid) ?? currentSpeaker ?? "?"
            // Sprecherwechsel nur an Wortgrenzen. FluidAudio normalisiert ▁ (U+2581) zu
            // führendem Leerzeichen — deshalb auf " " (U+0020) prüfen, nicht auf ▁.
            let isWordBoundary = timing.token.hasPrefix(" ")
            let s = (currentSpeaker == nil || isWordBoundary) ? detectedSpeaker : currentSpeaker!
            let token = timing.token

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
        // Genau EINE Load-Task erzeugen, auch bei parallelen Aufrufen. Der Lock schützt nur
        // das synchrone Check-and-Set — das eigentliche Warten passiert lockfrei via `await`.
        let task: Task<Void, Never> = {
            loadLock.lock()
            defer { loadLock.unlock() }
            if let existing = loadingTask { return existing }
            let useDiarization = settings.parakeetDiarization
            let created = Task {
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
                            // Nur permanente (enrollte) Sprecher laden — anonyme Session-Sprecher
                            // aus alten Sessions würden den Matcher verwirren.
                            let knownSpeakers = store.loadSpeakers().filter { $0.isPermanent }
                            if !knownSpeakers.isEmpty {
                                await diar.speakerManager.initializeKnownSpeakers(knownSpeakers, mode: .skip)
                                Log.write("Parakeet: \(knownSpeakers.count) enrollte Sprecher-Profile geladen")
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
            loadingTask = created
            return created
        }()
        await task.value
        loadLock.withLock { loadingTask = nil }
    }
}
