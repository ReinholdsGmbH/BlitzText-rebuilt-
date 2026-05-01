---
phase: 03-diarization-ux
plan: 02
subsystem: Diarization
tags: [swift6, macos, swiftui, fluidaudio, diarization, settings-ui, integration, wave-2]
requires:
  - 03-01-SUMMARY.md (DiarizerModelManager surface)
provides:
  - DiarizerStatusBlock (vier-state-block in SettingsView)
  - DiarizerModelManager.ensureInstalled() async (D-16-Konsumpunkt für ParakeetClient)
  - SettingsStore.diarizerManager + didSet-Side-Effect (D-01)
  - AppDelegate.bootstrap mit prewarm-Detached-Task (D-13, D-14)
  - PipelineErrorPathTests-Helper mit FakeDiarizerLoader-Manager
affects:
  - BlitzText/App/AppDelegate.swift (DI-Wiring)
  - BlitzText/Modes/ModeProcessor.swift (init-Signatur)
  - BlitzText/Settings/SettingsStore.swift (didSet + weak ref)
  - BlitzText/Settings/SettingsView.swift (DiarizerStatusBlock)
  - BlitzText/Settings/SettingsWindowController.swift (environmentObject)
  - BlitzText/Transcription/DiarizerModelManager.swift (ensureInstalled)
  - BlitzText/Transcription/ParakeetClient.swift (manager-konsumierend)
  - BlitzTextTests/Pipeline/PipelineErrorPathTests.swift (helper)
  - BlitzTextTests/Diarizer/DiarizerModelManagerTests.swift (2 Tests)
tech-stack:
  added: []
  patterns:
    - "@MainActor-Hop für Cross-Actor-Side-Effect (SettingsStore.didSet → DiarizerModelManager.start())"
    - "Switch-over-State-Enum für Vier-State-UI (D-18, UI-SPEC State-by-State)"
    - "DI via init-Constructor statt @EnvironmentObject für Service-Schicht (ParakeetClient, ModeProcessor)"
    - "@EnvironmentObject nur in View-Schicht (DiarizerStatusBlock, SettingsView)"
    - "Detached MainActor.run-Task im AppDelegate.bootstrap für Pre-Warm — App-Start blockiert nie"
key-files:
  created: []
  modified:
    - BlitzText/Transcription/DiarizerModelManager.swift (+ensureInstalled async)
    - BlitzText/Settings/SettingsStore.swift (didSet, weak ref)
    - BlitzText/Transcription/ParakeetClient.swift (manager DI, ensureLoaded refactor)
    - BlitzText/Modes/ModeProcessor.swift (init-Param)
    - BlitzText/Settings/SettingsWindowController.swift (init-Param + environmentObject)
    - BlitzText/Settings/SettingsView.swift (DiarizerStatusBlock + Block-Replace)
    - BlitzText/App/AppDelegate.swift (Manager-Property, bootstrap-DI, prewarm)
    - BlitzTextTests/Pipeline/PipelineErrorPathTests.swift (Helper + Pin-Test-Doc)
    - BlitzTextTests/Diarizer/DiarizerModelManagerTests.swift (+2 ensureInstalled Tests)
key-decisions:
  - "ensureInstalled() async löst Snapshot des loadingTask vor dem await — verhindert Race mit beginDownload's loadingTask=nil-Zuweisung"
  - "didSet-Side-Effect via Task @MainActor weil DiarizerModelManager.start() @MainActor-isoliert ist und SettingsStore nicht; explizite weak-Capture im Task-Closure für Sicherheit"
  - "diarizerStateMatches() als @MainActor-Methode, await-Aufrufe in Sequenz (nicht in &&-autoclosure) wegen Swift-6-Restriktion"
  - "Wave-0-Manager hatte cachedModels bereits in allen Erfolgs-Pfaden gesetzt — kein Wave-0-Patch nötig"
  - "Manager im PipelineErrorPathTests-Helper ist isolierte FakeDiarizerLoader-Instanz; State irrelevant, weil parakeetTranscriber Fake ist"
requirements-completed: [DIA-01, DIA-02]
duration: ~8 min
completed: 2026-05-01
---

# Phase 3 Plan 02: Diarizer-UX-Wiring Summary

**One-liner:** Wave-0-`DiarizerModelManager`-Surface in BlitzText eingewoben — `SettingsStore`-`didSet` triggert Manager-Start, `ParakeetClient.ensureLoaded` ruft `manager.ensureInstalled()` (kein direkter `DiarizerModels.downloadIfNeeded`-Call mehr), `SettingsView` rendert vier visuell distinkte States via `switch manager.state`, `AppDelegate.bootstrap` prewarmt im detached MainActor-Task. 39 Tests grün, 3× konsekutiv.

## Was gemacht wurde

