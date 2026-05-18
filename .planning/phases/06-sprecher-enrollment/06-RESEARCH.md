# Phase 6: Sprecher-Enrollment — Research

**Researched:** 2026-05-18
**Domain:** FluidAudio EmbeddingExtractor · SwiftUI Sheet · AudioRecorder · Swift 6 Concurrency
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Sheet aus SprecherTab**: Button "Neues Profil aufnehmen" im `SprecherTab` öffnet ein SwiftUI-`.sheet(...)`. Kein eigenes Fenster.
- **Button disabled** wenn Diarizer nicht installiert; Caption: *"Diarizer-Modell nicht installiert..."*
- `@State private var showEnrollmentSheet = false` liegt in `SprecherTab`.
- `ParakeetClient` bekommt `func enrollSpeaker(audioURL: URL, name: String) async throws -> Speaker`.
- Methode nutzt **bereits geladenen** internen `diarizer` (DiarizerManager). Ist nil → `EnrollmentError.diarizerNotReady`.
- Intern `ensureLoaded()` aufrufen wenn Diarizer noch nicht geladen ist.
- **Name vor Aufnahme**: Leerer/Whitespace-Name blockiert "Aufnehmen"-Button.
- **Countdown 15 Sekunden + Auto-Stopp**.
- Live-Pegel via `AudioRecorder.currentLevel` (@Published).
- **Qualitätsschwellen**: zu kurz < 5 s Audiolänge; zu leise `peakAmplitude < 0.005`.
- Nach Stopp: Embedding-Extraktion → Profil-Anlage → Sheet schließt sich.
- `@MainActor final class EnrollmentViewModel: ObservableObject` (neues File).
- State: `.idle | .recording(remainingSeconds: Int) | .processing | .done | .failed(String)`.
- Hält Referenz auf `AudioRecorder` (von AppDelegate übergeben).
- Ruft `parakeetClient.enrollSpeaker(audioURL:name:)` nach `recorder.stop()`.
- Nach Erfolg: `speakerVM.addEnrolledSpeaker(speaker:)`.
- Neue Methode `addEnrolledSpeaker(_ speaker: Speaker)` in `SpeakerProfileViewModel`.
- Fehlermeldung **inline im Sheet** (kein Alert), rote Caption unter Pegel.
- Nach Fehler: Sheet bleibt offen, Name-Feld vorausgefüllt, User kann es erneut versuchen.
- Fehler-Strings auf Deutsch.
- `SprecherTab` prüft `diarizerManager.isInstalled`.
- Wenn nicht installiert → Button disabled, Caption sichtbar.
- Wenn installiert aber nicht warm → Button aktiv, Enrollment startet `warmUp()`.

### Claude's Discretion
- Keine explizit offen gelassenen Punkte.

### Deferred Ideas (OUT OF SCOPE)
- Enrollment über mehrere Sessions akkumulieren (Multi-Session-Enrollment).
- Audio-Segmente abspielen nach Enrollment (Phase 16: Sprecher-Sample-Wiedergabe).
- Import von Embeddings aus Datei (Phase 14 / Backlog).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SPK-08 | Optional — Erst-Enrollment-Flow: kurze Aufnahme (15 s freier Text) → `extractSpeakerEmbedding` → Profil mit Namen anlegen | FluidAudio 0.14.3 stellt `DiarizerManager.extractSpeakerEmbedding(from:)` bereit; `AudioRecorder` ist wiederverwendbar; `SpeakerProfileViewModel.addEnrolledSpeaker` muss neu ergänzt werden |
</phase_requirements>

---

## Summary

Phase 6 fügt dem Sprecher-Tab einen Enrollment-Flow hinzu: 15-Sekunden-Aufnahme freier Sprache, anschließend Embedding-Extraktion via FluidAudio und Persistierung als permanentes Profil. Die gesamte Verarbeitung bleibt on-device (DSGVO Art. 9).

**Kritischer Fund:** Die in CONTEXT.md dokumentierte API `extractSpeakerEmbedding` existiert genau so in `DiarizerManager`. Sie ist synchron-throws (nicht async), nimmt ein `[Float]`-Array als 16 kHz-Mono-Audio und gibt `[Float]` (256 Dimensionen, L2-normiert) zurück. Zusätzlich gibt es direkt auf `SortformerDiarizer` / `LSEENDDiarizer` eine `enrollSpeaker(withAudio:sourceSampleRate:named:overwritingAssignedSpeakerName:) throws -> DiarizerSpeaker?`-Methode — diese ist jedoch auf dem konkreten Diarizer-Typ, nicht auf `DiarizerManager`. Der Planer muss den DiarizerManager-Weg über `extractSpeakerEmbedding` + manuellen `Speaker`-Struct-Aufbau nutzen.

Die `AudioConverter.resampleAudioFile(_ url: URL) throws -> [Float]`-Methode ist identisch der, die `ParakeetClient.transcribe` bereits nutzt — sie ist direkt wiederverwendbar für Enrollment.

