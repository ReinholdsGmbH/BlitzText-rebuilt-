---
phase: 01-stabilisierung-doku-drift
plan: 03
subsystem: hotkeys
tags: [accessibility, permissions, watcher, ux]
requires: ["01-02"]
provides:
  - "HotkeyManager.installEventTap() (idempotent)"
  - "HotkeyManager.startPermissionWatcher() (1 Hz DispatchSourceTimer)"
affects:
  - BlitzText/Hotkeys/HotkeyManager.swift
  - BlitzText/Settings/SettingsView.swift
  - BlitzText/Settings/Keychain.swift
tech-stack:
  added: []
  patterns: ["DispatchSourceTimer auf .main", "idempotente Init via guard nil-check"]
key-files:
  modified:
    - BlitzText/Hotkeys/HotkeyManager.swift
    - BlitzText/Settings/SettingsView.swift
    - BlitzText/Settings/Keychain.swift
decisions:
  - "Polling mit 1 Hz statt KVO/Notification: AXIsProcessTrusted hat keinen offiziellen Notify-Mechanismus; 1 Hz ist billig (paar µs/Tick) und User-spürbar instant."
  - "Watcher nutzt AXIsProcessTrusted() ohne Options-Dictionary, um nicht jeden Tick einen System-Prompt auszulösen — der prompt-auslösende Pfad bleibt ensureAccessibilityPermission() (User-initiierter Start)."
  - "Watcher-Lifecycle: Selbstabschaltung nach erstem true. Kein Auto-Stop bei Dauer-Denial (STAB-03 fordert das nicht; auf Backlog verschiebbar)."
requirements: [STAB-03]
metrics:
  duration: "~10 min"
  completed: "2026-04-30"
  tasks: 2
  files_changed: 3
---

# Phase 1 Plan 03: STAB-03 Auto-Recovery Accessibility-Permission Summary

Tap installiert sich automatisch, sobald der User die Bedienungshilfen-Permission erteilt — kein App-Restart mehr.

## Diff-Zusammenfassung

**`BlitzText/Hotkeys/HotkeyManager.swift`** (+40/-12)
- Neue Property `permissionTimer: DispatchSourceTimer?`.
- `start()` reduziert auf `if AXIsProcessTrusted() { installEventTap() } else { startPermissionWatcher() }`.
- `installEventTap()` extrahiert (Body identisch zum bisherigen Tap-Aufbau, plus `guard eventTap == nil` für Idempotenz).
- `startPermissionWatcher()`: `DispatchSource.makeTimerSource(queue: .main)`, deadline +1 s / repeating 1 s. EventHandler prüft `AXIsProcessTrusted()` (prompt-frei), bei `true` → `cancel()`, `permissionTimer = nil`, `installEventTap()`.
- `stop()` cancelt zusätzlich `permissionTimer`.
- Datei-Header dokumentiert das 1-Hz-Polling-Verhalten.

**`BlitzText/Settings/SettingsView.swift`** (+1/-1)
- Caption-Text: „… BlitzText einmal beenden und neu starten …" → „… sind die Hotkeys sofort aktiv — kein App-Neustart nötig."

**`BlitzText/Settings/Keychain.swift`** (+4/-2)
- Header-Kommentar verlinkt explizit auf `Scripts/create-signing-cert.sh` und erklärt den Ad-hoc-Signing-Fall (Code-Hash wechselt → Prompt erscheint erneut).

## Commits

| Task | Hash      | Message                                                                                |
| ---- | --------- | -------------------------------------------------------------------------------------- |
| 1    | `92bc4f7` | feat(stab-03): Auto-Recovery für Accessibility-Permission ohne App-Restart             |
| 2    | `c273bb2` | docs(stab-03): Permission-Hilfetext und Keychain-Kommentar entstauben                  |

## Verification Result

**Automated**

- `grep -c "installEventTap\b" HotkeyManager.swift` → `3` (≥3 ✓: Aufruf in `start()`, Aufruf in Watcher, Methodendefinition).
- `grep -q "startPermissionWatcher"` → ✓.
- `grep -qF "permissionTimer?.cancel"` → ✓ (zweimal: in `stop()` und im Watcher-EventHandler).
- `xcodegen generate` → ✓.
- `xcodebuild … build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` → **BUILD SUCCEEDED** ✓ (keine Concurrency-Warnungen).
- Task 2: Restart-String entfernt ✓, „kein App-Neustart nötig" vorhanden ✓, „BlitzText Local Dev" in Keychain.swift vorhanden ✓.

**Idempotenz / Race-Schutz** (statisch geprüft via grep):

```
44:        permissionTimer?.cancel()           // stop()
57:        guard eventTap == nil else { return }   // installEventTap() — kein doppelter Tap
93:        guard permissionTimer == nil else { return }   // startPermissionWatcher() — kein doppelter Timer
100:                self.permissionTimer?.cancel()   // Watcher-EventHandler — Selbstabschaltung
```

**Manueller End-to-End-Permission-Test**

> ⚠️ Manueller Test laut Plan vom User auszuführen. Test-Drehbuch:
>
> 1. Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → BlitzText-Eintrag entfernen (oder Toggle aus). App vorher beenden.
> 2. App starten → Log enthält:
>    `HotkeyManager.start() — AXIsProcessTrusted = false`
>    `Accessibility fehlt — Hotkeys aus, beobachte TCC-Status (1 Hz Polling).`
> 3. In Systemeinstellungen die Permission jetzt aktivieren (Toggle an, ggf. Touch-ID).
> 4. Innerhalb 1–2 s erscheint im Log **ohne App-Restart**:
>    `HotkeyManager: Accessibility erteilt — Tap wird gestartet.`
>    `CGEventTap aktiv — fn-Modifier wird beobachtet.`
> 5. fn+Shift halten → Aufnahme startet. Loslassen → stoppt.

## Hinweise / Backlog-Kandidaten

- **Polling-Frequenz**: 1 Hz. Watcher läuft auf `.main` und ist deshalb in Aufnahme-Pausen vernachlässigbar. Bei späteren Performance-Bedenken könnte ein Auto-Stop nach z. B. 10 min ohne Grant ergänzt werden. STAB-03 fordert das nicht — bewusst ausgelassen.
- **Concurrency**: `HotkeyManager` bleibt `@unchecked Sendable`. Der Watcher-EventHandler läuft auf `.main` (kein zusätzlicher Hop nötig). Build ohne neue Warnungen.
- **Keychain-Kommentar**: Bleibt inhaltlich gültig. Mit Plan 01-01 wird Keychain.shared aktiv — der Self-Signed-Cert-Hinweis ist jetzt user-relevant (statt nur Notiz für die Zukunft).

## Deviations from Plan

None — Plan exakt wie geschrieben umgesetzt.

## Self-Check: PASSED

- `BlitzText/Hotkeys/HotkeyManager.swift` ✓ (modifiziert)
- `BlitzText/Settings/SettingsView.swift` ✓ (modifiziert)
- `BlitzText/Settings/Keychain.swift` ✓ (modifiziert)
- Commit `92bc4f7` ✓ (in `git log`)
- Commit `c273bb2` ✓ (in `git log`)
- Build SUCCEEDED ✓
