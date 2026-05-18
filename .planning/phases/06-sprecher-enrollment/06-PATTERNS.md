# Phase 6: Sprecher-Enrollment — Pattern Map

**Mapped:** 2026-05-18
**Files analyzed:** 8 (2 neu, 6 modifiziert)
**Analogs found:** 8 / 8

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `BlitzText/Enrollment/EnrollmentViewModel.swift` (NEU) | viewmodel | event-driven / request-response | `BlitzText/Transcription/DiarizerModelManager.swift` | role-match (gleich: @MainActor ObservableObject, State-Enum, Task-basiert) |
| `BlitzText/Enrollment/EnrollmentSheet.swift` (NEU) | component | event-driven | `BlitzText/Settings/SettingsView.swift` → `UnnamedSpeakerRow`, `SprecherTab` | role-match (Sheet-artige UI, TextField + Button, inline-Fehler-Caption) |
| `BlitzText/Transcription/ParakeetClient.swift` (modifiziert) | service | request-response | `BlitzText/Transcription/ParakeetClient.swift` selbst (Methode `transcribe`) | exact (gleiche Datei, gleicher Resampling-Pfad) |
| `BlitzText/Transcription/SpeakerProfileViewModel.swift` (modifiziert) | viewmodel | CRUD | `BlitzText/Transcription/SpeakerProfileViewModel.swift` selbst (Methode `assignName`) | exact (gleiche Datei, gleiche Muster rename/assignName) |
| `BlitzText/Transcription/SpeakerProfileStore.swift` (lesen/ref) | store | file-I/O | — | Referenz-only; keine Änderungen nötig |
| `BlitzText/Settings/SettingsView.swift` (modifiziert) | component | event-driven | `BlitzText/Settings/SettingsView.swift` → `SprecherTab` | exact (gleiche Datei, .confirmationDialog-Muster → .sheet-Muster) |
| `BlitzText/App/AppDelegate.swift` (modifiziert) | config / DI | — | `BlitzText/App/AppDelegate.swift` selbst (bootstrap) | exact (gleiche Datei, speakerProfileViewModel-Wiring) |
| `BlitzText/Settings/SettingsWindowController.swift` (modifiziert) | config / DI | — | `BlitzText/Settings/SettingsWindowController.swift` selbst | exact (gleiche Datei, .environmentObject-Kette) |

---

## Pattern Assignments

### `BlitzText/Enrollment/EnrollmentViewModel.swift` (NEU — viewmodel, event-driven)

**Primär-Analog:** `BlitzText/Transcription/DiarizerModelManager.swift`
**Sekundär-Analog:** `BlitzText/Modes/ModeProcessor.swift` (State-Enum auf ModeProcessor)

**Imports-Pattern** (DiarizerModelManager.swift Zeilen 1–4):
```swift
import Foundation
import Combine
import FluidAudio
```
Für EnrollmentViewModel: `Combine` nur wenn nötig (Task-basierter Countdown braucht es nicht).
```swift
import Foundation
import FluidAudio
```

**@MainActor-ObservableObject-Deklaration** (DiarizerModelManager.swift Zeilen 17–18):
```swift
@MainActor
final class DiarizerModelManager: ObservableObject {
```
Gleich für EnrollmentViewModel:
```swift
@MainActor
final class EnrollmentViewModel: ObservableObject {
```

**State-Enum-Pattern** (DiarizerModelManager.swift Zeile 6–11 + ModeProcessor.swift Zeilen 8–15):
```swift
// DiarizerModelManager nutzt top-level enum; ModeProcessor nutzt nested enum
enum DiarizerModelState: Equatable {
    case notInstalled
    case downloading(progress: Double, etaSeconds: Double?)
    case installed
    case failed(message: String)
}
```
Für EnrollmentViewModel nested State-Enum mit Associated Value:
```swift
enum State: Equatable {
    case idle
    case recording(remainingSeconds: Int)
    case processing
    case done
    case failed(String)
}
@Published private(set) var state: State = .idle
```

**Task-basierter async-Ablauf** (DiarizerModelManager.swift Zeilen 130–162):
```swift
let task = Task { [weak self, loader] in
    do {
        // … async-Arbeit …
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.state = .installed
            self.loadingTask = nil
        }
    } catch {
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.state = .failed(message: msg)
            self.loadingTask = nil
        }
    }
}
loadingTask = task
```
Für EnrollmentViewModel: `countdownTask: Task<Void, Never>?` mit Task.isCancelled-Check im Loop; `enrollTask: Task<Void, Never>?` für Embedding-Extraktion.