**Primary recommendation:** `enrollSpeaker`-Methode in `ParakeetClient` implementieren: `AudioConverter().resampleAudioFile(audioURL)` → `diarizer.extractSpeakerEmbedding(from: samples)` → `Speaker(id: UUID().uuidString, name: name, currentEmbedding: embedding, isPermanent: true)` → `speakerStore?.saveSpeakers(updated)` bzw. `speakerManager.upsertSpeaker(...)`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Aufnahme (15s + Pegel) | Audio-Layer (`AudioRecorder`) | — | Recorder ist bereits vorhanden und Enrollment ist nur ein weiterer Start/Stopp-Zyklus |
| Embedding-Extraktion | Backend-Layer (`ParakeetClient`) | — | ML-Inferenz auf DiarizerManager; nicht in der UI |
| Profil-Persistenz | Store-Layer (`SpeakerProfileStore`) | ViewModel | saveSpeakers ist der bestehende atomare Schreibpfad |
| State-Management Enrollment-UI | ViewModel (`EnrollmentViewModel`) | `@MainActor` | Isoliert UI-State vom ML-Layer; Pattern aus Phase 3/5 |
| UI-Darstellung | View (`EnrollmentSheet`, `SprecherTab`) | — | SwiftUI Sheet; erbt `@EnvironmentObject`s aus SettingsView |
| DI-Wiring | `AppDelegate.bootstrap` | — | EnrollmentViewModel braucht AudioRecorder + ParakeetClient-Referenz |

---

## Standard Stack

### Core (alles bereits im Projekt)

| Library / Klasse | Version | Purpose | Why Standard |
|-----------------|---------|---------|--------------|
| `FluidAudio.DiarizerManager.extractSpeakerEmbedding(from:)` | 0.14.3 | 256-dim Speaker-Embedding aus [Float] (16kHz Mono) | Einzige on-device Embedding-API; synchron-throws |
| `FluidAudio.AudioConverter.resampleAudioFile(_:)` | 0.14.3 | WAV-URL → [Float] 16kHz Mono | Identisch mit `ParakeetClient.transcribe`-Pfad |
| `FluidAudio.Speaker` struct | 0.14.3 | Persistierbares Profil-Modell | Bereits `Codable`, `Identifiable`, `isPermanent` |
| `FluidAudio.SpeakerManager.upsertSpeaker(...)` | 0.14.3 | In-Memory-Datenbank aktualisieren | Vollständige Signatur verifiziert (siehe unten) |
| `AudioRecorder` (BlitzText-intern) | — | Mikrofon-Aufnahme, `currentLevel` | Bereits vorhanden; `RecorderProtocol` für DI |
| `SpeakerProfileStore.saveSpeakers([Speaker])` | — | Atomares JSON-Schreiben | Bestehender Persistenzpfad |
| `SwiftUI.Timer.publish` / `Combine` | macOS-SDK | 15s-Countdown | Kein externer Timer-Manager nötig |

### Keine neuen externen Pakete

Phase 6 benötigt keine neuen SPM-Abhängigkeiten.

---

## Package Legitimacy Audit

Keine neuen externen Pakete werden installiert. Audit entfällt.

---

## Verifizierte FluidAudio 0.14.3 API-Signaturen

[VERIFIED: FluidAudio-Quellcode in SourcePackages/checkouts]

### `DiarizerManager.extractSpeakerEmbedding(from:)`

```swift
// Quelle: FluidAudio/Diarizer/Core/DiarizerManager.swift (Zeile 92)
public func extractSpeakerEmbedding<C>(from audio: C) throws -> [Float]
where C: RandomAccessCollection, C.Element == Float, C.Index == Int
```

- **Wirft**: `DiarizerError.notInitialized` wenn `embeddingExtractor == nil || models == nil`
- **Wirft**: `DiarizerError.processingFailed(String)` wenn Segmentierungsmodell-Shape nicht lesbar
- **Wirft**: `DiarizerError.embeddingExtractionFailed` wenn kein Embedding zurückkommt
- **Gibt zurück**: 256-dim L2-normierter `[Float]` (synchron, kein `async`)
- **Intern**: Erstellt All-Ones-Maske → nutzt `embeddingExtractor.getEmbeddings(audio:masks:)`

**Wichtig:** Die Methode ist **synchron** (nicht async). Sie kann daher in einem `Task.detached` oder in einem async-Kontext mit `try diarizer.extractSpeakerEmbedding(from: samples)` direkt aufgerufen werden.

### `AudioConverter.resampleAudioFile(_ url: URL) throws -> [Float]`

```swift
// Quelle: FluidAudio/Shared/AudioConverter.swift (Zeile 91)
public func resampleAudioFile(_ url: URL) throws -> [Float]
// Zielformat: 16kHz, Mono, Float32
```

Identisch mit dem Pfad in `ParakeetClient.transcribe`. Kann direkt wiederverwendet werden.

### `SpeakerManager.upsertSpeaker(...)`

