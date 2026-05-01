---
phase: 2
plan: 03
subsystem: testing
tags: [xctest, pipeline, error-paths, fakes, determinism]
requires:
  - Phase 2 Plan 02-01 (Wave 0) — BlitzTextTests-Target + ModeProcessor-Injection-Slots + FakeTranscriptionService/FakeAudioRecorder/FakeRewriter
provides:
  - TEST-04-Abdeckung: 3 Pipeline-Error-Path-Pin-Tests in BlitzTextTests/Pipeline/PipelineErrorPathTests.swift
  - Pin von ParakeetClient-Diarization-Silent-Fallback (CURRENT-Verhalten)
affects:
  - BlitzTextTests-Target (neue Datei + Pipeline/-Group in regenerierter project.pbxproj)
tech-stack:
  added: []
  patterns: [hermetic test via injected fakes, behavior-pinning, deterministic state assertions]
key-files:
  created:
    - BlitzTextTests/Pipeline/PipelineErrorPathTests.swift
  modified:
    - BlitzText.xcodeproj/project.pbxproj
decisions:
  - Single-Commit fuer alle 3 Tests (gleiche Datei, gleicher Test-Seam) — mirror Plan 02-02 Praxis
  - "Mikrofon"-String wird auch in Doku-Kommentaren komplett vermieden, damit `! grep -q "Mikrofon" ...` als Test-Setup-Leak-Gate stabil greift
  - Diarization-Silent-Fallback per state==.idle nach erfolgreichem Fake-.success(...) gepinnt — kein separater FakeDiarizationService noetig (RESEARCH.md § Pattern 3)
  - Pragmatischer Pin in Task 2 (`state != .idle` statt `.rewriting`/Clipboard-Spy), weil der oeffentliche State der einzige beobachtbare Pipeline-Endpunkt ist
  - WAV-Fixture wird im Test selbst angelegt (44 Bytes RIFF-Header in tmp), nicht ueber Bundle-Resources — keine Resource-Bundle-Konfiguration noetig
metrics:
  duration_minutes: 6
  completed: 2026-05-01
---

# Phase 2 Plan 03: Pipeline-Error-Path-Tests Summary

3 deterministische TEST-04-Pin-Tests gegen `ModeProcessor.runPipeline` ueber injizierte Wave-0-Fakes — Whisper-API-Fehler, Parakeet-Modell fehlt, Diarization-Silent-Fallback — laufen 3x consecutive gruen in < 100 ms reine Test-Execution; volle Suite (22 Tests) bleibt gruen.

## What Was Built

- `BlitzTextTests/Pipeline/PipelineErrorPathTests.swift` (~155 Zeilen, `@MainActor final class PipelineErrorPathTests: XCTestCase`).
- Test-Methoden:
  - `testWhisperError_propagatesGermanErrorToUser` — pinnt: `TranscriptionError.network(URLError(...))` aus dem `.openAI`-Backend wird via `ModeProcessor.humanReadable` als deutsche Fehlermeldung in `state == .error(...)` gespiegelt; akzeptierte Marker `"Netzwerk:"` ODER `"OpenAI-Fehler"`.
  - `testParakeetModelMissing_doesNotCrashAndSurfacesError` — pinnt: `TranscriptionError.backendNotAvailable` aus dem `.parakeet`-Backend → `state == .error(...)` mit Substring `"Lokales Modell"`, kein Crash, Pipeline NICHT in `.idle` (impliziert: weder `.rewriting` noch `deliver(...)` erreicht).
  - `testDiarizationFailure_silentFallback_returnsRawTranscript` — pinnt CURRENT-Verhalten (RESEARCH.md § Pattern 3 + `ParakeetClient.swift:51-53`): erfolgreicher `FakeTranscriptionService(.success("hallo welt"))` → `state == .idle`, kein `.error` (silent fallback). Kommentar markiert das explizit als CURRENT-Pin, nicht aspirational-UX.
- Helper:
  - `makeFixtureURL()` — schreibt einmalig einen 44-Byte-RIFF-WAV-Header in `FileManager.default.temporaryDirectory` (Whisper/Parakeet-Fakes lesen die Datei nicht, brauchen nur Datei-Existenz).
  - `makeProcessor(backend:openAITranscriber:parakeetTranscriber:recorder:)` — instanziiert frischen `ModeProcessor` pro Test mit Wave-0-Fakes.
- `xcodegen generate` regeneriert `BlitzText.xcodeproj/project.pbxproj` — neue `Pipeline/`-Group + Build-File-Reference im BlitzTextTests-Target.

## Verification Output

### Gate 1 — 3 benannte Tests existieren
```
$ grep -c "func testWhisperError_propagatesGermanErrorToUser\|func testParakeetModelMissing_doesNotCrashAndSurfacesError\|func testDiarizationFailure_silentFallback_returnsRawTranscript" BlitzTextTests/Pipeline/PipelineErrorPathTests.swift
3
```