**Task.isCancelled-Countdown-Loop** (Muster aus RESEARCH.md Pattern 1, ergänzt durch DiarizerModelManager-Task-Pattern):
```swift
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
```

**weak-self-DI-Referenz** (DiarizerModelManager.swift Zeile 11):
```swift
private weak var speakerVM: SpeakerProfileViewModel?
```

**Error-handling nach State-Pattern** (DiarizerModelManager.swift Zeilen 148–162):
```swift
} catch {
    await MainActor.run { [weak self] in
        guard let self else { return }
        let msg = Self.classify(error)
        self.lastError = msg
        self.state = .failed(message: msg)
        self.loadingTask = nil
        Log.write("…")
    }
}
```
Für EnrollmentViewModel: direkte State-Zuweisung ohne `MainActor.run` (ViewModel ist bereits @MainActor):
```swift
} catch EnrollmentError.diarizerNotReady {
    state = .failed("Sprecher-Erkennungsmodell nicht bereit. Bitte warte kurz und versuche es erneut.")
} catch EnrollmentError.tooShort {
    state = .failed("Aufnahme zu kurz — bitte mindestens 5 Sekunden sprechen.")
} catch EnrollmentError.tooQuiet {
    state = .failed("Aufnahme zu leise — bitte lauter sprechen oder näher ans Mikrofon.")
} catch {
    state = .failed("Profil konnte nicht angelegt werden: \(error.localizedDescription)")
}
```

---

### `BlitzText/Enrollment/EnrollmentSheet.swift` (NEU — component, event-driven)

**Primär-Analog:** `BlitzText/Settings/SettingsView.swift` → `UnnamedSpeakerRow` (Zeilen 649–681) + `SprecherTab`
**Sekundär-Analog:** `BlitzText/Settings/SettingsView.swift` → `SpeakerRow` (TextField + inline OK/Cancel)

**Struct-Deklaration als private View** (SettingsView.swift Zeile 649):
```swift
private struct UnnamedSpeakerRow: View {
    let speaker: Speaker
    let onAssign: (String) -> Void
    @State private var name: String = ""
```
EnrollmentSheet erhält stattdessen den ViewModel als Parameter:
```swift
struct EnrollmentSheet: View {
    @ObservedObject var viewModel: EnrollmentViewModel
    @EnvironmentObject var speakerVM: SpeakerProfileViewModel
```

**TextField + disabled-Button-Pattern** (SettingsView.swift Zeilen 665–669):
```swift
TextField("Name eingeben", text: $name)
    .textFieldStyle(.roundedBorder)
    .frame(maxWidth: 180)
    .onSubmit { commit() }
Button("Zuweisen") { commit() }
    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
```
Analog für Enrollment-Namensfeld + Aufnahme-Button:
```swift
TextField("Name", text: $speakerName)
    .textFieldStyle(.roundedBorder)
Button("Aufnehmen") { viewModel.startRecording(name: speakerName) }
    .disabled(speakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || viewModel.state != .idle)
```

**Inline-Fehler-Caption (rote Text-Zeile)** (SettingsView.swift analog `LokalTab` Zeilen 427–429):
```swift
if let err = modelManager.lastError {
    Text(err).foregroundStyle(.red).font(.caption)
}
```
Für EnrollmentSheet (basierend auf State-Pattern):
```swift
if case .failed(let msg) = viewModel.state {
    Text(msg).foregroundStyle(.red).font(.caption)
}
```

**State-Switch für Button-Label** (SettingsView.swift DiarizerStatusBlock switch Zeile 797–828 als Vorlage):
```swift
switch viewModel.state {
case .idle:
    Button("Aufnehmen") { viewModel.startRecording(name: speakerName) }
case .recording(let remaining):
    Text("Aufnahme läuft … \(remaining) s")
    Button("Stopp") { viewModel.stopAndEnroll(name: speakerName) }
case .processing:
    ProgressView("Profil wird erstellt …").controlSize(.small)
case .done:
    // Sheet schließt sich — kein explizites Label nötig
    EmptyView()
case .failed:
    Button("Erneut versuchen") { viewModel.reset() }
}
```

**Section-Header-Pattern** (SettingsView.swift AnpassenTab Zeilen 181–187):
```swift
@ViewBuilder
private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.caption).foregroundStyle(.secondary).bold()
        content()
    }
}
```