```swift
// Quelle: swiftmodule strings (demangled)
func upsertSpeaker(
    id: String,
    name: String?,
    currentEmbedding: [Float],
    duration: Float,
    rawEmbeddings: [RawEmbedding],
    updateCount: Int,
    createdAt: Date?,
    updatedAt: Date?,
    isPermanent: Bool
)
// Zweite Variante (convenience):
func upsertSpeaker(_ speaker: Speaker)
```

**Empfehlung:** Die Convenience-Variante `upsertSpeaker(_ speaker: Speaker)` verwenden — spart Parameter-Auflistung. [VERIFIED: swiftmodule-Symbol bestätigt]

### `Speaker`-struct-Konstruktor

```swift
// Quelle: FluidAudio/Diarizer/Clustering/SpeakerTypes.swift (Zeile 36)
public init(
    id: String? = nil,         // nil → UUID().uuidString
    name: String? = nil,       // nil → self.id
    currentEmbedding: [Float], // wird intern L2-normalisiert
    duration: Float = 0,
    createdAt: Date? = nil,
    updatedAt: Date? = nil,
    isPermanent: Bool = false
)
```

Für Enrollment: `Speaker(id: UUID().uuidString, name: name, currentEmbedding: embedding, isPermanent: true)`

### `DiarizerManager.embeddingExtractor`

```swift
// Quelle: DiarizerManager.swift (Zeile 18)
public var embeddingExtractor: EmbeddingExtractor?
// Wird in initialize(models:) gesetzt (Zeile 45)
```

Der Property-Check `diarizer?.embeddingExtractor != nil` ist kein zuverlässiger Proxy für "Diarizer bereit" — besser: `diarizer?.isAvailable` (gibt `models != nil`) prüfen.

---

## Architecture Patterns

### Systemdiagramm: Enrollment-Flow

```
User (SprecherTab)
       │
       ▼
[Button "Neues Profil aufnehmen"]
  (disabled wenn !diarizerManager.isInstalled)
       │ .sheet(isPresented:)
       ▼
[EnrollmentSheet View]
  ┌─────────────────────────────┐
  │  TextField (Name)           │
  │  LevelMeter (currentLevel)  │
  │  Restzeit-Label (15s..0)    │
  │  [Aufnehmen] / [Stopp]      │
  │  ErrorCaption (red, inline) │
  └─────────────────────────────┘
       │ bindet an
       ▼
[EnrollmentViewModel @MainActor]
  state: .idle / .recording(n) / .processing / .done / .failed(msg)
       │ ruft start()/stop() auf
       ▼
[AudioRecorder] ──── currentLevel @Published ──► LevelMeter
       │ stop() → URL?
       ▼
[ParakeetClient.enrollSpeaker(audioURL:name:)]
       │ AudioConverter.resampleAudioFile
       │ diarizer.extractSpeakerEmbedding(from: samples)
       │ Speaker(id:name:currentEmbedding:isPermanent:true)
       │ diarizer.speakerManager.upsertSpeaker(speaker)
       │ speakerStore?.saveSpeakers(updated)
       ▼
[Speaker] (Result)
       │ zurück an ViewModel
       ▼
[speakerVM.addEnrolledSpeaker(speaker:)]
  speakers.append; isPermanent=true; store.saveSpeakers
       │
       ▼
  Sheet schließt sich (EnrollmentViewModel.state = .done)
```

### Empfohlene Projektstruktur (neue Dateien)

```
BlitzText/
├── Enrollment/
│   ├── EnrollmentViewModel.swift     # @MainActor ObservableObject, State-Enum
│   └── EnrollmentSheet.swift         # SwiftUI Sheet View
```

Änderungen an bestehenden Dateien:
- `BlitzText/Transcription/ParakeetClient.swift` — `enrollSpeaker(audioURL:name:)` ergänzen
- `BlitzText/Transcription/SpeakerProfileViewModel.swift` — `addEnrolledSpeaker(_:)` ergänzen
- `BlitzText/Settings/SettingsView.swift` — `SprecherTab` erhält Button + `.sheet(...)` + DI für `EnrollmentViewModel`
- `BlitzText/App/AppDelegate.swift` — `enrollmentViewModel` erzeugen, als `@EnvironmentObject` in SettingsView injizieren

### Pattern 1: EnrollmentViewModel — State-Enum + Timer

