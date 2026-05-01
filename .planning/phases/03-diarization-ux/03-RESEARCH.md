# Phase 3: Diarization-UX — Research

**Researched:** 2026-05-01
**Domain:** macOS-native Modell-Download-UX (FluidAudio Diarizer + SwiftUI Settings)
**Confidence:** HIGH

## Summary

FluidAudio 0.14.3 (currently pinned via `from: "0.6.0"` in `project.yml`, resolved exactly to **0.14.3** in `Package.resolved`) bietet **bereits eine vollständige Lösung für unser Phase-3-Problem**: `DiarizerModels.downloadIfNeeded(to:configuration:progressHandler:)` akzeptiert einen `progressHandler: @Sendable (DownloadProgress) -> Void` und gibt im Verlauf strukturierte Phase-Updates (`.listing` / `.downloading(completedFiles, totalFiles)` / `.compiling(modelName)`) plus `fractionCompleted: Double`. Die "wir müssen den Downloader selber bauen"-Annahme aus CONTEXT.md D-06 stimmt **nicht mehr** — sie ist ein Artefakt des opaken Aufrufs in `ParakeetClient:133` (`try await DiarizerModels.downloadIfNeeded()` ohne progressHandler). Die korrekte Lösung ist deutlich kleiner als ein eigener Downloader.

Der Diarizer-Pfad lebt unter `~/Library/Application Support/FluidAudio/Models/speaker-diarization/` (FluidAudio-Standard, **nicht** unter unserem `~/Library/Application Support/BlitzText/Models/Diarizer/`). Die installierten Dateien auf diesem Mac bestätigen das Layout: `pyannote_segmentation.mlmodelc/`, `wespeaker_v2.mlmodelc/`, plus drei Metadata-JSONs. Reale On-Disk-Größe nach Install: **13 MB** (nicht 80 MB) — die CONTEXT.md-Zahl bezieht sich vermutlich auf die ungekomprimierte HuggingFace-Repo-Größe inklusive `.mlpackage`-Quellen. Die Phase-3-UI-Strings sollten weiter "~80 MB" sagen (UI-SPEC ist locked und stimmt mit dem User-Mental-Modell der HF-Repo-Page überein), aber der Code muss nicht 80 MB pre-flight prüfen.

**Primary recommendation:** Keinen eigenen Downloader bauen. Stattdessen einen schlanken `@MainActor`-`DiarizerModelManager` schreiben, der `DiarizerModels.downloadIfNeeded(progressHandler:)` aufruft, die `DownloadProgress.fractionCompleted`-Werte in `@Published downloadProgress: Double?` + `etaSeconds: Double?` auf MainActor hopst, dabei einen sliding-window ETA-Estimator führt und die geladenen `DiarizerModels` cached (für direkte Übergabe an `DiarizerManager.initialize(models:)` in `ParakeetClient`). Damit fallen ~80 LOC neuer Code statt der ursprünglich geplanten ~200+ LOC Downloader-Reimplementierung an, und wir bleiben binärkompatibel mit FluidAudio-Updates.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Download-Trigger**
- **D-01:** Download startet **sofort bei Toggle-On** (`parakeetDiarization` flippt `false` → `true`). Nicht lazy bei nächster Aufnahme.
- **D-02:** Wenn das Modell bereits lokal vorhanden ist, ist Toggle-On ein No-Op-Download (Status: bereit) — kein erneutes Herunterladen.

**Toggle- & Block-Verhalten während Download**
- **D-03:** Während aktivem Download wird der **Toggle visuell durch ein Status-Label ersetzt** ("Lädt Diarizer-Modell …") inklusive Progress-Bar mit Prozent + ungefährer Restzeit.
- **D-04:** Kein Cancel während Download in v1.
- **D-05:** Bei `parakeetDiarization=true` aber fehlendem oder unvollständigem Modell zeigt der Block den Lade-/Fehler-State, nicht den aktiven Toggle.

**Progress-Quelle**
- **D-06:** Eigener Downloader analog `LocalModelManager` + `ModelDownloader.swift`. Persistenz unter `~/Library/Application Support/BlitzText/Models/Diarizer/`.
  - **Researcher-Anmerkung (FLAG):** Diese Decision sollte vom Planner **erneut diskutiert** werden, weil FluidAudio 0.14.3 bereits einen vollständig genügenden `progressHandler` exponiert. Siehe Sektion "Discrepancy Note" weiter unten. Trotzdem ist D-06 die locked Decision — wenn der Planner sie unverändert übernimmt, liefert dieses Dokument auch die nötigen URLs/Hashes für eine eigene Implementierung. Die alternative "wrap statt rewrite"-Variante ist als Anhang dokumentiert.
- **D-07:** Researcher-Aufgabe: konkrete URLs/Hashes der DiarizerModels-Pakete extrahieren — **erledigt, siehe "FluidAudio Internals" unten.**
- **D-08:** Restzeit-Schätzung via gleitendem Durchschnitt der Bytes/Sekunde.

**Fehler-Handling & Retry**
- **D-09:** Fehlerzustände in `DiarizerModelManager.lastError: String?` (`@Published`).
- **D-10:** Drei Fehler-Klassen (Netzwerk / Speicher / Unbekannt). User-getriggertes Retry, kein Auto-Backoff.
- **D-11:** Retry löscht partielle Dateien; kein Resume-Versuch in v1.
- **D-12:** Toggle bleibt logisch `true` bei Fehler — User-Intent erhalten.

**Pre-Warm beim App-Start**
- **D-13:** In `AppDelegate.bootstrap()`: bei `settings.parakeetDiarization == true` Hintergrund-Pre-Warm bzw. Hintergrund-Download mit Progress.
- **D-14:** Pre-Warm ist best-effort; App-Start blockiert nie.

**State-Machine**
- **D-15:** Neuer Manager `DiarizerModelManager` (`@MainActor`, `ObservableObject`) mit `state: DiarizerModelState` enum (`notInstalled`, `downloading(progress, etaSec)`, `installed`, `failed(message)`).
- **D-16:** `ParakeetClient.ensureLoaded()` konsultiert `DiarizerModelManager.isInstalled` statt selbst `downloadIfNeeded()` aufzurufen.

**Settings-UI-Struktur**
- **D-17:** Diarization-Block bleibt in `SettingsView.swift:380-388` (Lokal-Tab, Parakeet-Sektion). Kein eigener Tab.
- **D-18:** Vier Status-Zustände in 03-UI-SPEC.md spezifiziert.

### Claude's Discretion

- Genauer SF-Symbol für Status (UI-SPEC hat bereits gewählt: `arrow.down.circle` / `checkmark.circle.fill` / `exclamationmark.triangle.fill` — siehe 03-UI-SPEC.md).
- ETA-Algorithmus (gleitender Durchschnitt vs. instantane Rate) — **siehe Empfehlung in "ETA Strategy" unten.**
- Genauer Wortlaut der drei Fehler-Klassen — **bereits in 03-UI-SPEC.md fixiert.**
- Throttling der Progress-Updates (max 30 Hz) — **siehe Empfehlung "Throttling" unten.**

### Deferred Ideas (OUT OF SCOPE)

- Lösch-Button für Diarizer-Modell (nicht in Phase 3).
- Cancel-Button während Download (D-04).
- Auto-Retry mit Backoff (D-10).
- Download-Resume nach Abbruch (D-11).
- Modell-Version-Anzeige in UI.
- Sandbox-kompatibler Download-Pfad.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DIA-01 | Beim ersten Aktivieren von Diarization wird der ~80 MB-Modell-Download mit Progress (% + ungefähre Restzeit) im Settings-Tab angezeigt | FluidAudio 0.14.3 `DiarizerModels.downloadIfNeeded(progressHandler:)` liefert `DownloadProgress.fractionCompleted` ∈ [0,1] + `phase` (listing / downloading / compiling). ETA wird im Manager via sliding-window-Bytes-Rate geschätzt. UI-Spec State (b) deckt die Anzeige ab. |
| DIA-02 | Schlägt der Download fehl, sieht der Nutzer eine deutsche Fehlermeldung mit Retry-Button im Settings-Tab | Drei Fehler-Klassen (Netzwerk / Speicher / Unbekannt) klassifiziert via `URLError.Code` + `NSCocoaError.FileWriteOutOfSpaceError` + `POSIXError.ENOSPC`. UI-Spec State (d) liefert Layout. `manager.retry()` löscht partielle Dateien (FluidAudios eigener `clearModelCache(forRepo:directory:)`-Call) und ruft `start()` neu. |

## Project Constraints (from CLAUDE.md)

- **Swift 6, `SWIFT_STRICT_CONCURRENCY: minimal`** — bewusst, wegen CGEvent / AVAudioEngine / Keychain. Manager bleibt `@MainActor`; URLSession-Callbacks aus FluidAudio-Code laufen auf eigenem Thread und müssen via `Task { @MainActor in ... }` gehopst werden.
- **German UI strings, English code identifiers.** Manager-Properties / Methoden auf Englisch. Alle `lastError`-Strings + UI-Texte deutsch.
- **No external-cloud speaker ID** — bleibt erhalten; FluidAudio läuft on-device.
- **TranscriptionService protocol abstracts backends** — `DiarizerModelManager` ist kein Transcription-Backend selbst, sondern ein Lifecycle-Helper für `ParakeetClient`. Kein Protokoll-Touch nötig.
- **`@unchecked Sendable` für C-Bridge-Klassen** — Manager braucht das **nicht** (kein C-Boundary). Aber wenn wir partiell-Datei-Cleanup über `URLSessionDownloadDelegate` selbst machen würden (Variant B des Anhangs), bräuchten wir `@unchecked Sendable` für die Delegate-Klasse.
- **Keine neuen Logger** — alles über `Log.write(_)` (`BlitzText/App/Log.swift`).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Diarizer-Modell-Download (HTTP, partielle Dateien) | Network/Disk via FluidAudio (`DownloadUtils`) | — | FluidAudio 0.14.3 macht das bereits inkl. `progressHandler` und Cache-Clear-bei-Fehler. Wir konsumieren, nicht reimplementieren. |
| Download-Progress-Aggregation + ETA | App-State (`DiarizerModelManager`, MainActor) | — | UI-bound `@Published` State; ETA-Berechnung ist reine Funktion über Bytes-Timestamps. |
| State-Machine (`notInstalled` / `downloading` / `installed` / `failed`) | App-State (`DiarizerModelManager`) | — | Single source of truth für die UI-Switch in `DiarizerStatusBlock`. |
| Toggle-Side-Effect (`parakeetDiarization=true` → `manager.start()`) | App-State (`SettingsStore` `didSet` → Manager) | — | Setter-Hook in SettingsStore; Manager bleibt agnostisch wer ihn anstößt. |
| Pre-Warm beim App-Start | App-Lifecycle (`AppDelegate.bootstrap`) | App-State (Manager) | Bestehendes Pattern (analog `preloadLocalModelIfActive`). Hintergrund-Task, nicht blockierend. |
| Fehler-Klassifikation (Netzwerk / Speicher / Unbekannt) | App-State (`DiarizerModelManager`) | — | Reine Switch über `URLError.Code` + `NSCocoaError`. |
| UI-Render der vier States | View (`DiarizerStatusBlock` in `SettingsView`) | App-State (Manager als EnvironmentObject) | UI-SPEC fixiert das Layout; View liest Manager-State. |
| Diarizer-Konsum bei Aufnahme | Service (`ParakeetClient`) | App-State (Manager) | `ParakeetClient.ensureLoaded()` fragt `manager.isInstalled` und konsumiert die `DiarizerModels`-Instanz, die der Manager hält. |