**Pegel-Balken via @Published currentLevel** (AudioRecorder.swift Zeile 17):
```swift
@MainActor @Published private(set) var currentLevel: Float = 0
```
Im Sheet: `ProgressView(value: Double(viewModel.recorder.currentLevel))` oder eine eigene `LevelMeterView` analog zu RecordingHUD.

---

### `BlitzText/Transcription/ParakeetClient.swift` — neue Methode `enrollSpeaker` (modifiziert, service)

**Analog:** Methode `transcribe` in derselben Datei (Zeilen 29–83)

**Imports** — keine neuen Imports nötig; `Foundation` und `FluidAudio` bereits vorhanden (Zeile 1–2):
```swift
import Foundation
import FluidAudio
```

**AudioConverter-Resampling-Pattern** (ParakeetClient.swift Zeilen 43–44):
```swift
let converter = AudioConverter()
let samples = try converter.resampleAudioFile(audioURL)
```
Identisch in `enrollSpeaker` wiederverwendbar.

**ensureLoaded-Guard-Pattern** (ParakeetClient.swift Zeilen 30–39):
```swift
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
```
Für enrollSpeaker vereinfacht:
```swift
if diarizer == nil {
    await ensureLoaded()
}
guard let diarizer else {
    throw EnrollmentError.diarizerNotReady
}
```

**Log.write-Pattern** (ParakeetClient.swift Zeilen 45, 49, 80):
```swift
Log.write("Parakeet: starte ASR (\(samples.count) Samples, ~\(String(format: "%.1f", Double(samples.count)/16000))s)…")
```
Für enrollSpeaker:
```swift
Log.write("Enrollment erfolgreich: id=\(newID) name='\(name)'")
```

**speakerStore-Schreibmuster** (ParakeetClient.swift Zeilen 73–74):
```swift
let mergedSpeakers = Self.mergePersistedNames(runtimeSpeakers, from: speakerStore)
speakerStore?.saveSession(speakers: mergedSpeakers, sessionSpeakerIDs: sessionSpeakerIDs)
```
Für enrollSpeaker: direktes `saveSpeakers` (kein Session-Kontext):
```swift
if let store = speakerStore {
    var current = store.loadSpeakers()
    current.removeAll { $0.id == newID }
    current.append(speaker)
    store.saveSpeakers(current)
}
```

**EnrollmentError-Enum** — neue top-level enum in derselben Datei oder separater `EnrollmentError.swift`:
```swift
enum EnrollmentError: Error {
    case diarizerNotReady
    case tooShort
    case tooQuiet
}
```

**ModeProcessor.parakeetClient Sichtbarkeit** (ModeProcessor.swift Zeile 39):
```swift
// IST:
private lazy var parakeetClient = ParakeetClient(settings: settings, diarizerManager: diarizerManager, speakerStore: speakerStore)
// SOLL (minimale Änderung):
lazy var parakeetClient = ParakeetClient(settings: settings, diarizerManager: diarizerManager, speakerStore: speakerStore)
```
(`private` entfernen → `internal` Standardsichtbarkeit; `defaultParakeetTranscriber` bleibt wie bisher)

---

### `BlitzText/Transcription/SpeakerProfileViewModel.swift` — neue Methode `addEnrolledSpeaker` (modifiziert, viewmodel)

**Analog:** Methode `assignName` in derselben Datei (Zeilen 64–71)

**assignName-Pattern** (SpeakerProfileViewModel.swift Zeilen 64–71):
```swift
func assignName(to id: String, name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let idx = speakers.firstIndex(where: { $0.id == id }) else { return }
    speakers[idx].name = trimmed
    speakers[idx].isPermanent = true
    store.saveSpeakers(speakers)
}
```
Für `addEnrolledSpeaker`: kein guard-Trimm nötig (Name bereits validiert im ViewModel), aber Deduplizierung:
```swift
func addEnrolledSpeaker(_ speaker: Speaker) {
    if let idx = speakers.firstIndex(where: { $0.id == speaker.id }) {
        speakers[idx] = speaker
    } else {
        speakers.append(speaker)
    }
    store.saveSpeakers(speakers)
}
```

**store.saveSpeakers-Aufruf-Pattern** (SpeakerProfileViewModel.swift Zeilen 35–36, 42, 48, 60, 70):
```swift
store.saveSpeakers(speakers)
```
Unveränderter Aufruf.

---

### `BlitzText/Settings/SettingsView.swift` — SprecherTab Button + Sheet-Mount (modifiziert, component)

**Analog:** Dieselbe Datei — `SprecherTab.allSpeakersSection` mit `.confirmationDialog` (Zeilen 587–628)