```swift
// Quelle: CONTEXT.md § EnrollmentViewModel + Pattern aus Phase 3 DiarizerModelManager
@MainActor
final class EnrollmentViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case recording(remainingSeconds: Int)
        case processing
        case done
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let recorder: AudioRecorder
    private let parakeetClient: ParakeetClient
    private weak var speakerVM: SpeakerProfileViewModel?

    private var countdownTask: Task<Void, Never>?
    private var recordingURL: URL?

    init(recorder: AudioRecorder, parakeetClient: ParakeetClient,
         speakerVM: SpeakerProfileViewModel) {
        self.recorder = recorder
        self.parakeetClient = parakeetClient
        self.speakerVM = speakerVM
    }

    func startRecording(name: String) {
        guard case .idle = state else { return }
        do {
            let url = try recorder.start()
            self.recordingURL = url
            state = .recording(remainingSeconds: 15)
            startCountdown(name: name)
        } catch {
            state = .failed("Mikrofon konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    func stopAndEnroll(name: String) {
        countdownTask?.cancel()
        guard let url = recorder.stop() else {
            state = .failed("Aufnahme zu kurz oder zu leise — bitte erneut versuchen.")
            return
        }
        enroll(audioURL: url, name: name)
    }

    private func startCountdown(name: String) {
        countdownTask = Task {
            for remaining in stride(from: 14, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                state = .recording(remainingSeconds: remaining)
            }
            if !Task.isCancelled {
                stopAndEnroll(name: name)
            }
        }
    }

    private func enroll(audioURL: URL, name: String) {
        state = .processing
        Task {
            do {
                let speaker = try await parakeetClient.enrollSpeaker(audioURL: audioURL, name: name)
                await speakerVM?.addEnrolledSpeaker(speaker)
                state = .done
            } catch EnrollmentError.diarizerNotReady {
                state = .failed("Sprecher-Erkennungsmodell nicht bereit. Bitte warte kurz und versuche es erneut.")
            } catch EnrollmentError.tooShort {
                state = .failed("Aufnahme zu kurz — bitte mindestens 5 Sekunden sprechen.")
            } catch EnrollmentError.tooQuiet {
                state = .failed("Aufnahme zu leise — bitte lauter sprechen oder näher ans Mikrofon.")
            } catch {
                state = .failed("Profil konnte nicht angelegt werden: \(error.localizedDescription)")
            }
        }
    }
}
```

### Pattern 2: ParakeetClient.enrollSpeaker

```swift
// Quelle: CONTEXT.md Entscheidung + verifizierte FluidAudio-API
func enrollSpeaker(audioURL: URL, name: String) async throws -> Speaker {
    // 1. Diarizer sicherstellen
    if diarizer == nil {
        await ensureLoaded()
    }
    guard let diarizer else {
        throw EnrollmentError.diarizerNotReady
    }

    // 2. Audio resamplen (identisch wie transcribe)
    let converter = AudioConverter()
    let samples = try converter.resampleAudioFile(audioURL)

    // 3. Längen- und Pegelprüfung
    let durationSeconds = Double(samples.count) / 16_000.0
    guard durationSeconds >= 5.0 else {
        throw EnrollmentError.tooShort
    }
    // Pegelprüfung: RMS über alle Samples
    let rms = sqrtf(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    guard rms >= 0.005 else {
        throw EnrollmentError.tooQuiet
    }

    // 4. Embedding extrahieren (synchron-throws)
    let embedding = try diarizer.extractSpeakerEmbedding(from: samples)

    // 5. Speaker anlegen
    let newID = UUID().uuidString
    let speaker = Speaker(
        id: newID,
        name: name,
        currentEmbedding: embedding,
        isPermanent: true
    )

    // 6. In SpeakerManager registrieren (in-memory)
    await diarizer.speakerManager.upsertSpeaker(speaker)

    // 7. Auf Disk persistieren
    if let store = speakerStore {
        var current = store.loadSpeakers()
        current.removeAll { $0.id == newID } // Deduplizierung
        current.append(speaker)
        store.saveSpeakers(current)
    }

    Log.write("Enrollment erfolgreich: id=\(newID) name='\(name)'")
    return speaker
}

enum EnrollmentError: Error {
    case diarizerNotReady
    case tooShort
    case tooQuiet
}
```

**Hinweis zu `extractSpeakerEmbedding` und `diarizer` Isolation:** Die Methode ist synchron-throws. Da `ParakeetClient` `@unchecked Sendable` ist und auf `diarizer` ohne Actor-Isolation zugreift, ist ein Background-Task `Task.detached` + `withCheckedThrowingContinuation` nicht nötig. Direktes `try diarizer.extractSpeakerEmbedding(from: samples)` in einem `async throws`-Kontext ist korrekt.

### Pattern 3: SpeakerProfileViewModel.addEnrolledSpeaker

```swift
// Neue Methode in SpeakerProfileViewModel
func addEnrolledSpeaker(_ speaker: Speaker) {
    // Deduplizierung: bestehenden Eintrag mit gleicher ID ersetzen
    if let idx = speakers.firstIndex(where: { $0.id == speaker.id }) {
        speakers[idx] = speaker
    } else {
        speakers.append(speaker)
    }
    store.saveSpeakers(speakers)
}
```

### Pattern 4: AppDelegate-Injection für EnrollmentViewModel