## Standard Stack

### Core (alles bereits im Projekt)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FluidAudio | 0.14.3 | Diarizer-Modelle laden + Download mit Progress | [VERIFIED: GitHub API] Aktuelle Latest-Release `v0.14.3`, exakt das was Package.resolved hat. `DiarizerModels.downloadIfNeeded(progressHandler:)` ist seit ≥0.10 stable. Keine Alternative ist sinnvoll, weil ASR + Diarizer aus demselben Paket kommen müssen (Token-Timings → Speaker-Segments). |
| Foundation `URLSession` | macOS 26 system | (NICHT direkt — siehe "Don't Hand-Roll") | FluidAudio nutzt es intern; wir konsumieren nur den Progress-Callback. |
| Foundation `Date` + `Array` | macOS 26 system | Sliding-Window-ETA-Estimator | Reine Datenstruktur; kein library-grade ETA-Lib für 50 LOC nötig. |
| Combine | macOS 26 system | `@Published` Bridges in SwiftUI | Bestehendes Pattern (`LocalModelManager` ist die Vorlage). |
| `Log` (project-internal) | n/a | File-Logger | `BlitzText/App/Log.swift` — alle Subsysteme nutzen ihn. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `MainActor.run` / `Task { @MainActor in ... }` | system | Hop von FluidAudio-Worker-Thread → MainActor für `@Published`-Update | In jedem `progressHandler`-Body. Pattern wie in `LocalModelManager.swift:152-154`. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FluidAudio's `DiarizerModels.downloadIfNeeded(progressHandler:)` | Eigener `URLSessionDownloadDelegate`-basierter Downloader (D-06 wie ursprünglich gedacht) | Mehr Code (~150 LOC zusätzlich), eigene Resume-/Retry-Logik, eigenes Verzeichnis. **Vorteil:** Volle Kontrolle über Cancellation. **Nachteil:** Bei FluidAudio-Schema-Updates (z.B. neue Required-Files) muss manuell nachgezogen werden. **Empfehlung: nicht tun.** Variant B im Anhang dokumentiert wie es ginge, falls D-06 strikt durchgesetzt werden soll. |
| Eigener Pfad `~/Library/Application Support/BlitzText/Models/Diarizer/` | FluidAudios Default `~/Library/Application Support/FluidAudio/Models/speaker-diarization/` | Konsistenz mit unserem WhisperKit-Pfad. **Aber:** würde Doppelkopien erzeugen, weil FluidAudio sein eigenes Default-Dir benutzt, sobald `directory: nil` (was unser bestehender Code in `ParakeetClient:133` macht). **Empfehlung:** wir bleiben bei FluidAudio's Default-Pfad und passen das `Speicherort`-Label in der UI an. |

**Installation:**

Keine neue SPM-Dependency. FluidAudio 0.14.3 ist bereits im Projekt.

**Version verification:**
- `Package.resolved` zeigt `version: 0.14.3, revision: 00ea906c2089971bec767c4b4df38686aa7a9f9e` [VERIFIED: file read].
- GitHub API `https://api.github.com/repos/FluidInference/FluidAudio/releases/latest` → `tag_name: v0.14.3` [VERIFIED: curl 2026-05-01].
- Wir sind auf der Latest-Release. Pin in `project.yml` ist `from: "0.6.0"` (Range, nicht exact). Wenn in Phase 3 reproduzierbares Verhalten gefragt ist: in `project.yml` auf `exactVersion: "0.14.3"` umstellen — **nicht required**, aber empfohlen wenn Plan-Tests hängen bleiben sollen.

## FluidAudio Internals (D-07 Live-Inspection)

> Live-Source-Inspection: SPM-Checkout `~/Library/Developer/Xcode/DerivedData/BlitzText-dgthtajawdhsrxazqiknusbdlwdc/SourcePackages/checkouts/FluidAudio/`, FluidAudio v0.14.3.

### URL-Konstruktion

`ModelRegistry.resolveModel(_, _)` baut die HuggingFace-URLs (Source: `Sources/FluidAudio/ModelRegistry.swift:55-62`):

```swift
public static func resolveModel(_ repoPath: String, _ filePath: String) throws -> URL {
    let urlString = "\(baseURL)/\(repoPath)/resolve/main/\(filePath)"
    guard let url = URL(string: urlString) else { throw Error.invalidURL(urlString) }
    return url
}
```

mit `baseURL = "https://huggingface.co"` (oder ENV `REGISTRY_URL` / `MODEL_REGISTRY_URL` für Mirror).

### Diarizer-Repo-Definition

`Sources/FluidAudio/ModelNames.swift`:

```swift
case diarizer = "FluidInference/speaker-diarization-coreml"
// folderName auf Disk: "speaker-diarization" (-coreml entfernt, default-Branch line 199)
```

### Required Models (was wirklich heruntergeladen wird)

`Sources/FluidAudio/ModelNames.swift:208-218` (`ModelNames.Diarizer.requiredModels`):

```swift
public enum Diarizer {
    public static let segmentation = "pyannote_segmentation"
    public static let embedding = "wespeaker_v2"

    public static let segmentationFile = segmentation + ".mlmodelc"  // "pyannote_segmentation.mlmodelc"
    public static let embeddingFile = embedding + ".mlmodelc"        // "wespeaker_v2.mlmodelc"

    public static let requiredModels: Set<String> = [
        segmentationFile,
        embeddingFile,
    ]
}
```

### Konkrete Download-URL-Liste

Auflistungs-API (`Sources/FluidAudio/DownloadUtils.swift:307-369`) crawled rekursiv via HF Tree-API:

```
GET https://huggingface.co/api/models/FluidInference/speaker-diarization-coreml/tree/main
```

und filtert: alles unter `pyannote_segmentation/` + alles unter `wespeaker_v2/` + alle JSON/TXT-Files auf Top-Level. Dateien werden über

```
GET https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/main/<encoded-file-path>
```

geladen (DownloadUtils.swift:407-410). Die exakte Datei-Liste ist **nicht** im Source hardcoded — sie wird zur Runtime von HF zurückgegeben. Aber wir können live nachsehen:

**On-Disk Layout dieser Maschine** (nach erfolgtem Download, `~/Library/Application Support/FluidAudio/Models/speaker-diarization/`):

```
config.json                          (2 B  — Sentinel)
plda-parameters.json                 (89 KB)
xvector-transform.json               (177 KB)
pyannote_segmentation.mlmodelc/      (Verzeichnis, .mlmodelc-Bundle)
wespeaker_v2.mlmodelc/               (Verzeichnis, .mlmodelc-Bundle)
```

Gesamtgröße auf Disk: **13 MB** (`du -sh`). Das ist die kompilierte/gecachte Form. Die HF-Repo-Größe inkl. `.mlpackage`-Quellen liegt vermutlich bei den in CONTEXT.md-D-01 erwähnten ~80 MB; das ist Userwahrnehmung beim Laden der HF-Page. **Implementierung muss nicht 80 MB pre-flight prüfen** — `FluidAudio.downloadRepo` löst das transparent.

### `DiarizerModels`-Konstruktor-API

`Sources/FluidAudio/Diarizer/Core/DiarizerModels.swift:10-27` (struct + init):

```swift
public struct DiarizerModels: Sendable {
    public static let requiredModelNames = ModelNames.Diarizer.requiredModels
    public let segmentationModel: CoreMLDiarizer.SegmentationModel  // = MLModel
    public let embeddingModel: CoreMLDiarizer.EmbeddingModel        // = MLModel
    public let compilationDuration: TimeInterval

    init(segmentation: MLModel, embedding: MLModel, compilationDuration: TimeInterval = 0) {
        self.segmentationModel = segmentation
        self.embeddingModel = embedding
        self.compilationDuration = compilationDuration
    }
}
```

Der Init ist **internal** (default access, kein `public`) — wir können `DiarizerModels` nicht direkt selbst instanziieren. Wir müssen die statischen Factory-Methoden nutzen:

**Option A — Download mit Progress (empfohlen, DiarizerModels.swift:92-98):**

```swift
public static func downloadIfNeeded(
    to directory: URL? = nil,
    configuration: MLModelConfiguration? = nil,
    progressHandler: DownloadUtils.ProgressHandler? = nil
) async throws -> DiarizerModels
```

`progressHandler` ist `@Sendable (DownloadUtils.DownloadProgress) -> Void`. Wenn die Modelle bereits lokal liegen, ist der Aufruf ein **No-Op** (interner Pfad ruft direkt `loadModelsOnce` mit `allModelsExist == true`, springt dann auf 0.5-Progress + `.compiling`-Phase und liefert `DiarizerModels` zurück, DownloadUtils.swift:204-216).

**Option B — Pre-downloaded Files via `load(localSegmentationModel:localEmbeddingModel:)` (DiarizerModels.swift:120-140):**

```swift
public static func load(
    localSegmentationModel: URL,
    localEmbeddingModel: URL,
    configuration: MLModelConfiguration? = nil
) async throws -> DiarizerModels
```

Diese API existiert für den Fall "wir haben die Files irgendwo selbst hingelegt". Sie wäre der Hook für D-06's eigenen Downloader — **wenn** der Planner D-06 strikt umsetzen will. Der "Speicherort-Konflikt"-Risk aus CONTEXT.md ist damit gelöst: wir können beide URLs frei wählen.

### `DiarizerManager.initialize` (Konsument-Seite)

`Sources/FluidAudio/Diarizer/Core/DiarizerManager.swift:42`:

```swift
public func initialize(models: consuming DiarizerModels) {
    // ...
}
```

Heute in `ParakeetClient.swift:131-134`:

```swift
let diar = DiarizerManager(config: .default)
diar.initialize(models: try await DiarizerModels.downloadIfNeeded())
self.diarizer = diar
```

Ersetzt durch:

```swift
guard let models = await diarizerModelManager.modelsIfInstalled else {
    self.diarizer = nil  // Fallback auf reines ASR
    return
}
let diar = DiarizerManager(config: .default)
diar.initialize(models: models)
self.diarizer = diar
```

### `DownloadProgress`-Snapshot

`Sources/FluidAudio/DownloadUtils.swift:77-103`:

```swift
public enum DownloadPhase: Sendable {
    case listing
    case downloading(completedFiles: Int, totalFiles: Int)
    case compiling(modelName: String)
}

public struct DownloadProgress: Sendable {
    public let fractionCompleted: Double  // [0, 1]
    public let phase: DownloadPhase
}

public typealias ProgressHandler = @Sendable (DownloadProgress) -> Void
```

Wichtig: `fractionCompleted` ist **byte-weighted** für die Download-Phase (occupies 0.0–0.5 of overall) und springt dann in `.compiling` (0.5–1.0). Heißt: Bei 100 % Bytes-Download steht `fractionCompleted = 0.5`. Compile-Phase füllt die zweite Hälfte auf. Das ist **sinnvoll für unsere UI**, weil CoreML-Compile auf Apple Silicon nicht trivial ist (~2-10 s je Modell). User sieht "Lädt … 75 %" und das umfasst beides.

**Implication für ETA-Berechnung:** Die Bytes-Rate kommt nur in der ersten Hälfte vor. ETA muss `fractionCompleted * 2` als Bytes-Anteil interpretieren, oder besser: wir berechnen ETA über `fractionCompleted` direkt (linear-extrapoliert) und akzeptieren, dass die Restzeit-Schätzung am Übergang Download→Compile leicht springt. Das ist OK; UI-SPEC erlaubt "noch ~30 s"-Granularität.

### Discrepancy Note (für Planner)

CONTEXT.md D-06 sagt "Eigener Downloader analog `LocalModelManager` + `ModelDownloader.swift`. Wir umgehen `DiarizerModels.downloadIfNeeded()` und ziehen die FluidAudio-Modelldateien selbst per `URLSession`."

Diese Decision wurde vor der Live-Inspection gefällt. Nach Inspection: **`DiarizerModels.downloadIfNeeded(progressHandler:)` exponiert genau das, was wir brauchen.** Variant A (FluidAudio-progressHandler-wrap) ist meine starke Empfehlung. Variant B (eigener Downloader) wird im Anhang skizziert für den Fall, dass D-06 strikt durchgehalten wird — **bitte vor Planning kurz mit User abklären.**

## Architecture Patterns

### System Architecture Diagram

```
                                  User-Interaktion
                                        │
                  ┌─────────────────────┴─────────────────────┐
                  │                                           │
   App-Start (AppDelegate.bootstrap)              Toggle-Flip in SettingsView
                  │                                           │
                  │ if settings.parakeetDiarization=true      │ parakeetDiarization.didSet
                  │                                           │ false → true
                  │   manager.prewarm() ─ best-effort         │
                  │                                           │ manager.start()
                  └─────────────────────┬─────────────────────┘
                                        │
                                        ▼
                         ┌─────────────────────────────────┐
                         │     DiarizerModelManager        │
                         │     (@MainActor,                │
                         │      ObservableObject)          │
                         │                                 │
                         │  state: DiarizerModelState      │
                         │  ├─ notInstalled                │
                         │  ├─ downloading(progress, eta)  │
                         │  ├─ installed                   │
                         │  └─ failed(message)             │
                         │                                 │
                         │  cachedModels: DiarizerModels?  │
                         │  etaEstimator: SlidingWindow    │
                         └────────────┬────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
    DiarizerModels                                   SwiftUI: DiarizerStatusBlock
    .downloadIfNeeded(             ParakeetClient    (4 States, switch über
       progressHandler:            .ensureLoaded()    manager.state)
       { progress in
         hop @MainActor →
         Manager.update(progress) }
    )
              │
              │ FluidAudio internal:
              │ DownloadUtils.downloadRepo(.diarizer)
              │ → HF API listing, GET resolve URLs
              │ → ~/Library/Application Support/FluidAudio/Models/speaker-diarization/
              ▼
    HuggingFace (huggingface.co/FluidInference/speaker-diarization-coreml)
       ├─ pyannote_segmentation.mlmodelc/
       ├─ wespeaker_v2.mlmodelc/
       └─ {plda-parameters,xvector-transform,config}.json
```

### Recommended Project Structure

```
BlitzText/Transcription/
├── DiarizerModelManager.swift   # NEW — @MainActor lifecycle manager
├── DiarizerModelState.swift     # NEW — public enum used in UI switch
│                                #       (or nested in DiarizerModelManager)
├── ETAEstimator.swift           # NEW — pure-data, sliding-window bytes/sec
├── ParakeetClient.swift         # MODIFIED — accepts DiarizerModelManager dependency
├── LocalModelManager.swift      # UNCHANGED
└── ModelDownloader.swift        # UNCHANGED (Whisper-only)

BlitzText/Settings/
├── SettingsView.swift           # MODIFIED — Diarization-Block durch DiarizerStatusBlock ersetzt
├── DiarizerStatusBlock.swift    # NEW — private struct: View, switch über manager.state
└── SettingsStore.swift          # MODIFIED — parakeetDiarization didSet-Hook auf manager

BlitzText/App/
└── AppDelegate.swift            # MODIFIED — bootstrap instanziiert DiarizerModelManager
                                 #            + prewarmDiarizerIfActive
BlitzTextTests/
├── Diarizer/
│   ├── DiarizerModelManagerTests.swift   # NEW — 4-state transitions
│   └── ETAEstimatorTests.swift           # NEW — pure data
└── Support/
    └── FakeDiarizerLoader.swift          # NEW — Protocol-Seam für Manager
```

### Pattern 1: `@MainActor` Lifecycle Manager mit `@Published` State

**What:** Bestehendes Pattern aus `LocalModelManager`. `final class … @MainActor : ObservableObject` mit `@Published`-Properties für UI, internem `Task<Void, Never>?` für laufende Downloads, `func start()` / `func retry()`-API.

**When to use:** Immer wenn ein langlaufender Download/Load-Lifecycle für die UI sichtbar werden soll.

**Example (Skelett):**

```swift
// Source: BlitzText/Transcription/LocalModelManager.swift:138-168 (Vorlage)
//         + DiarizerModels-API aus FluidAudio 0.14.3 inspection
import Foundation
import Combine
import FluidAudio

enum DiarizerModelState: Equatable {
    case notInstalled
    case downloading(progress: Double, etaSeconds: Double?)
    case installed
    case failed(message: String)
}

@MainActor
final class DiarizerModelManager: ObservableObject {
    @Published private(set) var state: DiarizerModelState = .notInstalled
    @Published private(set) var lastError: String?

    /// Convenience für UI: schnelle %-Anzeige ohne enum-unwrap.
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var etaSeconds: Double?

    private var loadingTask: Task<Void, Never>?
    private var cachedModels: DiarizerModels?
    private let etaEstimator = ETAEstimator(windowSeconds: 5)

    /// Sync-Check ohne Inferenz: prüft Datei-Existenz.
    var isInstalled: Bool {
        let dir = FluidAudio.MLModelConfigurationUtils
            .defaultModelsDirectory(for: .diarizer)
        let seg = dir.appendingPathComponent("pyannote_segmentation.mlmodelc")
        let emb = dir.appendingPathComponent("wespeaker_v2.mlmodelc")
        let fm = FileManager.default
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: seg.path, isDirectory: &isDir) && isDir.boolValue
            && fm.fileExists(atPath: emb.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// MainActor-safe accessor für ParakeetClient.
    var modelsIfInstalled: DiarizerModels? { cachedModels }

    func start() {
        // D-02: bereits installiert? cache laden, fertig.
        if isInstalled, cachedModels != nil {
            state = .installed
            return
        }
        guard loadingTask == nil else { return }  // Idempotent
        beginDownload()
    }

    func retry() {
        // D-11: partielle Dateien löschen
        let dir = FluidAudio.MLModelConfigurationUtils
            .defaultModelsDirectory()  // …/FluidAudio/Models/
        FluidAudio.DownloadUtils.clearModelCache(forRepo: .diarizer, directory: dir)
        cachedModels = nil
        lastError = nil
        beginDownload()
    }

    /// Pre-Warm beim App-Start (D-13/D-14).
    func prewarm() {
        if isInstalled {
            // CoreML-Init im Hintergrund — laden, aber nicht UI-blocken
            beginDownload()  // ist No-Op-Download wenn alles da ist; lädt nur in MLModel
        } else {
            beginDownload()  // echter Download
        }
    }

    private func beginDownload() {
        etaEstimator.reset()
        state = .downloading(progress: 0, etaSeconds: nil)
        downloadProgress = 0
        etaSeconds = nil
        lastError = nil

        let task = Task { [weak self] in
            do {
                let models = try await DiarizerModels.downloadIfNeeded(
                    progressHandler: { progress in
                        // Worker-Thread → MainActor
                        Task { @MainActor [weak self] in
                            self?.handleProgress(progress)
                        }
                    }
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.cachedModels = models
                    self.state = .installed
                    self.downloadProgress = nil
                    self.etaSeconds = nil
                    self.loadingTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let msg = Self.classify(error)
                    self.lastError = msg
                    self.state = .failed(message: msg)
                    self.downloadProgress = nil
                    self.etaSeconds = nil
                    self.loadingTask = nil
                    Log.write("DiarizerModelManager: Download fehlgeschlagen — \(error.localizedDescription) → '\(msg)'")
                }
            }
        }
        loadingTask = task
    }

    private func handleProgress(_ p: DownloadUtils.DownloadProgress) {
        // Throttle: max 10 Hz UI-Update (siehe "Throttling" unten)
        let now = Date()
        let frac = p.fractionCompleted
        let eta = etaEstimator.tick(fraction: frac, now: now)
        downloadProgress = frac
        etaSeconds = eta
        state = .downloading(progress: frac, etaSeconds: eta)
    }

    private static func classify(_ error: Error) -> String {
        // siehe "Error Classification" unten
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .networkConnectionLost,
                 .dnsLookupFailed, .secureConnectionFailed:
                return "Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut."
            case .dataNotAllowed:
                return "Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht)."
            default: break
            }
        }
        let nsErr = error as NSError
        if nsErr.domain == NSCocoaErrorDomain
            && nsErr.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return "Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht)."
        }
        if nsErr.domain == NSPOSIXErrorDomain && nsErr.code == Int(POSIXError.ENOSPC.rawValue) {
            return "Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht)."
        }
        return "Download fehlgeschlagen. Versuch es später erneut — wenn das Problem bleibt, schau in das Log unter ~/Library/Logs/BlitzText.log."
    }
}
```