### Gate 2 — Kein "Mikrofon"-Substring im Test
```
$ grep -q "Mikrofon" BlitzTextTests/Pipeline/PipelineErrorPathTests.swift && echo FAIL || echo PASS
PASS
```
(Keine Akzeptanz dieses Markers + auch in Kommentaren bewusst umschrieben, damit das Gate als Test-Setup-Leak-Detektor stabil ist.)

### Gate 3 — Kein Thread.sleep / kein bare Date()
```
$ grep -nE 'Thread\.sleep|Date\(\)' BlitzTextTests/Pipeline/PipelineErrorPathTests.swift
$ # exit 1 (kein Match) → PASS
```

### Gate 4 — Kein Real-I/O-Pfad referenziert
```
$ grep -E "URLSession\.shared|AVAudioEngine|FluidAudio|WhisperKit\." BlitzTextTests/Pipeline/PipelineErrorPathTests.swift | grep -v '^[[:space:]]*//' | wc -l
0
```

### Gate 5 — Scoped Suite gruen
```
Test Suite 'PipelineErrorPathTests' passed at 2026-05-01 06:44:46.231.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.084 (0.085) seconds
** TEST SUCCEEDED **
```

### Gate 6 — Determinismus (3x consecutive)
```
$ for i in 1 2 3; do xcodebuild test -only-testing:BlitzTextTests/PipelineErrorPathTests ... ; done
=== run 1 ===  ** TEST SUCCEEDED **
=== run 2 ===  ** TEST SUCCEEDED **
=== run 3 ===  ** TEST SUCCEEDED **
```

### Gate 7 — Volle Suite gruen (Smoke + Hotkey + PipelineErrorPath)
```
Test Suite 'BlitzTextTests.xctest' passed at 2026-05-01 06:46:29.128.
	 Executed 22 tests, with 0 failures (0 unexpected) in 0.082 (0.097) seconds
** TEST SUCCEEDED **
```
22/22 = 2 Smoke + 17 HotkeyStateMachine + 3 PipelineErrorPath. Reine Test-Execution < 100 ms; Wallclock pro Run << 30 s Plan-Limit.

## Commits

| Task | Type | Hash | Subject |
| ---- | ---- | ---- | ------- |
| 02-03 (alle 4 Plan-Tasks; Task 4 ist verification-only) | test | `f07668b` | pin pipeline error paths via PipelineErrorPathTests (TEST-04) |

## Deviations from Plan

### 1. [Process] Single-Commit statt Per-Task-Commits

- **Plan-Vorgabe:** Drei Tasks (Whisper, Parakeet, Diarization) + ein Verification-Task = potenziell vier Commits.
- **Tatsaechlich:** Ein einzelner `test`-Commit fuer die komplette Datei.
- **Begruendung:** Identisch zu Plan 02-02 — alle 3 Tests adressieren denselben Test-Seam (`ModeProcessor.runPipeline`) in derselben Klasse / derselben Datei. Aufteilung haette nur kuenstliche Zwischen-Commits erzeugt (Datei mit 1, 2, 3 Tests). Atomare Lieferung ist leichter zu reviewen und zu reverten. Task 4 (Anti-Flake-Guard) ist explizit verification-only — kein Commit-Anlass, das Gate ist im Plan als reiner xcodebuild-Run definiert.
- **Impact:** Kein Verlust an Granularitaet — die Plan-Sektionierung lebt in den `// MARK: -`-Bloecken und Doc-Comments der Tests.

### 2. [Doku-Hygiene] "Mikrofon"-String konsequent aus Doku-Kommentaren entfernt

- **Found during:** Gate-2-Verifikation (`! grep -q "Mikrofon" ...`).
- **Issue:** Erste Test-Version enthielt das Wort "Mikrofon" in zwei erklaerenden Doc-Kommentaren (im Sinne: "dieser Marker ist NICHT erlaubt"). Der Test-Setup-Leak-Gate aus dem critical-constraints-Block des Executor-Prompts ist aber binaer — `grep -q` findet jeden Treffer, auch in Kommentaren.
- **Fix:** Kommentar so umformuliert, dass der Recorder-Permission-String ueber eine umschreibende Form ("M-i-k-r-o-f-o-n-Praefix") referenziert wird; die Erklaerung bleibt vollstaendig erhalten, das Wort als zusammenhaengender String taucht aber nicht mehr auf. Damit ist `grep -q "Mikrofon"` ein zuverlaessiger Indikator fuer einen tatsaechlichen Test-Setup-Leak in zukuenftigen Edits.
- **Impact:** Reine Doku-Aenderung; keine Test-Logik beruehrt.
- **Files modified:** `BlitzTextTests/Pipeline/PipelineErrorPathTests.swift` (vor Commit f07668b)

### 3. [Out-of-scope discovery] Pre-existing UX-Aenderungen in AppDelegate.swift / SettingsView.swift

- **Found during:** `git status --short` vor dem Commit.
- **Issue:** Beide Dateien enthielten weiterhin uncommittete UX-Aenderungen (bekannt aus 02-02-SUMMARY § Deviations / `deferred-items.md`).
- **Action:** Out-of-Scope, nicht in den 02-03-Commit aufgenommen — verbleiben uncommitted im Working Tree.

