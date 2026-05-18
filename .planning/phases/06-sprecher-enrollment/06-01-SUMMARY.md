---
phase: 06-sprecher-enrollment
plan: "01"
subsystem: speaker-enrollment-backend
tags:
  - speaker-enrollment
  - fluidaudio
  - parakeet
  - tdd
dependency_graph:
  requires:
    - "05-xx: SpeakerProfileStore.saveSpeakers (atomar)"
    - "03-xx: DiarizerModelManager.ensureInstalled"
  provides:
    - "ParakeetClient.enrollSpeaker(audioURL:name:) async throws -> Speaker"
    - "EnrollmentError enum (diarizerNotReady, tooShort, tooQuiet)"
    - "SpeakerProfileViewModel.addEnrolledSpeaker(_:)"
    - "ModeProcessor.parakeetClient internal (für DI in Wave 3)"
  affects:
    - "06-02: EnrollmentViewModel nutzt enrollSpeaker + addEnrolledSpeaker"
    - "06-03: UI-Sheet nutzt ModeProcessor.parakeetClient via AppDelegate-DI"
tech_stack:
  added:
    - "AVFoundation.AVAudioFile (in EnrollmentTests WAV-Helper)"
  patterns:
    - "synchron-throws extractSpeakerEmbedding im async-Kontext (kein Task.detached nötig)"
    - "@MainActor auf TestCase-Klasse wenn actor-isolated Dependencies im init"
key_files:
  created:
    - path: BlitzTextTests/Speakers/EnrollmentTests.swift
      purpose: "Unit-Tests für enrollSpeaker Fehler-Pfade (tooShort, tooQuiet, diarizerNotReady)"
  modified:
    - path: BlitzText/Transcription/ParakeetClient.swift
      purpose: "EnrollmentError enum + enrollSpeaker(audioURL:name:) async throws -> Speaker"
      loc_added: ~74
    - path: BlitzText/Transcription/SpeakerProfileViewModel.swift
      purpose: "addEnrolledSpeaker(_:) Methode (Append-vs-Replace + saveSpeakers)"
      loc_added: ~10
    - path: BlitzText/Modes/ModeProcessor.swift
      purpose: "parakeetClient: private lazy var → lazy var (internal)"
      loc_changed: 1
    - path: BlitzTextTests/Speakers/SpeakerProfileViewModelTests.swift
      purpose: "testAddEnrolledSpeaker_appendsAndSaves + testAddEnrolledSpeaker_replacesExistingId"
      loc_added: ~40
    - path: BlitzText.xcodeproj/project.pbxproj
      purpose: "xcodegen regeneriert damit EnrollmentTests.swift im Test-Target erfasst wird"
decisions:
  - "EnrollmentError als top-level enum in ParakeetClient.swift (kein separates File nötig)"
  - "await vor upsertSpeaker (actor-isolated SpeakerManager) statt SpeakerManager als nonisolated zu behandeln"
  - "@MainActor auf EnrollmentTests-Klasse wegen DiarizerModelManager.init (actor-isolated)"
  - "xcodegen generate nach Erstellen von EnrollmentTests.swift ausgeführt (Datei war nicht im Xcode-Target)"
metrics:
  duration: "~30 Minuten"
  completed: "2026-05-18"
  tasks_completed: 2
  tests_added: 5
  tests_total_after: 93
---

# Phase 06 Plan 01: Speaker-Enrollment Backend — Summary

**One-liner:** EnrollmentError enum + enrollSpeaker via FluidAudio extractSpeakerEmbedding (synchron-throws) + addEnrolledSpeaker ViewModel-Methode + 5 neue grüne Tests.

## Was wurde gebaut

### Task 1: ParakeetClient.enrollSpeaker + EnrollmentError + ModeProcessor-Sichtbarkeit

- **`EnrollmentError`** (top-level enum in `ParakeetClient.swift`): drei Cases — `diarizerNotReady`, `tooShort`, `tooQuiet`
- **`ParakeetClient.enrollSpeaker(audioURL:name:) async throws -> Speaker`**:
  1. Diarizer-Guard: `if diarizer == nil { await ensureLoaded() }` + `guard let diarizer`
  2. `AudioConverter().resampleAudioFile(audioURL)` — identisches Muster wie `transcribe`
  3. Längenguard: `Double(samples.count) / 16_000.0 >= 5.0` → `.tooShort`
  4. RMS-Guard: `sqrtf(sumOfSquares / Float(samples.count)) >= 0.005` → `.tooQuiet`
  5. `try diarizer.extractSpeakerEmbedding(from: samples)` — synchron-throws, direkt im async-Kontext
  6. `Speaker(id: UUID().uuidString, name: name, currentEmbedding: embedding, isPermanent: true)`
  7. `await diarizer.speakerManager.upsertSpeaker(speaker)` — Convenience-Variante (A1 confirmed: vorhanden)
  8. `store.saveSpeakers(updated)` mit Deduplizierung per ID
- **`ModeProcessor.parakeetClient`**: `private lazy var` → `lazy var` (internal)

### Task 2: SpeakerProfileViewModel.addEnrolledSpeaker + Unit-Tests

- **`addEnrolledSpeaker(_:)`** in `SpeakerProfileViewModel`: Append-vs-Replace per `id`, dann `store.saveSpeakers(speakers)`
- **2 neue ViewModel-Tests** (grün):
  - `testAddEnrolledSpeaker_appendsAndSaves` — neuer Speaker wird angehängt + auf Disk persistiert
  - `testAddEnrolledSpeaker_replacesExistingId` — gleiche ID → ersetzt statt Duplikat
