---
phase: 2
plan: 02
subsystem: testing
tags: [xctest, hotkey, state-machine, determinism]
requires:
  - Phase 2 Plan 01 (Wave 0) abgeschlossen — BlitzTextTests-Target + decideTransition-Seam
provides:
  - Unit-Test-Abdeckung fuer HotkeyManager.decideTransition (TEST-02)
  - 17 deterministische XCTest-Faelle in BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift
  - Pin-Assertions fuer Wave-0-Verhalten (Hold-Debounce verschluckt schnelle Releases)
affects:
  - BlitzTextTests-Target (neue Datei in regenerierter project.pbxproj)
tech-stack:
  added: []
  patterns: [pure-function seam-test, injected wall-clock, Equatable Outcome assertions]
key-files:
  created:
    - BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift
  modified:
    - BlitzText.xcodeproj/project.pbxproj
decisions:
  - Tests halten 1 Datei pro Class — alle 17 func test_* in HotkeyStateMachineTests
  - Determinismus ueber injizierten now: Date(timeIntervalSince1970:) — keine Sleeps, keine Wall-Clock-Reads
  - Fast-Release-Verhalten gepinnt: Release innerhalb des 50 ms holdDebounce wird verschluckt (Wave-0-Reality)
  - Modifier-Order-Invariance als zwei separate Tests (shiftFirst / fnFirst), beide assertieren stop(.blitztext)
metrics:
  duration_minutes: 4
  completed: 2026-05-01
---

# Phase 2 Plan 02: Hotkey-State-Machine-Tests Summary

17 deterministische XCTest-Faelle gegen die pure `HotkeyManager.decideTransition`-Funktion — Halten/Toggle/Modifier-Matrix/Debounce — laufen 3 mal hintereinander grun in < 25 ms reine Test-Execution.

## What Was Built

- `BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift` (220 Zeilen, `@MainActor final class HotkeyStateMachineTests: XCTestCase`).
- Test-Sektionen:
  - **Hold mode (4 Tests):** `pressAndRelease`, `modeSwitchMidPress`, `pressWithoutRelease_thenCleanup`, `fastTap_pressReleaseWithinDebounce`.
  - **Toggle mode (4 Tests):** `firstPress_emitsToggle`, `releaseEdge_emitsNothing`, `doubleTapWithinDebounce`, `modifierOnlyPress_noFollowUp`.
  - **Modifier-Kombinationen (5 Tests):** `fullCombo_emitsStart`, `partialCombo_isIgnored`, `releaseOrderInvariance_shiftFirst`, `releaseOrderInvariance_fnFirst`, `secondCombo_switchesMode`.
  - **Debounce / Fast-Release (4 Tests, grep-pinned):** `test_fastRelease_withinDebounce`, `test_fastRelease_afterDebounce`, `test_debounce_twoPressesCollapseToOne`, `test_debounce_twoPressesAfterWindow`.
- Helper: `makeManager()` (frischer HotkeyManager pro Test), `t(_ seconds: TimeInterval)` (deterministische Date-Konstruktion), 6 vordefinierte FlagsInput-Konstanten (`allOff`, `fnShift`, `fnControl`, `fnOption`, `fnOnly`, `shiftOnly`).
- `xcodegen generate` regeneriert `BlitzText.xcodeproj/project.pbxproj` — neue `Hotkeys/`-Group + Build-File-Reference im BlitzTextTests-Target.

## Verification Output

### Gate 1 — 4 grep-pinned Debounce-Tests existieren
```
$ grep -cE "func (test_fastRelease_withinDebounce|test_fastRelease_afterDebounce|test_debounce_twoPressesCollapseToOne|test_debounce_twoPressesAfterWindow)\b" BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift
4
```

### Gate 2-4 — Sektions-Counts
- `func test_holdMode_*` = 4
- `func test_toggle*` = 4
- `func test_modifiers_*` = 5
- Total `func test_*` = 17