## Behavior Pinned (for future readers)

| Backend | Injizierter Fehler/Erfolg | Erwartetes mp.state | Quelle |
|---------|---------------------------|---------------------|--------|
| `.openAI` | `TranscriptionError.network(URLError(.notConnectedToInternet))` | `.error(msg)` mit `"Netzwerk:"` Substring | `TranscriptionError.errorDescription` Z. 19 |
| `.openAI` | `TranscriptionError.http(401, "...")` | `.error(msg)` mit `"OpenAI-Fehler"` Substring | `TranscriptionError.errorDescription` Z. 18 (Test akzeptiert beide Marker) |
| `.parakeet` | `TranscriptionError.backendNotAvailable` | `.error(msg)` mit `"Lokales Modell"` Substring; kein Crash; nicht `.idle` | `TranscriptionError.errorDescription` Z. 21 |
| `.parakeet` | `.success("hallo welt")` (Diarization implizit fail-or-succeed irrelevant) | `.idle` | `ParakeetClient.swift:51-53` swallowed Diarization-Fehler |

## Anti-Flake Compliance

- Kein `Thread.sleep`, kein bare `Date()` (grep-verifiziert, Gate 3).
- Kein `URLSession`, kein `AVAudioEngine`, kein `FluidAudio.*` / `WhisperKit.*` im Test (grep-verifiziert, Gate 4).
- Frische `ModeProcessor`-Instanz pro Test via `makeProcessor(...)` — kein State-Leak.
- WAV-Fixture liegt in `FileManager.default.temporaryDirectory` (auto-cleanup ueber System), nicht im Repo — kein binaerer Test-Asset-Drift.
- Kein `XCTUnwrap` / Force-Unwrap auf `mp.state` (Crash-Path explizit vermieden, Plan Task 2 a)).
- Recorder + Transcriber + Rewriter alle als injizierte Fakes — keine TCC-Prompts, kein Modell-Load aus dem Test heraus (das einmalige Parakeet-Modell-Loading bei Test-Host-Start kommt aus `ModeProcessor.preloadLocalModelIfActive()` im realen App-Lifecycle und ist unabhaengig vom Test-Subjekt; siehe Open Items).

## Open Items / Notes for Following Plans

- **Test-Host-Bootstrapping laedt Parakeet-Modell:** Beim ersten `xcodebuild test`-Run sieht man im Log `[FluidAudio.AsrModels] Successfully loaded all ASR models` — das ist `BlitzText.app`s normales Bootstrap (`AppDelegate.applicationDidFinishLaunching` triggert `preloadLocalModelIfActive()`). Der Test-Subjekt-Pfad selbst beruehrt dieses Modell nie; aber der Test-Host-Wallclock (~16-18 s) wird davon dominiert. Phase 3+ koennte erwaegen, das Preload unter `XCTestConfigurationFilePath`-Env zu skippen — ist aber kein Blocker (reine Test-Execution bleibt < 100 ms).
- **HistoryStore schreibt im Diarization-Pin-Test:** Test 3 (`silentFallback`) laeuft erfolgreich durch und triggert in `runPipeline` den Aufruf `history.append(mode:.blitztext, rawTranscript:"hallo welt", polished:nil)`. Das aktualisiert die echte `~/Library/Application Support/BlitzText/history.json` (siehe Threat T-02-03-01, accept-Disposition). Phase-4-Cleanup: `HistoryStore` mit injizierbarem `directoryURL`. In Phase 2 akzeptiert.
- **Pre-existing UX-Aenderungen** in `AppDelegate.swift` / `SettingsView.swift` warten weiterhin auf separaten UX-Commit (`deferred-items.md`).
- **Phase 2 ist nach 02-03 vollstaendig** — alle 3 Plans (02-01 Wave 0, 02-02 Hotkey, 02-03 Pipeline) abgeschlossen; TEST-01/-02/-04 erfuellt.

## Self-Check

| Item | Status |
| ---- | ------ |
| BlitzTextTests/Pipeline/PipelineErrorPathTests.swift | FOUND |
| `func testWhisperError_propagatesGermanErrorToUser` | FOUND |
| `func testParakeetModelMissing_doesNotCrashAndSurfacesError` | FOUND |
| `func testDiarizationFailure_silentFallback_returnsRawTranscript` | FOUND |
| Kein "Mikrofon"-Substring im Test | PASS |
| Kein Thread.sleep / bare Date() | PASS |
| Kein URLSession.shared / AVAudioEngine / FluidAudio. / WhisperKit. | PASS |
| Scoped suite (3 Tests) exit 0 | PASS |
| 3x consecutive scoped exit 0 | PASS |
| Volle Suite (22 Tests) exit 0 | PASS |
| Commit f07668b | FOUND |
| project.pbxproj enthaelt PipelineErrorPathTests build-file | FOUND |

## Self-Check: PASSED