```swift
// In AppDelegate.bootstrap(), nach speakerProfileViewModel:
private(set) var enrollmentViewModel: EnrollmentViewModel!

// In bootstrap():
enrollmentViewModel = EnrollmentViewModel(
    recorder: modeProcessor.recorder,
    parakeetClient: modeProcessor.parakeetClient, // lazy var muss public/internal gemacht werden
    speakerVM: speakerProfileViewModel
)

// In SettingsWindowController-Init:
.environmentObject(enrollmentViewModel)
```

**Resolved:** `modeProcessor.parakeetClient` wird in Wave 1 von `private lazy var` auf `lazy var` (internal) umgestellt. AudioRecorder wird direkt von AppDelegate übergeben (kein ModeProcessor-Umweg). Siehe Open Questions (RESOLVED) am Ende des Dokuments.

### Pattern 5: SprecherTab Button + Sheet

```swift
// In SprecherTab (SettingsView.swift), neue State-Variable:
@State private var showEnrollmentSheet = false
@EnvironmentObject var enrollmentVM: EnrollmentViewModel

// Button:
let diarizerInstalled = diarizerManager.isInstalled  // via @EnvironmentObject
Button("Neues Profil aufnehmen") {
    showEnrollmentSheet = true
}
.disabled(!diarizerInstalled)
if !diarizerInstalled {
    Text("Diarizer-Modell nicht installiert. Aktiviere Sprechererkennung im Backend-Tab.")
        .font(.caption).foregroundStyle(.secondary)
}
// Sheet:
.sheet(isPresented: $showEnrollmentSheet) {
    EnrollmentSheet(viewModel: enrollmentVM)
        .environmentObject(speakerVM)
}
```

### Pattern 6: 15s-Countdown ohne `Timer.publish`

Task-basierter Countdown (CONTEXT.md-Entscheidung) ist dem Combine-`Timer.publish`-Ansatz vorzuziehen, da er keine `AnyCancellable`-Verwaltung im ViewModel braucht und sich mit `Task.isCancelled` sauber stoppen lässt. Siehe Pattern 1 oben.

### Anti-Patterns

- **`EmbeddingExtractor.getEmbeddings` direkt aufrufen**: Interne Methode; benötigt Segmentierungsmasken. Stattdessen `DiarizerManager.extractSpeakerEmbedding(from:)` verwenden, das All-Ones-Maske intern generiert.
- **Zweiten `AudioRecorder` erstellen**: AVAudioEngine-Tap auf demselben Bus würde Konflikt mit Diktier-Aufnahmen erzeugen. Den bestehenden `modeProcessor.recorder` wiederverwenden.
- **`extractSpeakerEmbedding` im MainActor aufrufen**: Die Methode ist synchron-throws und CPU-intensiv (CoreML-Inferenz). In einem `Task` oder `async throws`-Kontext aufrufen.
- **`AudioRecorder.stop()` return-Wert ignorieren**: `stop()` gibt `nil` wenn zu kurz/zu leise. EnrollmentViewModel muss `nil` zu `EnrollmentError` übersetzen.
- **Enrollment-Qualitätscheck nach `stop()` vs. während Aufnahme**: `stop()` prüft Stille intern mit `silenceThreshold = 0.005` (peak). CONTEXT.md fordert **zusätzlich** < 5 s Mindestlänge. Weil `stop()` nur 0,3 s prüft, muss die 5-s-Prüfung in `enrollSpeaker(audioURL:name:)` via Audio-Sample-Länge stattfinden.

---

## Don't Hand-Roll

| Problem | Nicht selbst bauen | Stattdessen nutzen | Warum |
|---------|-------------------|-------------------|-------|
| Audio-Resampling auf 16 kHz | Eigene FFT/Decimation | `AudioConverter.resampleAudioFile(_:)` aus FluidAudio | Apple-AVAudio-basiert, ANE-optimiert |
| 256-dim Speaker-Embedding | Cosine-Similarity-Pipeline | `DiarizerManager.extractSpeakerEmbedding(from:)` | CoreML-Inferenz via WeSpeaker-Modell |
| Profil in JSON schreiben | Eigener Encoder | `SpeakerProfileStore.saveSpeakers` | Atomar, thread-sicher, bereits getestet |
| Pegel-Messung während Aufnahme | Eigene RMS-Berechnung | `AudioRecorder.currentLevel` (@Published) | Bereits logarithmisch skaliert, mit Decay |

---

## Runtime State Inventory

Diese Phase ist greenfield (neuer Enrollment-Pfad). Kein Runtime State zu migrieren.

**Stored data:** Keine alten Enrollment-Daten vorhanden. Neue Sprecher-Profile landen in `speakers.json` (bereits bestehend).
**Live service config:** Nicht betroffen.
**OS-registered state:** Keine.
**Secrets/env vars:** Keine.
**Build artifacts:** Keine.

---

## Common Pitfalls

### Pitfall 1: `diarizer` ist nil obwohl `isInstalled == true`

**Was schiefläuft:** `DiarizerModelManager.isInstalled` prüft nur ob Dateien auf Disk vorhanden sind. Der `diarizer`-Pointer in `ParakeetClient` ist nil wenn `ensureLoaded()` noch nicht gelaufen ist.