### Pattern 2: Setter-Hook in `SettingsStore` für Toggle-Side-Effect

**What:** `parakeetDiarization` ist `@Published var`. Ein `didSet` direkt darauf läuft auch beim `load()` — das ist ein Reentrancy-Problem (würde Download beim App-Start triggern, ohne User-Toggle).

**When to use:** Hier — Side-Effect nur bei User-getriggertem Flip, nicht beim initialen Load.

**Example:**

```swift
// In SettingsStore — neuer Setter-Hook
@Published var parakeetDiarization: Bool = false {
    didSet {
        // Skip wenn wir gerade aus JSON laden (load() setzt isLoading=true)
        guard !isLoading, oldValue != parakeetDiarization else { return }
        // Kein direkter Manager-Zugriff hier, weil SettingsStore keinen Manager kennt.
        // Stattdessen Notification-Bridge:
        NotificationCenter.default.post(
            name: .parakeetDiarizationDidChange,
            object: nil,
            userInfo: ["enabled": parakeetDiarization]
        )
    }
}
```

**Alternative (saubere DI):** AppDelegate observed `settingsStore.$parakeetDiarization.dropFirst()` (skipt initialen Wert) und ruft `manager.start()` bei `true` auf. `dropFirst()` ist robuster als ein `isLoading`-Flag. Bestehende Combine-Pipeline in `SettingsStore.init` nutzt bereits `objectWillChange.debounce` — wir reihen uns ein.

```swift
// In AppDelegate.bootstrap — nach Manager-Init
settingsStore.$parakeetDiarization
    .removeDuplicates()
    .dropFirst()  // initialen JSON-Load-Wert ignorieren
    .sink { [weak self] enabled in
        if enabled {
            self?.diarizerModelManager.start()
        }
        // bei false: Manager macht nichts — Modell bleibt auf Disk (D-deferred)
    }
    .store(in: &cancellables)
```

### Anti-Patterns to Avoid