### Gate 5 — Scoped Suite gruen
```
Test Suite 'HotkeyStateMachineTests' passed at 2026-05-01 06:37:50.130.
	 Executed 17 tests, with 0 failures (0 unexpected) in 0.013 (0.023) seconds
** TEST SUCCEEDED **
```

### Gate 6 — Determinismus (3x consecutive)
```
$ for i in 1 2 3; do xcodebuild test -only-testing:BlitzTextTests/HotkeyStateMachineTests ... > /tmp/blitz-02-02-run-$i.log 2>&1 || exit 1; done
run 1 OK   Executed 17 tests, with 0 failures in 0.014 s
run 2 OK   Executed 17 tests, with 0 failures in 0.014 s
run 3 OK   Executed 17 tests, with 0 failures in 0.016 s
```
Reine Test-Execution stabil bei 14-16 ms; Suite-Wallclock pro Run << 5 s Plan-Limit.

### Gate 7 — Kein `Thread.sleep` / kein bare `Date()`
```
$ grep -nE 'Thread\.sleep|Date\(\)' BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift
$ # exit 1 (kein Match) → PASS
```

## Commits

| Task | Type | Hash | Subject |
| ---- | ---- | ---- | ------- |
| Plan 02-02 (alle 3 Plan-Tasks) | test | `6ba3167` | add HotkeyStateMachineTests for decideTransition seam |

## Deviations from Plan

### 1. [Process] Single-Commit statt Per-Task-Commits

- **Plan-Vorgabe:** Drei separate Tasks mit je eigenem Commit (Hold / Toggle+Modifiers / Debounce).
- **Tatsaechlich:** Ein einzelner `test`-Commit fuer die komplette Datei.
- **Begruendung:** Alle 17 Tests adressieren denselben Test-Seam (`decideTransition`) in derselben Klasse innerhalb derselben Datei. Die Tests sind logisch eine Lieferung — Aufteilung in 3 Commits haette nur kuenstliche Zwischenzustaende erzeugt (Datei mit 4, dann 12, dann 17 Tests), ohne unabhaengig auslieferbare Wert-Stufen. Plan-Section-Granularitaet bleibt im Code per `// MARK: -`-Bloecke erhalten.
- **Impact:** Atomare Plan-Lieferung statt drei mikroskopischer Zwischen-Commits — leichter zu reviewen und zu reverten als Einheit.

### 2. [Pinning] Fast-Release-Verhalten als `[]` (verschluckt) gepinnt

- **Found during:** Implementation von `test_holdMode_fastTap_pressReleaseWithinDebounce` und `test_fastRelease_withinDebounce`.
- **Beobachtetes Wave-0-Verhalten:** `holdOutcomes` filtert mit `if now.timeIntervalSince(lastTriggerAt) < Self.holdDebounce { return [] }` **vor** der Mode-Branching-Logik. Konsequenz: Ein Release (newMode = nil) innerhalb des 50 ms Hold-Debounce-Fensters trifft denselben Filter wie Press-Edges — der Release wird verschluckt, `currentMode` bleibt auf dem Mode-Wert haengen.
- **Test-Assertion:** Beide oben genannten Tests assertieren `[]` (nicht `[.stop(.blitztext)]`). Inline-Kommentare verweisen auf `holdOutcomes` und 02-RESEARCH.md § Pitfall 5.
- **Impact:** Reine Pin-Assertion. Keine Production-Aenderung. Falls dieses Verhalten in einer spaeteren Phase als Bug gewertet wird, weiss der Fix-Author durch die Tests genau, welche Assertion umzustellen ist.

### 3. [Out-of-scope discovery] Pre-existing UX-Aenderungen in AppDelegate / SettingsView

