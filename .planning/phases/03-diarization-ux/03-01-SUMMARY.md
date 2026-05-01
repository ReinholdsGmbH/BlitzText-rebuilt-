---
phase: 03-diarization-ux
plan: 01
subsystem: Diarization
tags: [swift6, macos, fluidaudio, diarization, testing, foundation, wave-1]
requires: []
provides:
  - DiarizerModelManager (@MainActor lifecycle owner für FluidAudio-Diarizer-Modell)
  - DiarizerLoaderProtocol (Sendable test-seam analog Phase-2-RecorderProtocol)
  - FluidAudioDiarizerLoader (Production-Impl, wrapped DiarizerModels.downloadIfNeeded)
  - ETAEstimator (pure-data sliding-window Restzeit-Schätzung)
  - FakeDiarizerLoader (Test-Fake mit progressTicks + injizierbarem Fehler)
affects:
  - BlitzTextTests/ (neue Diarizer/-Subdirektive + Support/-Erweiterung)
tech-stack:
  added: []
  patterns:
    - "DI-Seam-Pattern (Wave-2-fortgesetzt aus Phase 2 RecorderProtocol)"
    - "@MainActor ObservableObject für Modell-Lifecycle (analog LocalModelManager)"
    - "Worker→MainActor-Hop via Task { @MainActor in ... } in progressHandler"
    - "Sliding-Window-Sample-Struct mit cutoff-basiertem prune"
key-files:
  created:
    - BlitzText/Transcription/ETAEstimator.swift (40 LOC)
    - BlitzText/Transcription/DiarizerLoaderProtocol.swift (75 LOC)
    - BlitzText/Transcription/DiarizerModelManager.swift (195 LOC)
    - BlitzTextTests/Support/FakeDiarizerLoader.swift (46 LOC)
    - BlitzTextTests/Diarizer/ETAEstimatorTests.swift (52 LOC, 5 Tests)
    - BlitzTextTests/Diarizer/DiarizerModelManagerTests.swift (135 LOC, 10 Tests)
  modified:
    - BlitzText.xcodeproj/project.pbxproj (regen via xcodegen)
key-decisions:
  - "Variant A bestätigt durch Build: FluidAudio.DiarizerModels.downloadIfNeeded(progressHandler:) wird gewrappt — keine eigene URLSession-Implementierung"
  - "DiarizerLoaderProtocol exponiert nur fractionCompleted (Double), nicht DownloadProgress-Struct → Tests bleiben unabhängig vom FluidAudio-Bundle"
  - "ETAEstimator als value-type struct (mutating tick) statt class — pure-data, isoliert testbar, kein @MainActor"
  - "FakeDiarizerLoader wirft am Ende immer (auch im Erfolgspfad) weil DiarizerModels keinen public init hat — Tests verifizieren state-Transitionen, nicht cachedModels"
  - "Repo-Symbol ist top-level public enum (nicht ModelNames.Repo) — Plan-Code wurde während Implementierung korrigiert"
requirements-completed: [DIA-01, DIA-02]
duration: ~25 min
completed: 2026-05-01
---

# Phase 3 Plan 01: Foundation-Layer für Diarizer-UX Summary

**One-liner:** `@MainActor` Diarizer-Lifecycle-Manager wrapped FluidAudios `DiarizerModels.downloadIfNeeded(progressHandler:)` (Variant A), klassifiziert URLError/CocoaError/POSIX in drei UI-SPEC-fixierte deutsche Strings, plus Pure-Data ETAEstimator mit Sliding-Window — Wave-2 baut darauf UI + AppDelegate-Pre-Warm.

## Was gemacht wurde

| Task | Inhalt | Tests | Commit |
| ---- | ------ | ----- | ------ |
| 1 RED | ETAEstimatorTests (5 Verhaltens-Pins) | – | `4bbdcfe` |
| 1 GREEN | ETAEstimator + DiarizerLoaderProtocol + FluidAudioDiarizerLoader + FakeDiarizerLoader | 5/5 grün | `8ce5c0b` |
| 2 RED | DiarizerModelManagerTests (10 Verhaltens-Pins) | – | `a39e637` |
| 2 GREEN | DiarizerModelManager (state machine + classify + start/retry/prewarm) | 10/10 grün | `f747853` |

**Test-Ergebnis volle Suite:** 37/37 grün (22 Phase-2 + 5 ETA + 10 Manager). 3× consecutive identisch grün — kein Flake.

## Variant A vs. B — Entscheidungs-Befund

Plan-ADR (Variant A) bestätigt sich durch die Implementierung:

| Metrik | Variant A (gewählt) | Variant B (verworfen) |
| ------ | ------------------- | --------------------- |
| Production-LOC | 75 (Protocol) + 195 (Manager) = **270 LOC** | ~400+ LOC geschätzt (eigener URLSession + HF-Tree-Crawler + Pattern-Filter + Bundle-Validation) |
| FluidAudio-API-Surface konsumiert | `DiarizerModels.downloadIfNeeded(progressHandler:)`, `DownloadUtils.{ProgressHandler,DownloadProgress,clearModelCache,HuggingFaceDownloadError}`, `Repo.diarizer`, `ModelNames.Diarizer.{segmentationFile,embeddingFile}` | – |
| Forward-Kompat bei FluidAudio-Bumps | automatisch (FluidAudio-Maintainer ist verantwortlich für File-Set) | manuelles Audit notwendig |
| Pfad-Konsistenz | FluidAudio-Default `~/Library/Application Support/FluidAudio/Models/speaker-diarization/` — keine Doppelkopien | eigener Pfad → Risiko Doppelkopien wenn ParakeetClient `directory: nil` nutzt |

## Hand-off für Plan 03-02 (Wave 2)

**Stable Public Surface von `DiarizerModelManager` (von UI/AppDelegate konsumieren):**

```swift
@MainActor
final class DiarizerModelManager: ObservableObject {
    @Published private(set) var state: DiarizerModelState  // notInstalled | downloading | installed | failed
    @Published private(set) var downloadProgress: Double?  // 0…1, nil außerhalb Download
    @Published private(set) var etaSeconds: Double?        // nil bei Anlauf/Stagnation
    @Published private(set) var lastError: String?         // deutscher String, drei Klassen

    var isInstalled: Bool                // sync-Check ohne Inferenz (für ensureLoaded + bootstrap)
    var modelsIfInstalled: DiarizerModels?  // für ParakeetClient-Konsum (nil bis Download fertig)

    init(loader: DiarizerLoaderProtocol = FluidAudioDiarizerLoader(), etaWindowSeconds: TimeInterval = 5.0)

    func start()    // Toggle-On-Trigger, idempotent
    func retry()    // User-Klick "Erneut versuchen" → clearCache + neuer Download
    func prewarm()  // App-Start, nicht-blockierend, Pre-Warm wenn parakeetDiarization=true
}

enum DiarizerModelState: Equatable {
    case notInstalled
    case downloading(progress: Double, etaSeconds: Double?)
    case installed
    case failed(message: String)
}
```

**Plan 03-02 nutzt diese Surface 1:1 — keine Abweichung von 03-01-PLAN.md `<handoff>`:**

- UI bindet `@ObservedObject` auf `manager.state` und switched zwischen den vier Cases (UI-SPEC § Diarizer-Block).
- Retry-Button ruft `manager.retry()`.
- AppDelegate.bootstrap ruft `manager.prewarm()` wenn `settings.parakeetDiarization == true`.
- ParakeetClient liest `manager.isInstalled` + `manager.modelsIfInstalled` statt direkt `DiarizerModels.downloadIfNeeded()` aufzurufen (D-15-Verhaltensänderung; PipelineErrorPathTests-Anpassung kommt in Plan 03-02 Task 3).

**Drei deutsche Strings sind bereits byte-genau in `DiarizerModelManager.classify` einkompiliert (UI-SPEC § Copywriting Contract, einsehbar via `manager.lastError`):**

1. Netzwerk: `"Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut."`
2. Speicher: `"Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht)."`
3. Unbekannt: `"Download fehlgeschlagen. Versuch es später erneut — wenn das Problem bleibt, schau in das Log unter ~/Library/Logs/BlitzText.log."`

## Build-Anpassungen vs. Plan-Pseudo-Code

Drei kleine Korrekturen während der Implementierung — alle non-functional:

1. **`Repo.diarizer` statt `ModelNames.Repo.diarizer`:** In FluidAudio 0.14.3 ist `Repo` ein top-level `public enum` (Source: `Sources/FluidAudio/ModelNames.swift:4`), nicht innerhalb `ModelNames`. Plan-Code referenzierte den falschen Namespace; Compiler hätte das eindeutig abgelehnt. Korrektur in `FluidAudioDiarizerLoader.clearCache()` und Kommentar.

2. **`DiarizerModels.downloadIfNeeded(progressHandler:)`-Wrapper:** Plan-Code nutzte `progressHandler.map { ph in { (p: ...) in ph(p.fractionCompleted) } }` mit inferred return type. Das löste in Swift 6 einen Compiler-Bug ("failed to produce diagnostic for expression"). Workaround: explizite `let wrapped: DownloadUtils.ProgressHandler? = ...`-Bindung mit benamtem Closure-Wert. Funktional identisch, nur anders geschrieben.