- **Direkte `URLSessionDownloadDelegate`-Implementierung:** Auch wenn das die "klassische" Swift-Antwort auf "Download mit Progress" ist — in unserem Fall hieße das, FluidAudios HF-Auflistungs-Logik (rekursive Tree-API + Pattern-Filter) zu reimplementieren. Wir würden die `Repo`-/`ModelNames`-Konstanten zur Build-Zeit einfrieren. Brüche bei FluidAudio-Updates wären unsichtbar bis zur ersten Aufnahme. **Don't.**
- **Ein eigenes Modell-Verzeichnis unter `BlitzText/Models/Diarizer/`:** Würde Doppelkopien erzeugen (FluidAudio's Default ist hardcoded `~/Library/Application Support/FluidAudio/Models/speaker-diarization/`). Selbst wenn wir `directory:` an `downloadIfNeeded` übergeben, würde der Loader von `DiarizerManager.initialize` nichts an unserem Custom-Pfad ändern, solange `directory` nicht **konsistent** überall mitgegeben wird. **Don't.**
- **Cancel-Logik einbauen:** D-04 verbietet es. Manager hält den `Task` zwar, aber `task.cancel()` exponiert kein API-Surface. (FluidAudio's `downloadRepo` reagiert auf `Task.cancel` via `try await sharedSession.data` — das ist best-effort, aber wir versprechen es nicht.)
- **Pre-Flight-Disk-Space-Check:** ~80 MB pre-checken via `URLResourceValues.volumeAvailableCapacityForImportantUsage` würde nur eine zusätzliche failure-mode mit eigenem deutschen Text auslösen. Stattdessen klassifizieren wir den `ENOSPC`-Fehler **am Fehlerobjekt**, wenn er auftritt. UI-SPEC erlaubt das genau so.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HuggingFace-Repo-Auflistung | URLSession + JSON-Decoding der HF Tree-API | `FluidAudio.DownloadUtils.downloadRepo(.diarizer, …)` (intern via `DiarizerModels.downloadIfNeeded`) | Rate-Limit-Handling (429/503), Retry-on-corrupted-cache, HTML-Error-Detection, Subdirectory-Encoding — alles drin. |
| `.mlmodelc`-Bundle-Validation | `isDirectory`-Check + `coremldata.bin`-Existenz | FluidAudio macht es in `loadModelsOnce` (DownloadUtils.swift:234-256) | Falsch validierte CoreML-Bundles crashen erst beim `MLModel(contentsOf:)`-Call. FluidAudio wirft vorher `CocoaError.fileReadCorruptFile`. |
| Partial-File-Cleanup vor Retry | `FileManager.removeItem` + Pfad-Konstanten selber pflegen | `FluidAudio.DownloadUtils.clearModelCache(forRepo: .diarizer, directory: …)` | Repo-Folder-Naming kann sich ändern; FluidAudio kapselt's. |
| ETA über Bytes-pro-Sekunde | `URLSessionDownloadDelegate.didWriteData` plus Math | Sliding-Window-Estimator über `DownloadProgress.fractionCompleted` (siehe "ETA Strategy" unten) | `fractionCompleted` ist eh schon byte-weighted (DownloadUtils:418-431). Wir extrapolieren linear. ~30 LOC. |
| Pyannote/wespeaker-Embedding-Code | C/Python-Bindings | `DiarizerManager.performCompleteDiarization(_)` (bereits in ParakeetClient verwendet) | FluidAudio kapselt CoreML-Inferenz vollständig. Phase 4 wird Sprecher-Profile darüber bauen. |

**Key insight:** Die ganze Phase ist 80 % UI/State-Management und 20 % FluidAudio-API-Konsum. Jede Codezeile, die nicht UI- oder State-Code ist, hat hohe Wahrscheinlichkeit, ein bestehendes FluidAudio-API-Surface zu duplizieren.

## ETA Strategy (D-08 Discretion)

**Empfehlung: Sliding-Window über die letzten N Sekunden, mit linearer Extrapolation.**

`DownloadProgress.fractionCompleted` ist bereits byte-gewichtet im Download-Bereich [0, 0.5] und springt dann in Compile-Bereich [0.5, 1.0]. Wir können also komplett über `fractionCompleted` arbeiten ohne Bytes zu kennen.

```swift
struct ETAEstimator {
    private struct Sample { let time: Date; let fraction: Double }
    private var samples: [Sample] = []
    private let windowSeconds: TimeInterval

    init(windowSeconds: TimeInterval = 5.0) {
        self.windowSeconds = windowSeconds
    }

    mutating func reset() { samples.removeAll() }

    /// Liefert geschätzte Restsekunden, oder `nil` wenn noch nicht genug Datenpunkte.
    mutating func tick(fraction: Double, now: Date = Date()) -> Double? {
        samples.append(.init(time: now, fraction: fraction))
        // Drop alte Samples außerhalb des Fensters
        let cutoff = now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.time < cutoff }

        guard let first = samples.first, samples.count >= 2 else {
            return nil  // UI: "Geschwindigkeit wird ermittelt …"
        }
        let elapsed = now.timeIntervalSince(first.time)
        let progressDelta = fraction - first.fraction
        guard elapsed > 0.5, progressDelta > 0.001 else { return nil }
        let rate = progressDelta / elapsed  // Anteil pro Sekunde
        let remaining = max(0, 1.0 - fraction)
        return remaining / rate
    }
}
```

**Warum N=5 s:** Faustregel aus `Sources/FluidAudio/DownloadUtils.swift`-Verhalten beim Probelauf: HF-Mirrors haben 0.5-1 s Bursts; ein 1-s-Fenster wäre zu zappelig. 5 s ist genug zum Glätten ohne dass die ETA-Anzeige nach Recovery (z.B. WLAN-Hiccup) >10 s alt aussieht. Tunable Constant — Manager exponiert `init(etaWindow: TimeInterval = 5)` für Tests.

**Alternative (verworfen):** Exponential moving average. Vorteil: keine Sample-Liste. Nachteil: Anlaufphase-Verhalten ist nicht-trivial zu testen, und der Sprung Download→Compile (50 %→52 % nach 0.1 s, dann 90 %→100 % in 5 s) lässt EMA ähnlich häufig springen. Gleitender Window ist konzeptuell einfacher und besser testbar.

**Edge-Cases:**
- Erste 1-2 s: `nil` zurückgeben → UI zeigt "Geschwindigkeit wird ermittelt …" (UI-SPEC).
- Compile-Phase (`fractionCompleted ≥ 0.5`): rate stagniert oft bei 0 zwischen Modellen → ETA wird unbegrenzt. **Mitigation:** Wenn `progressDelta < 0.001`, gib letzten validen ETA zurück oder `nil` — beides UI-konform.
- Sample-Liste-Größe: bei 10 Hz Updates × 5 s Fenster → max ~50 Samples. Kein Problem.

## Throttling (Discretion)

**Empfehlung: 10 Hz UI-Update-Rate via Combine `throttle`.**

UI-SPEC sagt "max 30 Hz, gefühlt flüssig". 10 Hz ist deutlich darunter und reicht für Progress-Bar+ETA-Text. Implementierung: in der `Manager.handleProgress`-Funktion **nicht** throtteln (sonst verlieren wir den finalen 100 %-Tick), sondern Combine-Side über

```swift
$downloadProgress
    .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
```

falls ein dedicated `@Published` für die View gebraucht wird. **Aber:** SwiftUI-Views, die direkt `manager.downloadProgress` lesen, rendern eh nur dann neu, wenn der `objectWillChange`-Pulse durchkommt — und der bouncest sich an SwiftUI's eigenem 60-Hz-Loop. **In der Praxis ist kein expliziter Throttle nötig.** Recommendation: erst messen, dann throttlen. Initialer Plan kann throttle weglassen.

## Error Classification (D-10)

Mapping von Apple-Error-Domains auf die drei UI-Texte (UI-SPEC fixiert die exakten deutschen Strings):

```swift
private static func classify(_ error: Error) -> String {
    // Klasse: Netzwerk
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .secureConnectionFailed,
             .resourceUnavailable,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:  // dataNotAllowed kann sowohl "no cellular" als auch "user blocked" sein → Netzwerk
            return "Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut."
        default:
            break
        }
    }

    // Klasse: Speicher
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain
        && ns.code == CocoaError.Code.fileWriteOutOfSpace.rawValue {
        return "Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht)."
    }
    if ns.domain == NSPOSIXErrorDomain
        && ns.code == Int(POSIXError.ENOSPC.rawValue) {
        return "Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht)."
    }
    // FluidAudio's eigene Errors
    if let hf = error as? DownloadUtils.HuggingFaceDownloadError {
        switch hf {
        case .rateLimited, .invalidResponse, .htmlErrorResponse, .downloadFailed:
            // Alles HF-Server- oder Connection-Probleme → Netzwerk-Klasse
            return "Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut."
        case .modelNotFound:
            // Server hat das Modell nicht ausgeliefert → unbekannt
            return "Download fehlgeschlagen. Versuch es später erneut — wenn das Problem bleibt, schau in das Log unter ~/Library/Logs/BlitzText.log."
        }
    }

    // Default: Unbekannt
    return "Download fehlgeschlagen. Versuch es später erneut — wenn das Problem bleibt, schau in das Log unter ~/Library/Logs/BlitzText.log."
}
```

[VERIFIED: Apple Foundation docs] `URLError.Code` enum values are defined in `URLError.swift` (Foundation framework). `CocoaError.fileWriteOutOfSpace` is the canonical disk-full error on macOS for `FileManager`/`URLSession.download(...)`-Pfad. `POSIXError.ENOSPC` rundet ab für seltene low-level filesystem-API-Pfade.

**Warning:** `URLError.dataNotAllowed` ist mehrdeutig (kann auch "User hat Cellular für die App blockiert" heißen). Auf macOS 26 ist Cellular nicht relevant — bleibt Netzwerk-Klasse. [ASSUMED — bleibt locked durch UI-SPEC, kein User-Confirmation nötig.]

## Pre-Warm Detection (D-13/D-14)

**Empfehlung: Pure Datei-Existenz-Check, kein Hash.**

```swift
var isInstalled: Bool {
    let dir = MLModelConfigurationUtils.defaultModelsDirectory(for: .diarizer)
    let seg = dir.appendingPathComponent("pyannote_segmentation.mlmodelc")
    let emb = dir.appendingPathComponent("wespeaker_v2.mlmodelc")
    let fm = FileManager.default
    var isDir: ObjCBool = false
    return fm.fileExists(atPath: seg.path, isDirectory: &isDir) && isDir.boolValue
        && fm.fileExists(atPath: emb.path, isDirectory: &isDir) && isDir.boolValue
}
```

**Warum kein Hash:**
- HF-Datei-Hash ist nicht im Source hardcoded (FluidAudio würde sich lock-stepped halten müssen mit jedem HF-Push).
- FluidAudio's eigene `loadModelsOnce` nutzt nur Datei-Existenz + `coremldata.bin`-Existenz im Bundle (DownloadUtils:204-260). Wenn das gut genug für FluidAudio ist, ist es gut genug für uns.
- Bei Korruption greift FluidAudio's eigene Recovery (`first load failed → delete cache → re-download`, DownloadUtils:130-153). Der erste echte Inferenz-Aufruf in `ParakeetClient.transcribe` würde den Re-Download triggern. **Aber:** Das wäre für den User unsichtbar (kein UI-Update zwischen Pre-Warm-OK und nächster Aufnahme). Akzeptables Risiko in Phase 3.

**Pre-Warm-Pattern (analog `preloadLocalModelIfActive`):**

```swift
// In AppDelegate.bootstrap, nach diarizerModelManager init
if settingsStore.parakeetDiarization {
    // Best-effort, nicht-blockierend (D-14)
    diarizerModelManager.prewarm()
}
```

`prewarm()` im Manager:
- Wenn `isInstalled == true` und `cachedModels == nil` → Hintergrund-`Task` der `DiarizerModels.load(localSegmentationModel:localEmbeddingModel:)` (oder `downloadIfNeeded` als No-Op-Path) aufruft, um die `MLModel`-Objekte zu compilen und in `cachedModels` zu cachen. UI zeigt nichts (falls nicht offen), Settings-Tab beim Öffnen direkt im (c)-State.
- Wenn `isInstalled == false` → echter Hintergrund-Download. UI zeigt beim Öffnen (b)-State mit aktuellem Progress. Genau das verlangt UI-SPEC.

## Race Condition: Toggle off während Download (Question 9)

**Frage:** Was, wenn `parakeetDiarization` während aktivem Download von `true` → `false` flippt (z.B. via `defaults write` oder anderer Codepfad)?

**Empfehlung:** Manager **ignoriert** den Flip. Keine Cancel-Logik in v1.

**Rationale:**
- D-04 verbietet Cancel-UI. Der Toggle ist während State (b) **gar nicht gerendert** (UI-SPEC State (b) explizit). Der Race kann also nicht aus der UI kommen.
- Ein `defaults write` während des Downloads ist ein Power-User-Edge-Case, der außerhalb des Phase-3-Scope liegt.
- Wenn der Download durchläuft, zeigt der Settings-Tab beim Öffnen (a) mit Toggle-off + Modell-vorhanden-Confirmation. Modell ist installiert, aber Toggle ist off → User-Intent wird respektiert beim nächsten Aufnahme-Cycle (`ParakeetClient.ensureLoaded` lädt den `DiarizerManager` nicht, weil `settings.parakeetDiarization == false`). **Korrektes Verhalten.**

**Konsequenz für `DiarizerModelManager`:** Kein `cancel()`-API. Setter-Hook in `SettingsStore` (siehe Pattern 2) ignoriert `false`-Übergänge — er triggert nur bei `false → true`. `dropFirst()` + `removeDuplicates()` reichen.

## Testability (Question 10)

**Seam: Protocol-based Loader-DI im Manager-Init.**

Bestehendes Pattern aus Phase 2: `RecorderProtocol` (BlitzText/Audio/AudioRecorder.swift), `ModeProcessor.init` mit optional-defaulted DI.

```swift
/// Test-Seam für DiarizerModelManager.
/// Production-Default ist `FluidAudioDiarizerLoader`; Tests injizieren `FakeDiarizerLoader`.
protocol DiarizerLoaderProtocol: Sendable {
    func downloadIfNeeded(
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> DiarizerModels
    func isInstalled() -> Bool
    func clearCache()
}

struct FluidAudioDiarizerLoader: DiarizerLoaderProtocol {
    func downloadIfNeeded(
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> DiarizerModels {
        try await DiarizerModels.downloadIfNeeded(
            progressHandler: progressHandler.map { ph in
                { (p: DownloadUtils.DownloadProgress) in ph(p.fractionCompleted) }
            }
        )
    }
    func isInstalled() -> Bool {
        // Datei-Existenz-Check wie oben
    }
    func clearCache() {
        let dir = MLModelConfigurationUtils.defaultModelsDirectory()
        DownloadUtils.clearModelCache(forRepo: .diarizer, directory: dir)
    }
}

@MainActor
final class DiarizerModelManager: ObservableObject {
    private let loader: DiarizerLoaderProtocol

    init(loader: DiarizerLoaderProtocol = FluidAudioDiarizerLoader()) {
        self.loader = loader
    }
    // ... Rest wie oben
}
```

In Tests:

```swift
// BlitzTextTests/Support/FakeDiarizerLoader.swift
final class FakeDiarizerLoader: DiarizerLoaderProtocol, @unchecked Sendable {
    var installed: Bool = false
    var failure: Error?
    var progressTicks: [Double] = [0.1, 0.5, 0.9, 1.0]
    func isInstalled() -> Bool { installed }
    func clearCache() { installed = false }
    func downloadIfNeeded(progressHandler: (@Sendable (Double) -> Void)?) async throws -> DiarizerModels {
        for tick in progressTicks {
            progressHandler?(tick)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if let failure { throw failure }
        installed = true
        // Test gibt einen Fake-DiarizerModels-Wert nicht zurück, weil der Init internal ist.
        // Stattdessen: Tests prüfen state-Transitionen + lastError, nicht die DiarizerModels selbst.
        // → Manager braucht für Tests einen "test mode", der den DiarizerModels-Cache überspringt.
        throw NSError(domain: "FakeDiarizerLoader", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: "Test-Stub: kein echtes Modell"])
    }
}
```

**Caveat:** `DiarizerModels`-Init ist internal (siehe FluidAudio Internals). Tests können kein echtes `DiarizerModels`-Objekt herstellen. Mitigation:
1. Tests fokussieren auf State-Transitionen + Error-Klassifikation, nicht auf den `cachedModels`-Wert.
2. Manager bekommt einen `cachedModelsForTesting: Any?` Hook nur unter `#if DEBUG`. Oder:
3. Den `installed`-State im Manager via Datei-Existenz triggern statt via `cachedModels != nil`. Tests legen Fake-Verzeichnisse an.

**Recommendation:** Variante 1 reicht für Phase 3. Tests prüfen `state == .downloading(_, _)` → `.failed` und `state == .downloading` mit korrekten Progress-Ticks. `ParakeetClient`-Konsum ist nicht Phase-3-Test-Scope (das wäre Phase 4 mit Speaker-Profile-Matching-Tests).

**Konkrete Test-Cases (für die Plan-Phase):**

| Test | Setup | Assert |
|------|-------|--------|
| `start_when_not_installed_transitions_to_downloading` | `loader.installed=false`, `loader.progressTicks=[0.1,0.5,1.0]` | `state` durchläuft `.downloading(0.1,_)` → `.downloading(0.5,_)` → `.downloading(1.0,_)` → `.failed` (wegen FakeDiarizerLoader-Throw) |
| `start_when_already_installed_skips_download` | `loader.installed=true`, `cachedModels` mocked | `state == .installed`, `loader.downloadCallCount == 0` |
| `retry_clears_cache_and_restarts` | manager im `.failed`-State | `loader.clearCacheCallCount == 1`, dann `state == .downloading` |
| `error_classification_network` | `loader.failure = URLError(.notConnectedToInternet)` | `lastError == "Verbindung fehlgeschlagen. …"` |
| `error_classification_storage_cocoa` | `loader.failure = CocoaError(.fileWriteOutOfSpace)` | `lastError == "Nicht genug Speicherplatz …"` |
| `error_classification_storage_posix` | `loader.failure = NSError(domain: NSPOSIXErrorDomain, code: ENOSPC)` | `lastError == "Nicht genug Speicherplatz …"` |
| `error_classification_unknown` | `loader.failure = NSError(domain: "Custom", code: 42)` | `lastError == "Download fehlgeschlagen. …"` |
| `eta_estimator_first_seconds_returns_nil` | < 2 Datenpunkte oder elapsed < 0.5 s | `eta == nil` |
| `eta_estimator_steady_progress_returns_seconds` | 5 Datenpunkte, 0→0.5 in 5 s | `eta ≈ 5.0` (linear-extrapoliert: 50 % bleiben, 0.1/s rate) |
| `eta_estimator_resets_on_reset` | nach Wert ticken, `reset()`, dann tick | erster Wert nach Reset = `nil` |

`ETAEstimator` ist pure-data → kein MainActor, eigene Test-Suite ohne Manager.

## Common Pitfalls

### Pitfall 1: FluidAudio-Default-Pfad vs. eigener Pfad

**What goes wrong:** Wenn wir `directory:` an `downloadIfNeeded` übergeben, aber `DiarizerManager.initialize` später ohne directory aufgerufen wird, lädt FluidAudio implizit aus dem Default-Pfad. Wir hätten zwei Kopien.

**Why it happens:** Der `directory: nil`-Default in `defaultModelsDirectory()` ist das Standard-Verhalten bei jedem FluidAudio-Aufruf, der den Parameter weglässt.

**How to avoid:** Wir lassen `directory:` weg und akzeptieren FluidAudios Default. Damit sind alle Pfade konsistent und `isInstalled` muss nur den einen Pfad prüfen.

**Warning signs:** `du -sh ~/Library/Application\ Support/FluidAudio/Models/` UND `du -sh ~/Library/Application\ Support/BlitzText/Models/Diarizer/` zeigen beide >0.

### Pitfall 2: Initial-Load-Trigger durch `parakeetDiarization` `didSet`

**What goes wrong:** Wenn `SettingsStore.load()` ein gespeichertes `parakeetDiarization=true` setzt, würde ein naives `didSet` den `manager.start()` triggern — beim App-Start, ohne User-Trigger, parallel zum Pre-Warm-Pfad. Doppel-Download.

**Why it happens:** Swift's `didSet` läuft auch beim ersten Set in `init`/`load`.

**How to avoid:** Setter-Hook **außerhalb** von `SettingsStore` aufhängen, via `settingsStore.$parakeetDiarization.dropFirst().sink { ... }`. Skipt den initialen Load-Wert. Pattern 2 oben zeigt's.

**Warning signs:** Log zeigt `DiarizerModelManager: start()` zweimal kurz nach App-Start.

### Pitfall 3: Compile-Phase wird als "Hängen" wahrgenommen

**What goes wrong:** Nach dem Download (fractionCompleted=0.5) läuft die CoreML-Compile-Phase. Auf langsamen Geräten kann das 5-15 s dauern. UI zeigt "Lädt … 50 %" für gefühlt zu lange.

**Why it happens:** `fractionCompleted` springt während `.compiling` nur an Modell-Grenzen (50% → 75% nach erstem Modell, → 100% nach zweitem). Zwei Modelle = nur ein Sprung.

**How to avoid:** Wenn `phase == .compiling`, Status-Label-Subtext anpassen: "Lädt Diarizer-Modell — 75 % · wird kompiliert …" statt ETA. Tunable in der UI-Schicht; UI-SPEC erlaubt es als minor-Variation des "Detail"-Texts. Falls Phase-3-Plan das nicht aufnehmen will: Default ist OK, weil 5-15 s im Phase-3-Erfolgsmaßstab "sichtbar" reicht.

**Warning signs:** Wave-2-Test mit M1-Mac zeigt 7 s "stuck at 50 %"-Wahrnehmung.

### Pitfall 4: `Task` Race bei wiederholtem `start()`

**What goes wrong:** Toggle-on → Settings öffnet → User klickt Retry-Button (während Download läuft) → zweiter Task wird gestartet → beide schreiben `cachedModels`.

**Why it happens:** `start()`-Idempotenz-Check (`guard loadingTask == nil`) verhindert parallele Tasks, aber `retry()` muss den alten Task **canceln** vor dem neuen `beginDownload`. Wenn nicht: zwei Tasks laufen, zwei Updates.

**How to avoid:**
```swift
func retry() {
    loadingTask?.cancel()
    loadingTask = nil
    // ... cleanup, dann beginDownload()
}
```
FluidAudio's URLSession-Tasks reagieren auf `Task.cancel()` durch Cancellation-Throw, der dann in `classify(_)` als "Unbekannt" landet. Akzeptabel — der zweite Task überschreibt den State eh.

**Warning signs:** Test `retry_during_active_download` zeigt zwei `progressHandler`-Spuren in den Mock-Calls.

### Pitfall 5: ParakeetClient `diarizerEnabledLastLoad` State-Drift

**What goes wrong:** Nach Phase 3 setzt `ParakeetClient.ensureLoaded` den Diarizer aus `manager.modelsIfInstalled`. Aber bestehender Code re-loaded ASR + Diarizer wenn `diarizerEnabledLastLoad != settings.parakeetDiarization` (ParakeetClient.swift:25, :122). Wenn der Manager das Modell schon gecached hat, würde `ensureLoaded` trotzdem ASR neu laden (wegen Setting-Drift-Check).

**Why it happens:** ASR-Reload und Diarizer-Reload teilen sich denselben `loadingTask` — schneidet beide unnötig.

**How to avoid:** ParakeetClient-Refactor in Phase 3 trennt ASR-Lifecycle (bleibt wo er ist) von Diarizer-Lifecycle (kommt aus Manager). Das `diarizerEnabledLastLoad`-Flag wird obsolet, weil der Manager den Diarizer-Cache verantwortet.

**Konkrete Änderung in `ParakeetClient.ensureLoaded()`:**
```swift
// Statt:
if asrManager == nil || diarizerEnabledLastLoad != settings.parakeetDiarization {
    await ensureLoaded()
}

// Neu:
if asrManager == nil {
    await ensureASRLoaded()  // splittet aus
}
if settings.parakeetDiarization, diarizer == nil {
    if let models = await diarizerModelManager.modelsIfInstalled {
        let diar = DiarizerManager(config: .default)
        diar.initialize(models: models)
        self.diarizer = diar
    }
    // else: bleibt nil; Aufnahme läuft ohne Speaker-Annotationen
}
if !settings.parakeetDiarization {
    self.diarizer = nil  // Cleanup wenn Toggle off
}
```

**Warning signs:** Phase-2-Test `Pipeline-Error-Path: Diarization-Silent-Fallback` (TEST-04) muss in Phase 3 angepasst werden — er pinnt das CURRENT-Verhalten und darf bewusst gebrochen werden (siehe STATE.md "Decisions"-Eintrag).

## Code Examples

### Example 1: Manager-Instanziierung in `AppDelegate.bootstrap`

```swift
// Source: BlitzText/App/AppDelegate.swift modified
// Pattern: bestehende Reihenfolge (modelManager-init → onActivate-Hook → preload)

// In AppDelegate properties:
let diarizerModelManager = DiarizerModelManager()

// In bootstrap(), nach modeProcessor-init:
modeProcessor.preloadLocalModelIfActive()
modelManager.onActivate = { [weak self] in
    self?.modeProcessor.preloadLocalModelIfActive()
}

// NEW — Diarizer-Pre-Warm (D-13/D-14)
if settingsStore.parakeetDiarization {
    diarizerModelManager.prewarm()
}

// NEW — Toggle-Side-Effect (Pattern 2)
settingsStore.$parakeetDiarization
    .removeDuplicates()
    .dropFirst()
    .sink { [weak self] enabled in
        guard let self else { return }
        if enabled {
            self.diarizerModelManager.start()
        }
    }
    .store(in: &cancellables)  // cancellables-Store muss neu in AppDelegate aufgenommen werden
```

### Example 2: SwiftUI-Konsum in `DiarizerStatusBlock`

```swift
// Source: 03-UI-SPEC.md State-Spezifikation; FluidAudio nicht direkt hier
// File: BlitzText/Settings/DiarizerStatusBlock.swift (NEW) oder inline in SettingsView.swift

private struct DiarizerStatusBlock: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var diarizerManager: DiarizerModelManager

    var body: some View {
        switch diarizerManager.state {
        case .notInstalled:
            // State (a): Toggle aktiv, kein Modell-Hinweis
            Toggle("Sprechererkennung (Diarization)", isOn: $settings.parakeetDiarization)
            Text("Aktiviert Sprecher-Annotationen (\"Sprecher 1: …\"). Lädt zusätzlich ein Diarizer-Modell (~80 MB).")
                .font(.caption2).foregroundStyle(.tertiary)

        case .downloading(let progress, let eta):
            // State (b): Status-Label + Progress + ETA
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lädt Diarizer-Modell …").font(.subheadline)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)
                    Text(detailLine(progress: progress, eta: eta))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

        case .installed:
            // State (c): Toggle aktiv + Confirmation
            Toggle("Sprechererkennung (Diarization)", isOn: $settings.parakeetDiarization)
            if settings.parakeetDiarization {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Modell vorhanden").font(.caption).foregroundStyle(.green)
                }
            }
            Text("Aktiviert Sprecher-Annotationen (\"Sprecher 1: …\"). Lädt zusätzlich ein Diarizer-Modell (~80 MB).")
                .font(.caption2).foregroundStyle(.tertiary)

        case .failed(let message):
            // State (d): Error + Retry
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diarizer-Modell konnte nicht geladen werden").font(.subheadline)
                    Text(message).font(.caption).foregroundStyle(.red)
                    Button("Erneut versuchen") { diarizerManager.retry() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func detailLine(progress: Double, eta: Double?) -> String {
        let percent = Int((progress * 100).rounded())
        guard let eta else { return "\(percent) % · Geschwindigkeit wird ermittelt …" }
        let etaText: String
        if eta < 60 { etaText = "noch ~\(Int(eta.rounded())) s" }
        else if eta < 3600 { etaText = "noch ~\(Int((eta / 60).rounded())) min" }
        else { etaText = "noch ~\(Int((eta / 3600).rounded())) h" }
        return "\(percent) % · \(etaText)"
    }
}
```

## Runtime State Inventory

> Phase 3 ist **kein** Rename/Refactor/Migrations-Phase. Sie führt einen neuen Manager + UI-Block ein und passt zwei bestehende Call-Sites an. Keine String-Replacements, keine Datenstruktur-Migration. Diese Sektion bleibt aus konsequenter Hygiene drin.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — Phase 3 schreibt keine eigenen persistenten Daten. FluidAudio cached die Modelle in `~/Library/Application Support/FluidAudio/Models/speaker-diarization/` (existing behavior). `parakeetDiarization` in `SettingsStore.Snapshot` ist optional + bereits da. | Keine Migration. |
| Live service config | None — kein externer Service. | Keine. |
| OS-registered state | None — kein launchd/Task Scheduler/pm2. | Keine. |
| Secrets/env vars | Optional `REGISTRY_URL` / `MODEL_REGISTRY_URL` ENV vars (FluidAudio-Override für HF-Mirror). Wenn gesetzt, geht der Download dorthin statt zu HF. **Nicht durch BlitzText ausgewertet** — wenn der User sie gesetzt hat, war's vor Phase 3 schon so und bleibt so. | Keine. |
| Build artifacts | None — keine Build-Artefakte werden zur Build-Zeit erzeugt. SPM-Checkout aktualisiert sich automatisch. | Keine. |

## Common Pitfalls (zusammengefasst)

Siehe Sektion oben. Kurz:
1. FluidAudio Default-Pfad respektieren, nicht eigenen ausdenken.
2. `dropFirst()` auf `$parakeetDiarization` damit Initial-Load nicht triggert.
3. Compile-Phase als "75 % wird kompiliert …" labeln, nicht als ETA.
4. Bei `retry()` den alten Task canceln vor `beginDownload()`.
5. `ParakeetClient.diarizerEnabledLastLoad` obsoletisieren — Diarizer-Cache lebt im Manager.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| FluidAudio (SPM) | Diarizer-Lifecycle | ✓ | 0.14.3 (Package.resolved) | — |
| WhisperKit (SPM) | unverändert | ✓ | 0.18.0 | — |
| macOS 26.0 | CoreML, FluidAudio | ✓ (deployment target) | 26.0 | — |
| Swift 6.0 | toolchain | ✓ | 6.0 | — |
| Internet-Verbindung beim ersten Download | DiarizerModels.downloadIfNeeded | runtime-dependent | n/a | UI-State (d) "Verbindung fehlgeschlagen" + Retry-Button. **Implementiert in Phase 3.** |
| `~/Library/Application Support` writable | FluidAudio cache | ✓ (App ist un-sandboxed, default macOS user-dir) | n/a | UI-State (d) "Speicher" oder "Unbekannt"-Klasse. |

**Missing dependencies with no fallback:** keine.

**Missing dependencies with fallback:**
- Internet-Verbindung — Fallback ist Fehler-UI mit Retry. Genau das ist Phase 3.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Apple System) |
| Config file | `project.yml` (target `BlitzTextTests`, Bundle-Loader-Pattern, lines 66-82) |
| Quick run command | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/DiarizerModelManagerTests` (single Suite, < 5 s) |
| Full suite command | `xcodebuild test -scheme BlitzText -destination 'platform=macOS'` (volle Suite — Phase 2 hatte 22/22 in unter 30 s) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DIA-01 | Progress-Updates während Download | unit | `xcodebuild test ... -only-testing:BlitzTextTests/DiarizerModelManagerTests/test_start_when_not_installed_transitions_to_downloading` | ❌ Wave 0 (NEW) |
| DIA-01 | ETA-Berechnung über Sliding-Window | unit | `xcodebuild test ... -only-testing:BlitzTextTests/ETAEstimatorTests/test_eta_steady_progress_returns_seconds` | ❌ Wave 0 (NEW) |
| DIA-01 | ETA-Erstphase liefert nil ("wird ermittelt …") | unit | `xcodebuild test ... -only-testing:BlitzTextTests/ETAEstimatorTests/test_first_seconds_returns_nil` | ❌ Wave 0 (NEW) |
| DIA-02 | Netzwerk-Fehler-Klassifikation | unit | `xcodebuild test ... -only-testing:BlitzTextTests/DiarizerModelManagerTests/test_error_classification_network` | ❌ Wave 0 (NEW) |
| DIA-02 | Speicher-Fehler-Klassifikation (Cocoa) | unit | `xcodebuild test ... -only-testing:BlitzTextTests/DiarizerModelManagerTests/test_error_classification_storage_cocoa` | ❌ Wave 0 (NEW) |
| DIA-02 | Speicher-Fehler-Klassifikation (POSIX) | unit | `xcodebuild test ... -only-testing:BlitzTextTests/DiarizerModelManagerTests/test_error_classification_storage_posix` | ❌ Wave 0 (NEW) |
| DIA-02 | Unbekannt-Fehler-Default | unit | `xcodebuild test ... -only-testing:BlitzTextTests/DiarizerModelManagerTests/test_error_classification_unknown` | ❌ Wave 0 (NEW) |
| DIA-02 | Retry löscht Cache + restartet Download | unit | `xcodebuild test ... -only-testing:BlitzTextTests/DiarizerModelManagerTests/test_retry_clears_cache_and_restarts` | ❌ Wave 0 (NEW) |
| (regression) | Phase-2-Suite bleibt grün | regression | full suite (s.o.) | ✅ existing |
| (UI smoke) | DiarizerStatusBlock rendert vier States | manual | nicht automatisierbar (SwiftUI Preview ist visueller Smoke-Test, kein XCTest) | manual gate |

### Sampling Rate

- **Per task commit:** Single-Suite-Run der betroffenen Suite (`DiarizerModelManagerTests` ODER `ETAEstimatorTests`), < 5 s.
- **Per wave merge:** Volle BlitzTextTests-Suite, < 30 s (Phase-2-Bench).
- **Phase gate:** Volle Suite grün vor `/gsd-verify-work` + manueller End-to-End-Smoke (Toggle on → Download mit Progress sichtbar → Modell installiert; Toggle off → on bei vorhandenem Modell → State (c) ohne Re-Download).

### Wave 0 Gaps

- [ ] `BlitzTextTests/Diarizer/DiarizerModelManagerTests.swift` — abdeckt DIA-01 (state-Transitionen) + DIA-02 (Fehler-Klassifikation, Retry)
- [ ] `BlitzTextTests/Diarizer/ETAEstimatorTests.swift` — abdeckt DIA-01 ETA-Anteil
- [ ] `BlitzTextTests/Support/FakeDiarizerLoader.swift` — Test-Seam (Protocol-Implementierung)
- [ ] `BlitzText/Transcription/DiarizerLoaderProtocol.swift` (oder inline im Manager-File) — Production-Seam
- [ ] Framework install: nicht nötig — XCTest existiert seit Phase 2.

*Manuelle E2E-Smoke-Steps (kein Wave-0-Gap, nur Phase-Gate-Doku):*
1. Lösche `~/Library/Application Support/FluidAudio/Models/speaker-diarization/`
2. Build + Run BlitzText, öffne Settings → Lokal → Parakeet-Sektion
3. Toggle "Sprechererkennung (Diarization)" → erwartet: State (b) erscheint sofort, Progress-Bar bewegt sich, ETA zeigt nach 1-2 s eine Zahl, schließlich State (c) mit "Modell vorhanden ✓"
4. Toggle off, Toggle on → erwartet: kein neuer Download, sofort State (c)
5. Disconnect WiFi, lösche Cache, Toggle on → erwartet: State (b) → State (d) "Verbindung fehlgeschlagen …" + Retry-Button. Retry mit WiFi an → erwartet: State (b) → (c)

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1` in `.planning/config.json`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Keine User-Auth — App ist single-user. |
| V3 Session Management | no | Keine Sessions. |
| V4 Access Control | no | Keine Access-Levels. |
| V5 Input Validation | partial | Nur HTTP-Response-Validation, die FluidAudio bereits in `validateJSONResponse` (DownloadUtils) macht. Wir übergeben keine User-Input-Strings an URL-Builder. |
| V6 Cryptography | partial | TLS via URLSession-Default. **Nicht hand-gerollt.** Kein Cert-Pinning (siehe CONCERNS.md "No URL pinning" — bewusst akzeptiert). |
| V7 Error Handling | yes | Drei Fehler-Klassen wie spezifiziert (D-10, UI-SPEC). Kein Stack-Trace-Leak in UI. |
| V8 Data Protection | partial | Diarizer-Modelle sind public Embeddings (pyannote/wespeaker), keine privaten Daten. Cache-Pfad ist user-dir, nicht system-wide. App ist un-sandboxed (CONCERNS.md P1 accepted). |
| V9 Communications | yes | TLS-Default; HTTPS via `https://huggingface.co` (oder ENV-Mirror). |
| V12 Files & Resources | yes | Cache-Pfad-Validation: `FluidAudio.MLModelConfigurationUtils.defaultModelsDirectory()` ist hardcoded auf Application Support — keine User-supplied Pfade. |
| V13 API & Web Service | n/a | Keine eigenen APIs. |
| V14 Configuration | yes | `REGISTRY_URL`/`MODEL_REGISTRY_URL`-ENV-Override ist eine known-good FluidAudio-Feature; wir adden nichts. |

### Known Threat Patterns for `Swift / macOS / FluidAudio + URLSession`

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Cache-Korruption durch Crash mid-Download | Tampering | FluidAudio's eigener "first load failed → delete cache → retry"-Pfad (`DownloadUtils.swift:130-153`). Wir konsumieren das via `clearModelCache(forRepo:directory:)` im Retry-Flow. |
| HF-Server-Compromise / Modell-Tampering | Tampering | TLS via URLSession-Default verifiziert Server-Cert. Kein Cert-Pinning (akzeptierter Trade-off, CONCERNS.md V3-Note). FluidAudio re-validiert `coremldata.bin`-Existenz im Bundle vor dem `MLModel(contentsOf:)`-Call. |
| Disk-Fill-DoS durch wiederholten Failed-Download | DoS | Retry ist user-getriggert (kein Auto-Backoff D-10). Partial-Files werden vor jedem Retry über `clearModelCache` gelöscht. Kein unbounded-disk-growth-Pfad. |
| Path-Traversal via HF-File-Paths | Tampering | FluidAudio's `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)` (DownloadUtils:407) plus `appendingPathComponent`-Sandboxing in unserem Pfad. **Aber:** Wir prüfen nicht, dass HF-Paths nicht `../` enthalten. **Mitigation:** Wir vertrauen FluidAudio. Falls in Phase 3 ein Audit gewünscht ist: ein assert vor `appendingPathComponent` würde reichen. **Recommendation:** Für ASVS-Level-1 reicht das aktuelle Vertrauensmodell. |
| Sensitive-Data-Leak via Log | Information Disclosure | Manager loggt **keine** User-Daten (keine Aufnahmen, keine Transkripte). Logs zeigen nur: Download-Phase, Bytes-Counter, Fehlermeldungen. Konvention aus CONVENTIONS.md ("Do NOT log raw transcripts") wird eingehalten. |

**Phase-3-spezifischer Sicherheits-Hotpot:** Keiner. FluidAudio läuft im selben TLS-Trust-Modell wie WhisperKit (Phase 1+2 already accepted). On-device-Inferenz bleibt erhalten (keine Cloud-Dependencies hinzugefügt).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ParakeetClient.swift:133`: `try await DiarizerModels.downloadIfNeeded()` ohne progressHandler | `manager.start()` mit progressHandler-bridge in Manager | Phase 3 | UI-Sichtbarkeit + Fehler-Recovery |
| Diarizer-Cache hängt am `loadingTask` von `ParakeetClient` (gemeinsam mit ASR) | Diarizer-Cache lebt im `DiarizerModelManager`, ASR bleibt in `ParakeetClient` | Phase 3 | Saubere Verantwortungstrennung; Phase-2-`diarizerEnabledLastLoad`-Flag obsoletisiert |
| Bestehende `LocalModelManager.download(_)` ist Whisper-spezifisch (mehrere Modelle, eigener `ModelDownloader`-Wrapper) | `DiarizerModelManager` ist Single-Modell, konsumiert FluidAudio direkt — kein neuer `ModelDownloader`-Wrapper | Phase 3 | Weniger Code, weniger Drift-Risiko |

**Deprecated/outdated:**
- `ParakeetClient.diarizerEnabledLastLoad: Bool` — wird in Phase 3 entfernt. Ersatz: Manager-State + Setting-Cleanup im Lifecycle.
- Phase-2-Test `Pipeline-Error-Path: Diarization-Silent-Fallback` (TEST-04, PipelineErrorPathTests) — pinnt den heutigen `silent download`-Pfad. In Phase 3 ändert sich das Verhalten bewusst (CONTEXT.md, STATE.md "Decisions"). Test muss angepasst oder durch neuen Pin ersetzt werden.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | UI-SPEC's Claim "~80 MB" ist die User-erwartete Größe (HF-Repo-Bruttogröße), die On-Disk-Größe nach Install ist 13 MB | Summary, Architecture | Niedrig — UI-SPEC ist locked, Code muss die Zahl nicht prüfen. |
| A2 | `URLError.dataNotAllowed` mappt auf Speicher-Klasse (Apple-Doku ist mehrdeutig: "data is not allowed"). UI-SPEC sagt explizit `dataNotAllowed → Speicher`. Wir folgen UI-SPEC. | Error Classification | Niedrig — falsch klassifiziert wäre nur eine ungenaue UI-Meldung; Funktionalität bleibt. |
| A3 | Sliding-Window-ETA mit N=5 s ist gefühlt am besten. Kein A/B-Test gemacht. | ETA Strategy | Niedrig — Tunable Constant, kann Wave-1 angepasst werden falls Smoke-Test schlechte Wahrnehmung zeigt. |
| A4 | Pre-Warm "best-effort" heißt: ein einmaliger Download-Versuch, kein automatischer Retry beim Fehler. UI-SPEC bestätigt. | Pre-Warm Detection | Niedrig — Verhalten ist explizit. |
| A5 | `DiarizerModels.downloadIfNeeded()` ist No-Op wenn alles installiert ist. Inspektion von DownloadUtils:204-216 deutet darauf hin, aber wurde nicht live mit `du`-Vergleich verifiziert. | Pre-Warm | Mittel — wenn falsch, würde Pre-Warm bei jedem App-Start Bytes ziehen. **Empfehlung:** Plan nimmt einen `isInstalled`-Sync-Check **vor** dem `downloadIfNeeded`-Call auf, der bei `true` direkt zu State `.installed` springt. Dann ist A5 belanglos. |

## Open Questions

1. **D-06 vs. FluidAudio-progressHandler — Re-Confirmation gewünscht?**
   - What we know: D-06 sagt "eigener Downloader". FluidAudio 0.14.3 exponiert genau das, was D-06 selber bauen wollte.
   - What's unclear: Ob D-06 ein "wir bauen die UI selber"-Statement war oder ein "wir trauen FluidAudio nicht für Progress"-Statement.
   - Recommendation: Planner stellt im PLAN.md einen Mini-ADR voran ("Variant A: FluidAudio progressHandler — chosen") und der User kann's einkurz approven oder per `/gsd-replan-phase` rückgängig machen. Variant B (eigener Downloader) ist im Anhang dokumentiert.

2. **`MLModelConfiguration` für CI/Testing-Pfad?**
   - What we know: FluidAudio's `defaultConfiguration` switch zwischen `.cpuAndNeuralEngine` (CI) und `.all` (default).
   - What's unclear: Ob der `BlitzTextTests`-Run unter `XCTestConfigurationFilePath` als CI gilt (ProcessInfo-ENV nicht gleich `CI`).
   - Recommendation: Tests injizieren `FakeDiarizerLoader`, lädt nie ein echtes Modell → Frage entfällt. Production-Pfad ist `.all`.

3. **Wann wird `ParakeetClient` refactored — eigener Plan oder mit Manager?**
   - What we know: Manager + Settings-UI + ParakeetClient-Refactor sind drei distinct Aufgaben.
   - What's unclear: Wave-Granularität.
   - Recommendation: Planner-Sache. Naheliegend: Wave 0 = Manager + Tests (DI-Seam), Wave 1 = SettingsView + AppDelegate-Wiring + ParakeetClient-Anpassung. Phase-2-Pin-Test bricht in Wave 1 absichtlich.

## Sources

### Primary (HIGH confidence)
- **FluidAudio source v0.14.3 SPM-Checkout** — direkter Read der Diarizer-Module:
  - `Sources/FluidAudio/Diarizer/Core/DiarizerModels.swift` (DiarizerModels API + downloadIfNeeded + load(localSegmentationModel:))
  - `Sources/FluidAudio/DownloadUtils.swift` (ProgressHandler typealias + DownloadProgress struct + downloadRepo + clearModelCache)
  - `Sources/FluidAudio/ModelNames.swift` (Diarizer.requiredModels, Repo.diarizer)
  - `Sources/FluidAudio/ModelRegistry.swift` (URL-Konstruktion, baseURL-Override)
  - `Sources/FluidAudio/Shared/MLModelConfigurationUtils.swift` (defaultModelsDirectory)
- **Package.resolved** — pin verifiziert: `FluidAudio 0.14.3, revision 00ea906c2089971bec767c4b4df38686aa7a9f9e`
- **GitHub Releases API** `https://api.github.com/repos/FluidInference/FluidAudio/releases/latest` (curl 2026-05-01) — bestätigt 0.14.3 als latest
- **On-disk inspection** `~/Library/Application Support/FluidAudio/Models/speaker-diarization/` — 13 MB tatsächliche Cache-Größe, exakter Datei-Listing
- **BlitzText-Codebase**: ParakeetClient.swift, LocalModelManager.swift, ModelDownloader.swift, SettingsStore.swift, AppDelegate.swift, SettingsView.swift, project.yml — alle live gelesen

### Secondary (MEDIUM confidence)
- **Apple Foundation docs (training)** — URLError.Code enum, CocoaError.fileWriteOutOfSpace, POSIXError.ENOSPC. Standard, nicht extern verifiziert in dieser Session, aber stable seit Swift 4.

### Tertiary (LOW confidence)
- (none — alle Claims sind via Source-Inspektion oder Codebase-Read verifiziert)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — FluidAudio-Source live inspected, Versionspin verifiziert
- Architecture: HIGH — Manager-Pattern hat 1:1 Vorlage in `LocalModelManager`, getestet im Codebase
- FluidAudio API: HIGH — Source live gelesen, exakter URL-Pfad + Method-Signaturen
- ETA Strategy: MEDIUM — Algorithmus-Wahl ist Empfehlung, nicht hart verifiziert
- Error Classification: HIGH — Apple-domain-mapping ist Standard, UI-SPEC fixiert die Strings
- Pitfalls: HIGH — Pitfall 5 (`diarizerEnabledLastLoad`-Drift) ist konkret aus Code lesbar
- Tests: HIGH — Phase 2 hat das DI-Pattern bereits etabliert

**Research date:** 2026-05-01
**Valid until:** 2026-08-01 (FluidAudio movt langsam; Apple URLError-Domain ist seit Jahren stable)

---

## Anhang: Variant B (D-06 strikt durchgesetzt)

> Nur lesen, falls der User D-06 explizit nicht von FluidAudio's eingebautem progressHandler delegieren lassen will.

### Eigener Downloader analog `ModelDownloader.swift`

```swift
// File: BlitzText/Transcription/DiarizerModelDownloader.swift (NEW)
enum DiarizerModelDownloader {
    static let baseURL = "https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/main"

    enum Result: Sendable {
        case success
        case failure(String)
    }

    /// Lädt die Diarizer-Modell-Dateien manuell.
    /// Achtung: Diese Pfad-Liste MUSS mit FluidAudio's HF-Tree-API-Auflistung übereinstimmen.
    /// Bei FluidAudio-Update auf >0.14.3 manuell verifizieren.
    static func download(
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> Result {
        // 1. HF-Tree-API queren für rekursive Datei-Liste — wie FluidAudio.DownloadUtils.downloadRepo (Zeile 307-369)
        // 2. Jede Datei via URLSession.download laden, Progress aggregieren
        // 3. In `destination` ablegen
        // 4. DiarizerModels.load(localSegmentationModel:localEmbeddingModel:) aufrufen
        // …
        // ~150 LOC plus Tests für die Tree-Walking-Logik
    }
}
```

**Manager nutzt diesen statt FluidAudio:**

```swift
private func beginDownload() {
    let dest = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/BlitzText/Models/Diarizer")
    let task = Task { [weak self] in
        let result = await DiarizerModelDownloader.download(destination: dest) { frac in
            Task { @MainActor [weak self] in self?.handleProgress(frac) }
        }
        await MainActor.run { [weak self] in
            switch result {
            case .success:
                let seg = dest.appendingPathComponent("pyannote_segmentation.mlmodelc")
                let emb = dest.appendingPathComponent("wespeaker_v2.mlmodelc")
                self?.cachedModels = try? await DiarizerModels.load(
                    localSegmentationModel: seg, localEmbeddingModel: emb
                )
                self?.state = .installed
            case .failure(let msg):
                self?.state = .failed(message: msg)
            }
        }
    }
    loadingTask = task
}
```

**Kosten gegenüber Variant A:**
- +150 LOC Downloader (Tree-Walk, Progress-Aggregation, Error-Mapping)
- +50 LOC Tests dafür (Mock-URLSession)
- Drift-Risiko bei FluidAudio-Updates (URL-Pfade/Required-Files können sich ändern)
- Doppelter Cache-Pfad (`BlitzText/Models/Diarizer` UND `FluidAudio/Models/speaker-diarization` falls FluidAudio's Default-Pfad in irgendeinem Codepfad weiter konsultiert wird)

**Vorteil:** Volle Kontrolle. Cancel wäre einbaubar (out of scope per D-04). Pfad-Konvention konsistent mit `LocalModelManager`-Models-Root.

**Empfehlung bleibt Variant A.** Variant B ist für den Fall, dass D-06 als hard-locked behandelt werden muss.