| Task | Inhalt | Commit |
| ---- | ------ | ------ |
| 1 | `DiarizerModelManager.ensureInstalled() async` + 2 Tests (already-installed, fail-Pfad) | `da4a4e9` |
| 2 | `SettingsStore.parakeetDiarization.didSet` → `manager.start()` via `Task @MainActor` + `weak diarizerManager` | `e92bac7` |
| 3 | `ParakeetClient` & `ModeProcessor` manager-konsumierend; `DiarizerModels.downloadIfNeeded` direkt-Call entfernt; `diarizerStateMatches()` für Reload-Entscheidung | `b9e7be9` |
| 4 | `DiarizerStatusBlock` in `SettingsView` (4 States); `SettingsWindowController` injiziert `diarizerManager` als `environmentObject` | `e584e80` |
| 5 | `AppDelegate.bootstrap` mit `DiarizerModelManager()`-Property + DI in alle drei Konsumenten + Pre-Warm; `PipelineErrorPathTests`-Helper mit `FakeDiarizerLoader`; Pin-Test-Doc aktualisiert | `daf66f2` |

**Test-Ergebnis volle Suite:** 39/39 grün. 3× konsekutiv-Run zeigte 3× `Test Suite 'BlitzTextTests.xctest' passed` — kein Flake.

## LOCKED-Strings-Audit (UI-SPEC § Copywriting)

Alle sechs LOCKED-Strings byte-genau in `BlitzText/Settings/SettingsView.swift`:

| String | Greps |
| ------ | ----- |
| `Lädt Diarizer-Modell …` (U+2026) | 1 |
| `Geschwindigkeit wird ermittelt …` (U+2026) | 2 |
| `Erneut versuchen` | 1 |
| `Diarizer-Modell konnte nicht geladen werden` | 1 |
| `Modell vorhanden` | 1 |
| Drei Error-Klassen (Netzwerk/Speicher/Unbekannt) — bereits in Wave-0-`DiarizerModelManager.classify`, hier konsumiert | – |

**HARD constraints:**

- HARD #1 (LOCKED strings byte-genau): PASS
- HARD #2 (Toggle wird ersetzt, nicht disabled): PASS — `grep -A 3 'Toggle("Sprechererkennung' SettingsView.swift | grep disabled(true)` = 0
- HARD #3 (`DiarizerModels.downloadIfNeeded` direkt-Call): PASS — `grep -c "DiarizerModels.downloadIfNeeded" ParakeetClient.swift` = 0 (Kommentar wurde umformuliert)
- HARD #4 (Phase-2-Pin-Test grün): PASS — `xcodebuild test -only-testing:BlitzTextTests/PipelineErrorPathTests` exit 0, 3/3
- HARD #5 (3× konsekutiv grün): PASS — alle drei Runs `Test Suite 'BlitzTextTests.xctest' passed`
- HARD #6 (`08-CONTEXT.md` unangetastet): PASS — `git status` zeigt M-Marker nur auf vom Plan modifizierten Files

## Hand-off für /gsd-verify-phase 3

Manuelle visuelle Verifikation in der laufenden App:

1. **State (a) — Toggle aktiv:** `Settings → Lokales Modell` öffnen mit gelöschtem Diarizer-Cache (`rm -rf "~/Library/Application Support/FluidAudio/Models/speaker-diarization"` während App geschlossen). Toggle ist sichtbar, off, mit Subtitle.
2. **State (b) — Lädt Diarizer-Modell …:** Toggle on flippen → Toggle verschwindet, ProgressView läuft, Detail-Zeile zeigt `{percent} % · noch ~{n} {s|min}` (oder `Geschwindigkeit wird ermittelt …` in den ersten ~2 s).
3. **State (c) — Modell vorhanden:** Nach abgeschlossenem Download → Toggle wieder sichtbar (on), grüner Checkmark + "Modell vorhanden".
4. **State (d) — Fehler:** Netzwerk vor Toggle-On trennen (WLAN aus, oder DNS auf 127.0.0.1) → "Diarizer-Modell konnte nicht geladen werden" + deutsche Klassifikation + "Erneut versuchen"-Button (klickbar, retry feuert).
5. **App-Start-Prewarm:** Mit `parakeetDiarization == true` und gelöschtem Diarizer-Cache App neu starten. UI darf NICHT blockieren; im Settings-Tab erscheint State (b) sofort.

## Wave-0-Patches (gemäß Plan-Hint)

**Keine.** Die Plan-Notiz "Wave-1-cachedModels-Patch falls nötig" war defensiv — `Wave-0-DiarizerModelManager.beginDownload` setzt `cachedModels` schon im Erfolgs-Pfad (Zeile 118 in 03-01-Output). Keine zusätzliche Anpassung nötig.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Build-Blocker] Swift-6 `await` in `&&`-Autoclosure**
- **Found during:** Task 3 erster Build
- **Issue:** `if asrManager != nil && (await diarizerStateMatches()) { … }` ergibt unter Swift 6 strict concurrency: `'await' in an autoclosure that does not support concurrency`. Plan-Code referenzierte das Pattern direkt.
- **Fix:** Sequenzielle `let matches = await diarizerStateMatches()`-Bindung, dann `if matches { return }`. Identische Semantik.
- **Files:** `BlitzText/Transcription/ParakeetClient.swift`
- **Commit:** `b9e7be9`

