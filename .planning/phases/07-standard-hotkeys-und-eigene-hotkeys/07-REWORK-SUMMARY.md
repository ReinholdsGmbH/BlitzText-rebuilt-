# Phase 7 Rework SUMMARY: Doppeltipp-Toggle

**Status:** DONE
**Datum:** 2026-05-19

## Entscheidung

Toggle via schnellem Doppeltipp der Hold-Kombo statt freier Carbon-Kombo.
Eliminiert Modifier-Konflikt zwischen Hold- und Toggle-Pfad vollständig.

## Rückbau (Wave 0)

Wurde in einem vorherigen Schritt durchgeführt (Carbon-Layer, KeyboardShortcuts SPM-Package,
TriggerMode-Enum, toggleHotkeyFor*-Properties, ToggleHotkeyRow/ConflictWarningBanner,
ToggleHotkeyTests.swift sind entfernt).

## Neuimplementierung (Wave 1)

### HotkeyManager.swift

- `lastReleaseTime: [Mode: Date]` — neue Property, merkt Release-Zeitstempel pro Mode
- `doubleTapThreshold: TimeInterval = 0.30` — 300 ms Fenster für Doppeltipp
- `decideTransition` prüft Doppeltipp vor Hold-Logik:
  - zweite Press-Edge desselben Mode innerhalb 300 ms nach Release → `.toggle(mode)`
  - Release-Eintrag wird nach Toggle-Auslösung gelöscht (kein falsches Re-Triggern)
  - Debounce (50 ms) wird auch für Toggle respektiert
- `holdOutcomes` zeichnet Release-Zeit auf: `lastReleaseTime[active] = now`

### HotkeyStateMachineTests.swift (3 neue Tests + 1 Anpassung)

- `test_doubleTap_triggersToggle`: Press/Release/Press innerhalb 300 ms → `.toggle(.blitztext)`
- `test_slowSecondTap_triggersHold`: zweiter Press 400 ms nach Release → `.start(.blitztext)`
- `test_hold_noRelease_noDoubleTap`: Halten ohne Release → idempotent `[]`
- `test_debounce_twoPressesAfterWindow`: Timing auf 500 ms korrigiert (war 200 ms → fiel in Doppeltipp-Fenster; Rule-1-Fix)

## Deviation

**[Rule 1 - Bug] test_debounce_twoPressesAfterWindow Timing-Kollision**

- **Gefunden bei:** Task 2/3 (Testausführung)
- **Problem:** Bestehender Test hatte zweiten Press bei t=0.2s (100 ms nach Release bei t=0.1s) — genau in der neuen 300 ms Doppeltipp-Zone. Test erwartete `.start`, bekam jetzt `.toggle`.
- **Fix:** Zweiten Press auf t=0.5s (400 ms nach Release) verschoben — außerhalb doubleTapThreshold.
- **Datei:** `BlitzTextTests/Hotkeys/HotkeyStateMachineTests.swift`
- **Commit:** 6cd5cd9

## Build + Test

- BUILD SUCCEEDED: ja
- HotkeyStateMachineTests: 16/16 grün (13 bestehend + 3 neu)

## Commits

- `95d80a7` — `feat(07-rework): Doppeltipp-Toggle — lastReleaseTime + decideTransition-Check`
- `6cd5cd9` — `test(07-rework): HotkeyStateMachineTests — 3 Doppeltipp-Tests + Timing-Fix`
