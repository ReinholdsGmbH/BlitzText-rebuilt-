# 07-05 SUMMARY: ToggleHotkeyTests

**Status:** DONE
**Wave:** 3
**Datum:** 2026-05-19

## Was wurde getan

ToggleHotkeyTests.swift mit 6 Tests in BlitzTextTests/Hotkeys/ erstellt.
Tests decken die testbaren Seams der Toggle-Hotkey-Funktionalitaet:
SC-2 (Persistenz + Validierungslogik), SC-4 (Conflict-Detection) und SC-1 (Hold-Regression).

xcodeproj via xcodegen regeneriert — ToggleHotkeyTests.swift ist in der
Hotkeys-Gruppe des BlitzTextTests-Targets registriert.

## Test-Ergebnisse

- ToggleHotkeyTests: 6/6 Tests gruen
- HotkeyStateMachineTests: 17/17 Tests gruen
- SpeakerMatchingTests: 1 bekannter Failure (testApplyDiarization_mixedSpeakers_correctLabels — Phase-4-Scope, nicht Phase-7)

## Neue Tests

- testToggleBinding_snapshotRoundtrip: gruen
- testDuplicateBinding_detectedInState: gruen
- testFnModifier_invalidForToggle: gruen
- testModifierOnly_invalid: gruen
- testConflict_spotlightBindingDetected: gruen
- testHoldBindings_unaffectedByToggleOperations: gruen

## Design-Entscheidungen

**HotkeyBinding ist Hashable:** Plan 07-03 hat `HotkeyBinding: Hashable` als Bug-Fix
ergaenzt (bcca20c). Der `testConflict_spotlightBindingDetected`-Test nutzt daher
ein `[HotkeyBinding: String]`-Dictionary statt eines Arrays — konsistent mit der
tatsaechlichen Implementierung in HotkeysTab (SettingsView.swift).

**save() ist internal:** SettingsStore.save() hat keine Zugriffsbeschraenkung (internal).
Der Snapshot-Roundtrip-Test kann save() direkt aufrufen, ohne Debounce-Wartezeit.

**carbonModifierFlag als Int:** HotkeyModifier.carbonModifierFlag gibt `Int` zurueck
(angepasst in Plan 07-03 an die KeyboardShortcuts-API). testFnModifier_invalidForToggle
vergleicht `== 0` korrekt als Int-Vergleich.

## Deviationen

Keine — Plan executed exactly as written.
HotkeyBinding war wie in 07-03-SUMMARY dokumentiert Hashable (nicht wie in der
urspruenglichen 07-04-SUMMARY-Deviation beschrieben) — Dictionary-Ansatz funktioniert.

## Commits

- bf9d685 test(07-05): ToggleHotkeyTests — 6 Tests fuer SC-1/SC-2/SC-4

## Self-Check

- [x] BlitzTextTests/Hotkeys/ToggleHotkeyTests.swift existiert
- [x] grep "func test" BlitzTextTests/Hotkeys/ToggleHotkeyTests.swift | wc -l = 6 (>= 5)
- [x] Test Suite 'ToggleHotkeyTests' passed (6/6)
- [x] HotkeyStateMachineTests weiterhin gruen (Hold-Pfad unveraendert)
- [x] Kein neuer Failure ausser vorbestehendem SpeakerMatchingTests-Issue
- [x] Commit bf9d685 existiert