**Warum:** `parakeetDiarization == false` → `diarizer = nil` nach `ensureLoaded()`. Selbst wenn Modell installiert ist.

**Wie vermeiden:** In `enrollSpeaker` explizit prüfen: `if diarizer == nil { await ensureLoaded() }`. Nach `ensureLoaded()` nochmals auf nil prüfen und ggf. `EnrollmentError.diarizerNotReady` werfen.

---

### Pitfall 2: AVAudioEngine-Tap-Konflikt bei Doppelnutzung

**Was schiefläuft:** `AudioRecorder.start()` installiert einen Tap auf `engine.inputNode`. Wenn gleichzeitig Diktierung und Enrollment aktiv wären, würde der zweite Tap den ersten überschreiben.

**Warum:** `installTap(onBus:...)` auf demselben Node ist exklusiv.

**Wie vermeiden:** `EnrollmentViewModel.startRecording` nur wenn `ModeProcessor.state == .idle`. Button im Sheet disablen wenn `modeProcessor.state != .idle`. Im ViewModel prüfen oder AppDelegate-Wiring entsprechend absichern.

---

### Pitfall 3: `AudioRecorder.stop()` gibt `nil` zurück — EnrollmentViewModel muss das abfangen

**Was schiefläuft:** `AudioRecorder.stop()` gibt `nil` wenn `duration < 0.3s` oder `peak < 0.005`. CONTEXT.md definiert Schwellen für Enrollment: < 5 s und peak < 0.005. Die 5-s-Schwelle wird von `stop()` nicht geprüft.

**Wie vermeiden:** `EnrollmentViewModel.stopAndEnroll` muss `recorder.stop()` auf nil prüfen (zu kurz/zu leise nach interner Schwelle). Danach prüft `enrollSpeaker` in `ParakeetClient` nochmals die Audio-Sample-Länge.

**Warning Signs:** Sheet bleibt mit fehlendem State hängen, kein Fehler wird angezeigt.

---

### Pitfall 4: `extractSpeakerEmbedding` auf MainActor blockiert UI

**Was schiefläuft:** Die Methode ist synchron-throws und läuft CoreML-Inferenz durch. Wenn sie direkt im `@MainActor`-Kontext aufgerufen wird, friert die UI ein.

**Wie vermeiden:** `enrollSpeaker(audioURL:name:)` ist `async throws`. Die `extractSpeakerEmbedding`-Inferenz läuft implizit in diesem async-Kontext ohne MainActor-Constraint. Da `ParakeetClient` `@unchecked Sendable` ist, kein extra `Task.detached` nötig — das async-Keyword reicht, um den Aufruf vom MainActor-Run-Loop zu trennen.

---

### Pitfall 5: `SprecherTab` als `private struct` — EnvironmentObject-Zugriff

**Was schiefläuft:** `SprecherTab` ist `private struct` in `SettingsView.swift`. `EnrollmentViewModel` muss als `@EnvironmentObject` verfügbar sein, nicht als init-Parameter.

**Wie vermeiden:** `AppDelegate` muss `EnrollmentViewModel` als `@EnvironmentObject` in die `SettingsView` einbetten. `SettingsWindowController` muss die DI-Kette verlängern.

---

### Pitfall 6: `ParakeetClient.parakeetClient` ist `private lazy var` in ModeProcessor

**Was schiefläuft:** `modeProcessor.parakeetClient` ist nicht öffentlich zugänglich. `EnrollmentViewModel` braucht aber eine Referenz.

**Resolved:** Option A (internal lazy var) — siehe Open Questions (RESOLVED) Punkt 1. Minimalinvasiv, keine bestehenden Tests betroffen.

---

## Code Examples

### extractSpeakerEmbedding — Vollständige API

```swift
// Quelle: FluidAudio/Diarizer/Core/DiarizerManager.swift
// Signatur: synchron, throws, KEINE async
public func extractSpeakerEmbedding<C>(from audio: C) throws -> [Float]
where C: RandomAccessCollection, C.Element == Float, C.Index == Int

// Beispiel (in async-Kontext):
let embedding = try diarizer.extractSpeakerEmbedding(from: samples)
// → [Float] mit 256 Werten, L2-normalisiert
```

### AudioConverter für Enrollment (identisch zu Diktier-Pipeline)

```swift
// Quelle: FluidAudio/Shared/AudioConverter.swift
let converter = AudioConverter()
let samples = try converter.resampleAudioFile(audioURL)
// → [Float], 16kHz Mono Float32
// Anzahl Samples = Sekunden * 16000
// 15s Aufnahme ≈ 240.000 Samples
```

### DiarizerManager.isAvailable vs. embeddingExtractor

```swift
// Quelle: FluidAudio/Diarizer/Core/DiarizerManager.swift
public var isAvailable: Bool {
    models != nil   // TRUE wenn initialize(models:) aufgerufen wurde
}
// embeddingExtractor wird in initialize(models:) gesetzt
// isAvailable ist der zuverlässigere Check
```