3. **`HuggingFaceDownloadError`-Cases mit associated values:** In FluidAudio 0.14.3 sind die Cases `rateLimited(statusCode:message:)`, `downloadFailed(path:underlying:)`, `modelNotFound(path:)`, `htmlErrorResponse(path:snippet:)`. Der `switch hf`-Pattern ohne assoc-Bindings funktioniert in Swift weil wir keine values binden — kompiliert sauber, Plan-NOTE-Anpassung war daher nicht nötig.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Build-Blocker] `Repo.diarizer`-Namespace**
- **Found during:** Task 1 GREEN, Compile-Verifikation `xcodebuild build`
- **Issue:** Plan-Code schrieb `DownloadUtils.clearModelCache(forRepo: .diarizer, directory: dir)` mit dem Kommentar `ModelNames.Repo.diarizer`; tatsächlich heißt der Top-Level-Symbol `Repo` ohne `ModelNames`-Präfix.
- **Fix:** Code nutzt `.diarizer`-Punkt-Notation (Type-Inferenz) und Kommentar zeigt jetzt korrekt auf top-level `public enum Repo` mit Source-Pfad.
- **Files:** `BlitzText/Transcription/DiarizerLoaderProtocol.swift`
- **Commit:** `8ce5c0b`

**2. [Rule 3 - Build-Blocker] Swift-6-Compiler-Bug bei Closure-Inferenz**
- **Found during:** Task 1 GREEN, erster `xcodebuild build`-Run
- **Issue:** `progressHandler.map { ph in { (p: ...) in ph(p.fractionCompleted) } }` ergibt unter Swift 6 / macOS-26-Toolchain einen "failed to produce diagnostic for expression"-Compiler-Bug.
- **Fix:** Explizit benamte `let wrapped: DownloadUtils.ProgressHandler? = ...`-Bindung mit explizitem Closure-Typ; semantisch identisch.
- **Files:** `BlitzText/Transcription/DiarizerLoaderProtocol.swift`
- **Commit:** `8ce5c0b`

**Total deviations:** 2 auto-fixed (beide Rule 3 — Build-Blocker, beide non-functional). **Impact:** Keine. Public API, Verhalten und Test-Ergebnisse identisch zum Plan.

## Self-Check: PASSED

| Item | Status |
| ---- | ------ |
| `BlitzText/Transcription/ETAEstimator.swift` exists | FOUND |
| `BlitzText/Transcription/DiarizerLoaderProtocol.swift` exists | FOUND |
| `BlitzText/Transcription/DiarizerModelManager.swift` exists | FOUND |
| `BlitzTextTests/Support/FakeDiarizerLoader.swift` exists | FOUND |
| `BlitzTextTests/Diarizer/ETAEstimatorTests.swift` exists (5 tests) | FOUND |
| `BlitzTextTests/Diarizer/DiarizerModelManagerTests.swift` exists (10 tests) | FOUND |
| Commit `4bbdcfe` (test RED ETA) | FOUND |
| Commit `8ce5c0b` (feat GREEN ETA + protocol) | FOUND |
| Commit `a39e637` (test RED Manager) | FOUND |
| Commit `f747853` (feat GREEN Manager) | FOUND |
| All 12 acceptance-criteria substring checks PASS | PASS |
| `xcodebuild test -scheme BlitzText` 3× consecutive | 37/37 grün, 3× identisch |
| Phase-2-Tests (`HotkeyStateMachineTests`, `PipelineErrorPathTests`, `SmokeTests`) intakt | PASS |

## Threat Flags

Keine neuen Surface-Patches außerhalb des Plan-Threat-Models. Alle Threat-IDs T-DIAR-1..5 bleiben mit ihren Plan-Dispositions in Kraft.

## TDD Gate Compliance

Beide Tasks folgten der RED-GREEN-Sequenz im git log:

- Task 1: `test(03-01)` → `feat(03-01)` (commits `4bbdcfe` → `8ce5c0b`)
- Task 2: `test(03-01)` → `feat(03-01)` (commits `a39e637` → `f747853`)

Kein REFACTOR-Commit nötig — Code ging in der GREEN-Phase direkt sauber.

## Ready for Plan 03-02

Wave 1 ist abgeschlossen. Plan 03-02 (Wave 2) kann parallel bereits begonnen oder seriell starten — die hier gelieferte Surface ist stabil. Konsumiert von:

- **`SettingsView.swift`** (Diarizer-Block UI mit `@ObservedObject` auf `manager.state`)
- **`AppDelegate.bootstrap`** (`prewarmDiarizerIfActive` ruft `manager.prewarm()`)
- **`ParakeetClient.ensureLoaded`** (D-16: konsultiert `manager.isInstalled` + `manager.modelsIfInstalled` statt direkter FluidAudio-Aufruf)
- **`PipelineErrorPathTests`** (in Plan 03-02 Task 3 angepasst, weil `ParakeetClient`-Pfad sich ändert)