- **3 neue EnrollmentTests** (grün):
  - `testEnrollSpeaker_tooShort_throws` — 4s WAV → `EnrollmentError.tooShort` ODER `.diarizerNotReady`
  - `testEnrollSpeaker_tooQuiet_throws` — 6s Stille → `EnrollmentError.tooQuiet` ODER `.diarizerNotReady`
  - `testEnrollSpeaker_diarizerNotReady_throws` — `parakeetDiarization=false` → pinnt `.diarizerNotReady`

## Architektur-Notizen

### synchron-throws extractSpeakerEmbedding im async-Kontext

`DiarizerManager.extractSpeakerEmbedding(from:)` ist **synchron** (kein `async`), kann aber direkt in einem `async throws`-Kontext mit `try` aufgerufen werden. Da `ParakeetClient` `@unchecked Sendable` ist und der Aufruf in einem `Task` (nicht auf dem MainActor) stattfindet, ist kein `Task.detached` nötig. Die CoreML-Inferenz blockiert den aufrufenden Thread (nicht den MainActor), was in einem `async`-Kontext ohne MainActor-Constraint korrekt ist.

### upsertSpeaker erfordert `await`

Die Convenience-Variante `SpeakerManager.upsertSpeaker(_ speaker: Speaker)` ist actor-isolated. Der RESEARCH.md-Hinweis "kein await nötig" war bzgl. der Concurrency-Anforderung unvollständig. Die Korrektur (`await diarizer.speakerManager.upsertSpeaker(speaker)`) ist kompatibel mit dem async-Kontext von `enrollSpeaker`.

### xcodegen nach neuer Test-Datei

Das `project.yml` nutzt path-Globbing für `BlitzTextTests/`. Neu erstellte Swift-Dateien werden erst nach `xcodegen generate` ins Xcode-Target aufgenommen. Das ist normales Projektverhalten.

## Test-Run-Output (Speakers Suite)

```
Test Suite 'EnrollmentTests' passed
   Executed 3 tests, with 0 failures in 2.045 seconds

Test Suite 'SpeakerProfileViewModelTests' passed
   Executed 23 tests, with 0 failures in 4.237 seconds

Test Suite 'BlitzTextTests.xctest' passed
   Executed 93 tests, with 0 failures in 6.606 seconds

** TEST SUCCEEDED **
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `await` vor `upsertSpeaker` ergänzt**
- **Found during:** Task 1 — Build-Fehler nach Implementierung
- **Issue:** `SpeakerManager.upsertSpeaker` ist actor-isolated und kann nicht synchron aus einem non-actor-isolated async-Kontext aufgerufen werden.
- **Fix:** `diarizer.speakerManager.upsertSpeaker(speaker)` → `await diarizer.speakerManager.upsertSpeaker(speaker)`
- **Files modified:** `BlitzText/Transcription/ParakeetClient.swift`
- **Commit:** 1d07ddf

**2. [Rule 3 - Blocking] `DiarizerModelManager.init` ohne `settings:`-Parameter**
- **Found during:** Task 2 — Compile-Fehler in EnrollmentTests
- **Issue:** PATTERNS.md zeigte `DiarizerModelManager(settings: settings)` aber die reale Signatur ist `init(loader:etaWindowSeconds:)` ohne SettingsStore.
- **Fix:** Test nutzt `DiarizerModelManager()` (Default-Init ohne settings-Param)
- **Files modified:** `BlitzTextTests/Speakers/EnrollmentTests.swift`

**3. [Rule 3 - Blocking] `@MainActor` auf EnrollmentTests-Klasse**
- **Found during:** Task 2 — Compile-Fehler in EnrollmentTests
- **Issue:** `DiarizerModelManager.init(...)` ist actor-isolated (`@MainActor`). Aufruf aus nonisolated synchronous Kontext nicht erlaubt.
- **Fix:** `@MainActor` auf `final class EnrollmentTests: XCTestCase` gesetzt (alle Test-Methoden sind bereits async, daher kein Re-entrancy-Problem)
- **Files modified:** `BlitzTextTests/Speakers/EnrollmentTests.swift`

**4. [Rule 3 - Blocking] xcodegen generate nach neuer Test-Datei**
- **Found during:** Task 2 — 0 Tests ausgeführt obwohl Datei existierte
- **Issue:** `EnrollmentTests.swift` war zwar auf Disk, aber nicht im Xcode-Target (project.pbxproj), da XcodeGen nicht automatisch neu generiert.
- **Fix:** `xcodegen generate` ausgeführt; `project.pbxproj` in Commit aufgenommen.
- **Files modified:** `BlitzText.xcodeproj/project.pbxproj`

## Commits

| Hash | Beschreibung |
|------|-------------|
| 1d07ddf | feat(06-01): ParakeetClient.enrollSpeaker + EnrollmentError + ModeProcessor internal |
| 66ee222 | feat(06-01): SpeakerProfileViewModel.addEnrolledSpeaker + EnrollmentTests |

## Known Stubs

Keine. Alle implementierten Methoden sind vollständig verdrahtet.

## Threat Flags

Keine neuen Angriffsflächen außerhalb des bereits dokumentierten Threat Models:
- T-06-01 (Tampering): Längen- und RMS-Guard implementiert — mitigiert
- T-06-02 (Info Disclosure): Embeddings on-device, kein Netzwerkaufruf — accepted
- T-06-03 (DoS): enrollSpeaker ist async, CoreML läuft nicht auf MainActor — mitigiert
- T-06-04 (Tampering): SpeakerProfileStore.saveSpeakers atomar — accepted

## Self-Check: PASSED

| Check | Status |
|-------|--------|
| ParakeetClient.swift | FOUND |
| SpeakerProfileViewModel.swift | FOUND |
| ModeProcessor.swift | FOUND |
| EnrollmentTests.swift | FOUND |
| commit 1d07ddf | FOUND |
| commit 66ee222 | FOUND |
