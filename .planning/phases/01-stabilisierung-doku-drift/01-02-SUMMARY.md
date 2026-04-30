---
phase: 01-stabilisierung-doku-drift
plan: 02
subsystem: hotkeys
tags: [refactor, docs, stab-02]
requires: []
provides:
  - "HotkeyManager.holdDebounce / toggleDebounce als benannte Konstanten"
  - "ARCHITECTURE.md mit Debounce-Rationale"
affects:
  - BlitzText/Hotkeys/HotkeyManager.swift
  - .planning/codebase/ARCHITECTURE.md
tech-stack:
  added: []
  patterns:
    - "private static let mit Doc-Comment für Tuning-Werte"
key-files:
  created: []
  modified:
    - BlitzText/Hotkeys/HotkeyManager.swift
    - .planning/codebase/ARCHITECTURE.md
decisions:
  - "Konstanten als private static let — Phase 2 öffnet sie auf internal, sobald Test-Target existiert"
metrics:
  duration: "~5 min"
  completed: 2026-04-30
  tasks_completed: 2
  files_changed: 2
---

# Phase 1 Plan 02: Hotkey-Debounce-Konstanten + Doku-Alignment Summary

Magic Numbers `0.05` und `0.3` im `HotkeyManager` zu benannten `private static let` mit Rationale-Doc-Comment hochgezogen; ARCHITECTURE.md um Debounce-Begründungs-Bullet ergänzt.

## Was wurde gebaut

- `HotkeyManager.holdDebounce: TimeInterval = 0.05` — 50 ms, schluckt CGEvent-Doppelfeuer ohne fn+Shift-Antipper zu verlieren.
- `HotkeyManager.toggleDebounce: TimeInterval = 0.30` — 300 ms, blockt ungewollte Doppeltipps.
- Beide mit deutschem Doc-Comment, Quelle: empirisch am M1.
- `handleHoldTransition` und `handleToggleTransition` referenzieren `Self.holdDebounce` / `Self.toggleDebounce`.
- Inline-Kommentar `// Debounce` entfernt (Property-Doc trägt die Information).
- ARCHITECTURE.md Zeile 209: neuer Bullet "Debounce-Rationale" verlinkt auf `static let` im HotkeyManager.

## Diff-Zusammenfassung

| Datei | Änderung |
| --- | --- |
| `BlitzText/Hotkeys/HotkeyManager.swift` | +14 / −3 (MARK-Block + Konstanten + 2 Call-Site-Refactors) |
| `.planning/codebase/ARCHITECTURE.md` | +4 / −0 (Rationale-Bullet) |

## Commits

- `cdcf6f3` refactor(stab-02): Hotkey-Debounce-Magic-Numbers in benannte Konstanten ziehen
- `2655b24` docs(stab-02): Debounce-Rationale in ARCHITECTURE.md ergänzen

## Verifikation

Plan-Verification-Block:

```
grep -nE "0\.05|0\.30|Self\.(hold|toggle)Debounce" BlitzText/Hotkeys/HotkeyManager.swift
```

Output:
```
87:    private static let holdDebounce: TimeInterval = 0.05
91:    private static let toggleDebounce: TimeInterval = 0.30
122:        if Date().timeIntervalSince(lastTriggerAt) < Self.holdDebounce { return }
139:        if Date().timeIntervalSince(lastTriggerAt) < Self.toggleDebounce { return }
```

Genau wie gefordert: 2 Konstanten-Definitionen, 2 Call-Sites.

Build:
```
xcodegen generate && xcodebuild -project BlitzText.xcodeproj -scheme BlitzText -configuration Debug -destination 'platform=macOS' build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
→ ** BUILD SUCCEEDED **
```

Dokumentations-Konsistenz:
```
! grep -nE "250\s*ms|250ms|0\.25\s*s" .planning/codebase/ARCHITECTURE.md  → keine Treffer
grep -q "50 ms hold, 300 ms toggle" .planning/codebase/ARCHITECTURE.md    → OK
grep -q "Debounce-Rationale" .planning/codebase/ARCHITECTURE.md           → OK
```

## Deviations from Plan

Keine. Hinweise:
- Schritt "250 ms"-Vorkommen ersetzen war ein No-Op — die Doku enthielt bereits korrekte Werte (50/300 ms). Nur die Rationale fehlte.
- Refresh-Marker am Datei-Anfang stand bereits auf `2026-04-30` (= heute) — keine Änderung nötig.

## Hinweis für Phase 2 (TEST-02)

Konstanten sind aktuell `private static`. Sobald ein Test-Target existiert und die Werte als Test-Anker gebraucht werden, im Phase-2-Plan explizit auf `internal static` öffnen — dann kann `HotkeyManager.holdDebounce` / `.toggleDebounce` direkt referenziert werden, ohne die Werte hardzucoden.

## Manueller Smoke-Test

Nicht ausgeführt (kein Verhalten geändert — reines Refactor mit identischen Konstanten-Werten). Empfehlung an Phase-1-Verifier: kurzer fn+Shift Hold-Test + fn+Shift Toggle-Test als Sanity-Check.

## Self-Check: PASSED

- `BlitzText/Hotkeys/HotkeyManager.swift` enthält `holdDebounce`/`toggleDebounce` und Self.-Referenzen — verified per grep.
- `.planning/codebase/ARCHITECTURE.md` enthält `Debounce-Rationale` und `50 ms hold, 300 ms toggle` — verified per grep.
- Commits `cdcf6f3` und `2655b24` existieren in `git log`.
- Build erfolgreich (`** BUILD SUCCEEDED **`).