**2. [Rule 3 — Build-Blocker] MainActor-Isolation in `SettingsStore.didSet`**
- **Found during:** Task 2 erster Build
- **Issue:** `DiarizerModelManager.start()` ist `@MainActor`-isoliert; `SettingsStore` ist nicht. Direkter `diarizerManager?.start()`-Call im `didSet` produziert `call to main actor-isolated instance method 'start()' in a synchronous nonisolated context`.
- **Fix:** `Task { @MainActor [weak diarizerManager] in diarizerManager?.start() }` — Hop auf MainActor mit weak-Capture für Sicherheit.
- **Files:** `BlitzText/Settings/SettingsStore.swift`
- **Commit:** `e92bac7`

**3. [Rule 1 — Acceptance-Hygiene] Kommentar enthielt `DiarizerModels.downloadIfNeeded`**
- **Found during:** Task 3 Acceptance-Verification
- **Issue:** HARD constraint #3 verlangt `grep -c "DiarizerModels.downloadIfNeeded" ParakeetClient.swift` == 0. Plan-Kommentar `// D-16: Manager fragen, NICHT mehr DiarizerModels.downloadIfNeeded() direkt rufen.` ergab grep-count 1.
- **Fix:** Kommentar umformuliert zu `// D-16: Manager ist Single-Source-of-Truth für den Diarizer-Modell-Lifecycle.` — gleiche semantische Aussage, ohne den verbotenen Substring.
- **Files:** `BlitzText/Transcription/ParakeetClient.swift`
- **Commit:** `b9e7be9`

**Total deviations:** 3 auto-fixed (zwei Rule-3 Swift-6-Compile-Anpassungen, eine Rule-1 Acceptance-Hygiene). **Impact:** Keine. Verhalten identisch, alle Tests grün.

## Self-Check: PASSED

| Item | Status |
| ---- | ------ |
| `BlitzText/App/AppDelegate.swift` modified | FOUND |
| `BlitzText/Settings/SettingsStore.swift` modified | FOUND |
| `BlitzText/Settings/SettingsView.swift` modified | FOUND |
| `BlitzText/Settings/SettingsWindowController.swift` modified | FOUND |
| `BlitzText/Transcription/ParakeetClient.swift` modified | FOUND |
| `BlitzText/Transcription/DiarizerModelManager.swift` modified | FOUND |
| `BlitzText/Modes/ModeProcessor.swift` modified | FOUND |
| `BlitzTextTests/Pipeline/PipelineErrorPathTests.swift` modified | FOUND |
| `BlitzTextTests/Diarizer/DiarizerModelManagerTests.swift` modified | FOUND |
| Commit `da4a4e9` (Task 1 — ensureInstalled async) | FOUND |
| Commit `e92bac7` (Task 2 — SettingsStore didSet) | FOUND |
| Commit `b9e7be9` (Task 3 — ParakeetClient + ModeProcessor) | FOUND |
| Commit `e584e80` (Task 4 — SettingsView Vier-State + WindowController) | FOUND |
| Commit `daf66f2` (Task 5 — AppDelegate + Pipeline-Pin) | FOUND |
| All Task-1..5 acceptance-criteria substring checks | PASS |
| `xcodebuild test -scheme BlitzText` 3× consecutive | 39/39 grün, 3× identisch |
| Phase-2-Pin (`PipelineErrorPathTests`) intakt | PASS (3/3) |

## Threat Flags

Keine neuen Surface-Patches außerhalb des Plan-Threat-Models. Alle Threat-IDs T-DIAR-W1-1..5 bleiben mit ihren Plan-Dispositions in Kraft.

## Offene Risiken für Phase 4+

- **Lösch-Button** für Diarizer-Modell — explizit deferred (UI-SPEC `Out of Scope`).
- **Cancel-Button** während Download — D-04 deferred.
- **Disk-Space-Warnung pre-flight** — deferred (CONTEXT `<deferred>`); aktuelle Klassifikation am Fehler-Objekt reicht.
- **Diarization-Inferenz-Fehler in HUD surfacen** — Phase 4 oder später (heute: silent fallback auf Roh-Text).

## Ready for /gsd-verify-phase 3

Wave 2 ist abgeschlossen. Alle Wave-0-Tests + Wave-1-Tests grün, ParakeetClient ist manager-konsumierend, UI rendert vier State-Branches, AppDelegate prewarmt im Hintergrund. Manuelle visuelle Inspektion in `/gsd-verify-phase 3` ist der nächste Schritt.