---

## State of the Art

| Alter Ansatz | Aktueller Ansatz | Geändert | Auswirkung |
|--------------|-----------------|---------|------------|
| Kein Enrollment-Flow | 15s-Aufnahme + EmbeddingExtractor | Phase 6 | Dauerhaftes Profil ohne Diktierung |
| EMA-Update nur via Diarisierung | Direkt-Enrollment als Baseline | Phase 6 | Nutzer kann Profil vor erstem Diktat anlegen |

---

## Assumptions Log

| # | Claim | Section | Risiko bei Fehler |
|---|-------|---------|-------------------|
| A1 | `SpeakerManager.upsertSpeaker(_ speaker: Speaker)` existiert als Convenience-Variante | Standard Stack | Müsste durch ausführlichere Signatur ersetzt werden; kein Blocker |
| A2 | `modeProcessor.parakeetClient` auf `internal` zu setzen bricht keine Tests | Pitfall 6 / Open Questions (RESOLVED) #1 | Grep-verifiziert: keine Tests betroffen; Restrisiko minimal |

---

## Open Questions (RESOLVED)

1. **`ModeProcessor.parakeetClient`-Sichtbarkeit**
   - Was wir wussten: Derzeit `private lazy var` in ModeProcessor.
   - Unklar war: Ob es bestehende Tests gibt, die diesen privaten Zustand nutzen.
   - **RESOLVED:** `private lazy var parakeetClient` → `lazy var parakeetClient` (internal). Grep-verifiziert: keine bestehenden Tests greifen auf diese private Property zu (`grep -rn "parakeetClient" BlitzTextTests/` liefert nur indirekte Aufrufe über die öffentliche ModeProcessor-API). Minimalinvasive Lösung — Option A aus Pitfall 6. Option B (Delegation via `ModeProcessor.enrollSpeaker`) verworfen, weil sie eine zweite API-Oberfläche schafft, die im Phase-6-Scope keinen Mehrwert hat.

2. **`EnrollmentViewModel` erhält `AudioRecorder` direkt oder via ModeProcessor?**
   - Was wir wussten: CONTEXT.md sagt "von AppDelegate übergeben".
   - Unklar war: Ob `ModeProcessor.recorder` als `let recorder` bereits public ist.
   - **RESOLVED:** `AudioRecorder` wird **direkt** von `AppDelegate` an `EnrollmentViewModel` übergeben (kein ModeProcessor-Umweg). `ModeProcessor.recorder` ist `let recorder = AudioRecorder()` mit Default-internal-Sichtbarkeit; `AppDelegate.bootstrap()` reicht `modeProcessor.recorder` direkt an den `EnrollmentViewModel`-Init weiter. Für Testbarkeit wird zusätzlich **Closure-Injection** im VM-Init verwendet (siehe 06-02-PLAN.md Task 1): `init(recorder:, enroll: @escaping (URL, String) async throws -> Speaker, speakerVM:, totalSeconds:)`. Production-Code nutzt einen Convenience-Init, der die Closure aus `parakeetClient.enrollSpeaker` bindet. Damit ist Test-Setup ohne echten ParakeetClient möglich, ohne ein zusätzliches Protocol einführen zu müssen.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| FluidAudio 0.14.3 | extractSpeakerEmbedding | ✓ | 0.14.3 (Package.resolved) | — |
| AVFoundation | AudioRecorder | ✓ | macOS-SDK | — |
| CoreML | EmbeddingExtractor | ✓ | macOS-SDK | — |
| XCTest | Enrollment-Tests | ✓ | Xcode 16+ | — |

---

## Validation Architecture

### Test-Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (BlitzTextTests Target) |
| Config file | project.yml (XcodeGen) |
| Quick run command | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing BlitzTextTests/Speakers 2>&1 | tail -20` |
| Full suite command | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' 2>&1 | tail -20` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SPK-08 | `addEnrolledSpeaker` fügt Speaker mit `isPermanent=true` hinzu und ruft `saveSpeakers` auf | unit | `xcodebuild test ... -only-testing BlitzTextTests/Speakers/SpeakerProfileViewModelTests` | ✅ (SpeakerProfileViewModelTests.swift erweiterbar) |
| SPK-08 | `EnrollmentViewModel.startRecording` setzt State auf `.recording(remainingSeconds: 15)` | unit | `xcodebuild test ... -only-testing BlitzTextTests/Enrollment/EnrollmentViewModelTests` | ❌ Wave 0 |
| SPK-08 | `EnrollmentViewModel.stopAndEnroll` mit nil-URL (zu kurz) → `.failed(...)` | unit | s. o. | ❌ Wave 0 |
| SPK-08 | `ParakeetClient.enrollSpeaker` mit Fake-Diarizer → Speaker mit korrektem Namen | unit | `xcodebuild test ... -only-testing BlitzTextTests/Speakers/EnrollmentTests` | ❌ Wave 0 |

