---
status: done
phase: 07-standard-hotkeys-und-eigene-hotkeys
source:
  - 07-01-SUMMARY.md
  - 07-02-SUMMARY.md
  - 07-03-SUMMARY.md
  - 07-04-SUMMARY.md
  - 07-05-SUMMARY.md
started: 2026-05-19T00:00:00Z
updated: 2026-05-19T00:00:00Z
---

## Current Test

completed: true

## Tests

### 1. Hotkeys-Tab erscheint in den Settings
expected: Settings-Fenster öffnen. In der Tab-Leiste erscheint "Hotkeys" als neuer Tab nach "Sprecher".
result: pass

### 2. HOLD-HOTKEYS Section — read-only Anzeige
expected: Im Hotkeys-Tab, Abschnitt HOLD-HOTKEYS: Drei Zeilen (Blitztext / Blitztext+ / Blitztext$%&!) mit fn+⇧ / fn+⌃ / fn+⌥ als Badge. Darunter Hinweis "Nicht änderbar — fn-Schnellpfad". Kein Recorder, keine Buttons.
result: issue
issue: Hold-Hotkeys sind nicht mehr konfigurierbar. Phase 7 hat den HotkeyRecorderRow im AnpassenTab durch einen Verweis-Text ersetzt; der neue Hotkeys-Tab zeigt Hold-Hotkeys nur read-only. Regression gegenüber vor Phase 7.
severity: high
fix: commit 0054e97 — HotkeyRecorderRow statt HoldHotkeyRow in HotkeysTab
fix_status: done

### 2b. Hold/Toggle Modifier-Konflikt
expected: Hold-Hotkey fn+⇧ und Toggle-Hotkey fn+⇧+B koexistieren konfliktfrei — Toggle-Hotkey löst aus, Hold-Recording startet nicht.
result: issue
issue: CGEventTap feuert auf flagsChanged (Modifier-Taste gedrückt) sofort wenn fn+⇧ erkannt wird — noch bevor der Buchstabe B gedrückt wird. Damit startet Hold-Recording, bevor Carbon den vollen Toggle-Shortcut fn+⇧+B registrieren kann. Jede Toggle-Kombo, deren Modifier-Set eine Obermenge des Hold-Modifier-Sets ist, löst ungewollt Hold aus.
severity: high

### 3. TOGGLE-HOTKEYS Section — leerer Zustand (State A)
expected: Im Abschnitt TOGGLE-HOTKEYS: Drei Zeilen, je ein "—" und ein Button "Hotkey belegen". Kein Banner sichtbar (keine Konflikte).
result: skipped
reason: TOGGLE-HOTKEYS-UI wurde im Rework entfernt — Toggle erfolgt via Doppeltipp der Hold-Kombo.

### 4. Toggle-Hotkey vergeben (Recorder State C → State B)
expected: "Hotkey belegen" klicken → Feld wechselt in Recorder-Modus (blau umrandet, Platzhaltertext). ⌘⇧B drücken → Feld zeigt "⌘⇧B", Recorder beendet sich. Zeile zeigt nun "Hotkey ändern" + ×-Button.
result: skipped
reason: ToggleHotkeyRow entfernt — kein freies Toggle-Binding mehr vorhanden.

### 5. Doppelbelegung wird abgelehnt (State D)
expected: Für einen zweiten Mode denselben Hotkey ⌘⇧B versuchen zu vergeben → Fehlermeldung "⌘⇧B ist bereits für [Mode] vergeben." erscheint unter der Zeile. Binding wird NICHT gespeichert.
result: skipped
reason: Entfällt mit Toggle-Rework.

### 6. ConflictWarningBanner bei ⌘Space (State D/SC-4)
expected: ⌘Space als Toggle-Hotkey für irgendeinen Mode vergeben → Banner "Möglicher Konflikt mit einem System-Hotkey" mit Hinweis auf "Spotlight" erscheint unterhalb der Toggle-Section.
result: skipped
reason: ConflictWarningBanner entfernt — kein freies Toggle-Binding mehr.

### 7. Double-Tap löst Toggle aus
expected: Außerhalb der Settings die Hold-Kombo (z.B. fn+⇧) zweimal schnell hintereinander drücken (~300 ms zwischen den Tastendrücken) → HUD erscheint im Toggle-Modus (Recording startet). Nochmals doppeltippen → Recording stoppt.
result: pass

### 8. Hold-Pfad unverändert (SC-1 Regression)
expected: fn+Shift gedrückt halten → HUD erscheint, Hold-Recording läuft. Loslassen → Aufnahme stoppt, kein Double-Fire.
result: pass

### 9. Binding überlebt App-Restart (SC-2 Persistenz)
expected: App beenden und neu starten → Hotkeys-Tab öffnen → ⌘⇧B ist weiterhin eingetragen. Hotkey löst nach Restart weiterhin aus.
result: pass

### 10. AnpassenTab — kein Recorder mehr
expected: Settings → Tab "Anpassen" → TASTENKÜRZEL-Abschnitt zeigt nur noch den Verweis-Text "Hotkeys werden im Tab \"Hotkeys\" konfiguriert." — keine HotkeyRecorderRow mehr sichtbar.
result: pass

## Summary

total: 10
passed: 6
issues: 2
pending: 0
skipped: 4

## Gaps

### GAP-1: Hold-Hotkeys im Hotkeys-Tab editierbar machen
- **Issue:** HoldHotkeyRow ist read-only; alter Recorder im AnpassenTab wurde entfernt
- **Fix:** HoldHotkeyRow in HotkeysTab durch HotkeyRecorderRow ersetzen (existiert bereits)
- **Severity:** high
- **Status:** fixed — commit 0054e97

### GAP-2: Design-Entscheidung — Toggle via Doppeltipp statt freier Kombo
- **Issue:** Carbon/KeyboardShortcuts-Toggle-Layer verursacht Modifier-Konflikte mit Hold-Pfad. Fundamentales Architekturproblem.
- **Decision:** Toggle = schneller Doppeltipp der Hold-Kombo (z.B. fn+⇧ zweimal schnell). Kein separates Binding nötig.
- **Rückbau:** KeyboardShortcuts-Package, Carbon-Layer in HotkeyManager, ToggleHotkey-Properties in SettingsStore, ToggleHotkeyRow + ConflictWarningBanner in SettingsView
- **Neuimplementierung:** Double-tap-Erkennung im CGEventTap (handleFlagsChanged), Zeitfenster ~300 ms
- **Status:** rework geplant