**@State-Variable + @EnvironmentObject-Zugriff** (SettingsView.swift Zeilen 541–546):
```swift
private struct SprecherTab: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var speakerVM: SpeakerProfileViewModel
    @State private var speakerToDelete: Speaker?
    @State private var showDeleteConfirm = false
```
Ergänzen:
```swift
    @State private var showEnrollmentSheet = false
    @EnvironmentObject var enrollmentVM: EnrollmentViewModel
    @EnvironmentObject var diarizerManager: DiarizerModelManager
```
Hinweis: `diarizerManager` ist bereits als `@EnvironmentObject` in `SettingsWindowController.show()` (Zeile 32) injiziert.

**Button-disabled-Pattern** (SettingsView.swift Zeilen 376–379):
```swift
if settings.backend == .local && modelManager.activeID == nil {
    Text("Lokales Backend gewählt, aber kein Modell aktiviert. …")
        .font(.caption).foregroundStyle(.orange)
}
```
Analog für Enrollment:
```swift
Button("Neues Profil aufnehmen") {
    showEnrollmentSheet = true
}
.disabled(!diarizerManager.isInstalled)
if !diarizerManager.isInstalled {
    Text("Diarizer-Modell nicht installiert. Aktiviere Sprechererkennung im Backend-Tab.")
        .font(.caption).foregroundStyle(.secondary)
}
```

**Sheet-Mount-Pattern** — kein direktes Sheet-Muster in SettingsView vorhanden; nächster Analog ist `.confirmationDialog` (Zeilen 612–628):
```swift
.confirmationDialog(
    "Sprecher wirklich löschen?",
    isPresented: $showDeleteConfirm,
    titleVisibility: .visible
) { … }
```
SwiftUI-Sheet läuft analog:
```swift
.sheet(isPresented: $showEnrollmentSheet, onDismiss: {
    enrollmentVM.reset()
}) {
    EnrollmentSheet(viewModel: enrollmentVM)
        .environmentObject(speakerVM)
}
```

---

### `BlitzText/App/AppDelegate.swift` — DI-Wiring EnrollmentViewModel (modifiziert, config)

**Analog:** Dieselbe Datei — `speakerProfileViewModel`-Deklaration und -Wiring (Zeilen 11, 69)

**private(set) var-Deklaration** (AppDelegate.swift Zeile 11):
```swift
private(set) var speakerProfileViewModel: SpeakerProfileViewModel!
```
Analog für EnrollmentViewModel:
```swift
private(set) var enrollmentViewModel: EnrollmentViewModel!
```

**bootstrap()-Wiring-Pattern** (AppDelegate.swift Zeilen 69, 77):
```swift
speakerProfileViewModel = SpeakerProfileViewModel(store: modeProcessor.speakerStore)
// …
recordingHUD = RecordingHUDController(recorder: modeProcessor.recorder, processor: modeProcessor, settings: settingsStore)
```
Ergänzen nach `speakerProfileViewModel`-Zeile:
```swift
enrollmentViewModel = EnrollmentViewModel(
    recorder: modeProcessor.recorder,
    parakeetClient: modeProcessor.parakeetClient,  // lazy var muss internal sein
    speakerVM: speakerProfileViewModel
)
```

---

### `BlitzText/Settings/SettingsWindowController.swift` — EnvironmentObject-Kette erweitern (modifiziert, config)

**Analog:** Dieselbe Datei — init und `.environmentObject`-Kette (Zeilen 14–34)

**init-Parameter-Pattern** (SettingsWindowController.swift Zeilen 14–19):
```swift
init(settings: SettingsStore, modelManager: LocalModelManager, diarizerManager: DiarizerModelManager, speakerViewModel: SpeakerProfileViewModel) {
    self.settings = settings
    self.modelManager = modelManager
    self.diarizerManager = diarizerManager
    self.speakerViewModel = speakerViewModel
}
```
Ergänzen um `enrollmentViewModel`:
```swift
init(settings: SettingsStore, modelManager: LocalModelManager, diarizerManager: DiarizerModelManager, speakerViewModel: SpeakerProfileViewModel, enrollmentViewModel: EnrollmentViewModel) {
    // … wie bisher …
    self.enrollmentViewModel = enrollmentViewModel
}
```

**environmentObject-Kette** (SettingsWindowController.swift Zeilen 29–33):
```swift
rootView: SettingsView()
    .environmentObject(settings)
    .environmentObject(modelManager)
    .environmentObject(diarizerManager)
    .environmentObject(speakerViewModel)
```
Ergänzen:
```swift
    .environmentObject(enrollmentViewModel)
```