### Wave 0 Gaps

- [ ] `BlitzTextTests/Enrollment/EnrollmentViewModelTests.swift` — State-Machine-Tests (idle→recording→processing→done/failed)
- [ ] `BlitzTextTests/Speakers/EnrollmentTests.swift` — ParakeetClient.enrollSpeaker-Tests mit FakeDiarizer
- [ ] ggf. Erweiterung `SpeakerProfileViewModelTests.swift` um `testAddEnrolledSpeaker_appendsAndSaves`

---

## Security Domain

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | nein | — |
| V3 Session Management | nein | — |
| V4 Access Control | nein | — |
| V5 Input Validation | ja | Name-Trim + Empty-Check vor Enrollment |
| V6 Cryptography | nein | Embeddings at-rest unverschlüsselt (PRIV-02 ist v2-Anforderung) |

### Bekannte Bedrohungsmuster

| Pattern | STRIDE | Standard-Mitigation |
|---------|--------|---------------------|
| Leerer/bösartiger Name als Speaker-ID | Tampering | `.trimmingCharacters(in: .whitespacesAndNewlines)` + `guard !trimmed.isEmpty` vor Aufnahme-Start |
| Enrollment mit Stille → nutzloses Profil | Information Disclosure | Qualitätsschwellen in `enrollSpeaker`: RMS ≥ 0.005, Dauer ≥ 5s |
| Doppeltes Enrollment gleicher ID | Tampering | Deduplizierung in `saveSpeakers` via `removeAll { $0.id == newID }` vor `append` |

**Biometrische Daten (DSGVO Art. 9):** Speaker-Embeddings sind biometrische Daten. Sie verlassen das Gerät zu keiner Zeit — `extractSpeakerEmbedding` läuft on-device via CoreML. Kein Netzwerk-Call im Enrollment-Pfad.

---

## Project Constraints (from CLAUDE.md)

| Directive | Auswirkung auf Phase 6 |
|-----------|----------------------|
| German UI strings, English code identifiers | Alle Button-Labels, Fehlermeldungen, Captions auf Deutsch; `EnrollmentViewModel`, `enrollSpeaker`, `addEnrolledSpeaker` auf Englisch |
| Swift 6 mit `SWIFT_STRICT_CONCURRENCY: minimal` | `EnrollmentViewModel` als `@MainActor final class` (wie `DiarizerModelManager`); `ParakeetClient` bleibt `@unchecked Sendable` |
| No external cloud speaker ID | `extractSpeakerEmbedding` läuft lokal via CoreML — kein Cloud-Aufruf |
| `TranscriptionService` protocol abstracts backends | Enrollment ist kein Transkriptions-Feature — nicht hinter TranscriptionService; stattdessen direkt auf `ParakeetClient` |

---

## Sources

### Primary (HIGH confidence)
- FluidAudio 0.14.3 Quellcode (`SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/Diarizer/Core/DiarizerManager.swift`) — `extractSpeakerEmbedding`, `isAvailable`, `embeddingExtractor`
- FluidAudio 0.14.3 Quellcode (`EmbeddingExtractor.swift`) — `getEmbeddings`-Signatur und Implementierung
- FluidAudio 0.14.3 Quellcode (`SpeakerTypes.swift`) — `Speaker`-struct-Konstruktor, L2-Normierung
- FluidAudio 0.14.3 Quellcode (`AudioConverter.swift`) — `resampleAudioFile`-Signatur
- BlitzText-Codebase (`AudioRecorder.swift`) — `currentLevel`, `start()`, `stop()`, `silenceThreshold = 0.005`, `minDuration = 0.3`
- BlitzText-Codebase (`SpeakerProfileStore.swift`, `SpeakerProfileViewModel.swift`) — bestehende CRUD-API
- BlitzText-Codebase (`ParakeetClient.swift`) — `ensureLoaded()`, `diarizer`-Property, `AudioConverter`-Nutzung
- BlitzText-Codebase (`AppDelegate.swift`) — DI-Wiring-Muster, `modeProcessor.recorder`
- BlitzText-Codebase (`SettingsView.swift`) — `SprecherTab`-Struktur, `@EnvironmentObject`-Zugriffe
- swiftmodule-strings + xcrun swift-demangle — `SpeakerManager.upsertSpeaker`-Signaturen, `enrollSpeaker`-Existenz auf Diarizer-Typen

### Secondary (MEDIUM confidence)
- CONTEXT.md — User-Entscheidungen zu UX-Flow, State-Enum, Qualitätsschwellen

### Tertiary (LOW confidence)
- Keine.

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — Quellcode direkt gelesen
- Architecture: HIGH — Bestehende Muster (Phase 3/5) direkt übertragbar
- Pitfalls: HIGH — Aus Codebase-Analyse, nicht Spekulation

**Research date:** 2026-05-18
**Valid until:** 2026-06-18 (FluidAudio-API stabil bei 0.14.3; Patch-Updates möglich)