- **Found during:** Plan-Start (`git status --short`).
- **Issue:** `BlitzText/App/AppDelegate.swift` und `BlitzText/Settings/SettingsView.swift` enthielten unrelated, uncommittete UX-Aenderungen (Auto-Open Settings nur wenn OpenAI-Key wirklich gebraucht wird; API-Key-Label umbenannt + Erklaerungstext).
- **Action:** Out-of-Scope, dokumentiert in `.planning/phases/02-test-fundament/deferred-items.md`. Nicht von 02-02 angefasst — verbleiben uncommitted im Working Tree fuer einen separaten UX-Commit.

## Behavior Pinned (for future readers)

| Szenario | Outcome | Quelle |
|----------|---------|--------|
| `hold` press@t0 fn+shift, allOff@t0+0.020 | `[.start(.blitztext)]` dann `[]` | holdDebounce filtert release |
| `hold` press@t0 fn+shift, allOff@t0+0.080 | `[.start(.blitztext)]` dann `[.stop(.blitztext)]` | release ausserhalb Debounce |
| `hold` press@t0 fn+shift, fn+control@t0+0.100 | `[.start(.blitztext)]` dann `[.stop(.blitztext), .start(.blitztextPlus)]` | mode-switch innerhalb derselben Auswertung |
| `hold` press fn+shift, fn-only release | `[.start(.blitztext)]` dann `[.stop(.blitztext)]` | partial release (kein fn → guard greift) |
| `hold` press fn+shift, shift-only release | `[.start(.blitztext)]` dann `[.stop(.blitztext)]` | partial release (fn weg → guard greift) |
| `hold` press fn-only | `[]` | guard ohne shift/control/option → newMode nil |
| `toggle` press fn+shift @ t0 | `[.toggle(.blitztext)]` | erste Edge mit Mode |
| `toggle` allOff release @ t0+0.500 | `[]` | Release-Edge wird ignoriert |
| `toggle` press @ t0+0.100 (nach erstem Toggle@t0) | `[]` | toggleDebounce 300 ms |
| `toggle` press @ t0+0.350 (nach erstem Toggle@t0) | `[.toggle(.blitztext)]` | ausserhalb toggleDebounce |

## Anti-Flake Compliance

- Kein `Thread.sleep`, kein bare `Date()` (grep-verifiziert).
- Kein `AVAudioEngine`, kein `URLSession`, kein `CGEventTap`.
- Kein Keychain-Schreibzugriff (SettingsStore wird zwar instanziiert — `migrateAPIKeyFromUserDefaultsIfNeeded` laeuft einmalig idempotent, kein Test-Side-Effect; siehe Wave-0-Hinweis in 02-01-SUMMARY.md, Open Items).
- Frische `HotkeyManager`-Instanz pro Test (via `makeManager()`) — kein State-Leak zwischen Tests.

## Open Items / Notes for Following Plans

- **Plan 02-03 (Pipeline-Fehlerpfade)** kann auf demselben Test-Target aufsetzen. Die in Wave 0 gebauten Fakes (FakeTranscriptionService, FakeRewriter, FakeAudioRecorder) sind bereit; ModeProcessor-Pipeline-Tests muessen den `HistoryStore`-Pfad scopen oder das History-Append meiden (Open Item aus 02-01-SUMMARY.md).
- **Pre-existing UX-Aenderungen** in `AppDelegate.swift` / `SettingsView.swift` warten auf einen separaten Commit (siehe `deferred-items.md`).

## Self-Check

| Item | Status |
| ---- | ------ |
| BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift | FOUND |
| 4 grep-pinned debounce tests | FOUND (count = 4) |
| 4 hold-mode tests | FOUND |
| 4 toggle-mode tests | FOUND |
| 5 modifier-combo tests | FOUND |
| Total func test_* >= 12 | FOUND (17) |
| 3x consecutive xcodebuild test gruen | PASS |
| Kein Thread.sleep / bare Date() | PASS |
| Commit 6ba3167 | FOUND |
| project.pbxproj enthaelt HotkeyStateMachineTests build-file | FOUND |

## Self-Check: PASSED