---

## Shared Patterns

### @MainActor ObservableObject
**Quelle:** `BlitzText/Transcription/DiarizerModelManager.swift` Zeilen 17–18
**Anwenden auf:** `EnrollmentViewModel`
```swift
@MainActor
final class EnrollmentViewModel: ObservableObject {
    @Published private(set) var state: State = .idle
}
```

### Task-basierte async-Arbeit mit weak self
**Quelle:** `BlitzText/Transcription/DiarizerModelManager.swift` Zeilen 130–135
**Anwenden auf:** `EnrollmentViewModel.enroll(audioURL:name:)` und `startCountdown`
```swift
let task = Task { [weak self] in
    // …
    await MainActor.run { [weak self] in
        guard let self else { return }
        self.state = .done
    }
}
```
Hinweis: Da `EnrollmentViewModel` selbst `@MainActor` ist, kann `state`-Zuweisung direkt ohne `MainActor.run` erfolgen, solange der Task nicht `detached` ist.

### Log.write für Tracing
**Quelle:** `BlitzText/Transcription/ParakeetClient.swift` Zeilen 45, 49, 80
**Anwenden auf:** `ParakeetClient.enrollSpeaker`, `EnrollmentViewModel`
```swift
Log.write("Enrollment erfolgreich: id=\(newID) name='\(name)'")
```

### store.saveSpeakers — atomarer JSON-Schreibpfad
**Quelle:** `BlitzText/Transcription/SpeakerProfileStore.swift` Zeilen 33–38
**Anwenden auf:** `SpeakerProfileViewModel.addEnrolledSpeaker`, `ParakeetClient.enrollSpeaker`
```swift
func saveSpeakers(_ speakers: [Speaker]) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(speakers) else { return }
    try? data.write(to: url, options: .atomic)
}
```

### Inline-disabled-Button mit Whitespace-Guard
**Quelle:** `BlitzText/Settings/SettingsView.swift` Zeilen 667–669
**Anwenden auf:** EnrollmentSheet "Aufnehmen"-Button
```swift
Button("Aufnehmen") { commit() }
    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
```

### EnvironmentObject-Injection via SettingsWindowController
**Quelle:** `BlitzText/Settings/SettingsWindowController.swift` Zeilen 29–33
**Anwenden auf:** EnrollmentViewModel in SettingsView-Hierarchie
```swift
rootView: SettingsView()
    .environmentObject(settings)
    .environmentObject(modelManager)
    .environmentObject(diarizerManager)
    .environmentObject(speakerViewModel)
    // + .environmentObject(enrollmentViewModel)
```

---

## No Analog Found

Alle Dateien haben starke Analogs. Keine Datei ohne Muster.

| Datei | Hinweis |
|-------|---------|
| `EnrollmentError` (enum) | Ggf. als top-level enum in `ParakeetClient.swift` oder eigene `EnrollmentError.swift`. Kein Analog nötig — simples Swift-Error-Enum. |

---

## Kritische Constraints (aus RESEARCH.md)

| Constraint | Betroffene Datei | Maßnahme |
|-----------|-----------------|---------|
| `extractSpeakerEmbedding` ist **synchron-throws** (nicht async) | `ParakeetClient.enrollSpeaker` | Direkter `try diarizer.extractSpeakerEmbedding(from: samples)` in async-Kontext — kein `Task.detached` nötig |
| `modeProcessor.parakeetClient` ist `private lazy var` | `ModeProcessor.swift` Zeile 39 | `private` entfernen → `internal` (Option A, minimalinvasiv) |
| Kein zweiter `AudioRecorder` erstellen | `EnrollmentViewModel` | `modeProcessor.recorder` (bereits `let recorder = AudioRecorder()`, internal) übergeben |
| `AudioRecorder.stop()` gibt `nil` bei zu kurz/zu leise | `EnrollmentViewModel.stopAndEnroll` | Nil-Check → `.failed("Aufnahme zu kurz oder zu leise …")` |
| Enrollment nur wenn `ModeProcessor.state == .idle` | `EnrollmentViewModel.startRecording` | Guard auf `modeProcessor.state` oder Button im Sheet disablen |

---

## Metadata

**Analog-Suchbereich:** `BlitzText/` (alle Swift-Dateien)
**Dateien gelesen:** 8 Quelldateien + CONTEXT.md + RESEARCH.md
**Pattern-Extraktion:** 2026-05-18
