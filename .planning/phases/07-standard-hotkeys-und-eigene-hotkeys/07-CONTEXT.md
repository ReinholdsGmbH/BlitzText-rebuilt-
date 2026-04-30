# Phase 999.6 Context: Standard-Hotkeys und Vergabe eigener Hotkeys

**Captured:** 2026-04-30
**Phase status:** BACKLOG (999.x — unsequenced parking lot)
**Source:** `/gsd-discuss-phase 999.6`

## <domain>

**Capability:** Default-Hotkey-Set ausliefern UND Nutzer:innen erlauben, eigene Hotkeys frei zu vergeben.

**Heutiger Stand (Code):**
- Hotkeys hartkodiert in [HotkeyManager.swift](../../../BlitzText/Hotkeys/HotkeyManager.swift): fn+Shift = Blitztext, fn+Ctrl = Blitztext+, fn+Option = Blitztext $%&!
- CGEventTap auf `.flagsChanged` — nur fn+Modifier-Kombos beobachtet, keine Buchstaben/Zahlen
- 3 Modes (`Mode`-Enum in [Mode.swift](../../../BlitzText/Modes/Mode.swift)) gemappt 1:1 auf 3 Hotkeys
- TriggerMode (hold/toggle) bereits konfigurierbar in [SettingsStore](../../../BlitzText/Settings/SettingsStore.swift)

**Phase-Boundary:** Default-Hotkeys + Custom-Bindings für die bestehenden 3 Modes. Weder neue Modes noch globale Aufnahme-/Cancel-Shortcuts oder Snippet-Hotkeys (das wären eigene Phases).

## <decisions>

### Trigger-Architektur

- **Hybrid-Schema:** fn-Schnellpfad (CGEventTap, wie heute) bleibt **für Hold-Mode** erhalten — niedrige Latenz beim Halten ist Markenversprechen aus PROJECT.md ("≤ 3 s end-to-end"). Zusätzlich kann pro Mode eine **freie Tastenkombo** (z.B. ⌘⇧B) für **Toggle-Mode** hinterlegt werden.
- **Implementierungspfad freie Kombos:** externes Swift-Package — Kandidaten `soffes/HotKey` oder `shpakovski/MASShortcut`. Researcher prüft Swift-6-Concurrency-Kompatibilität (project nutzt `SWIFT_STRICT_CONCURRENCY: minimal`) und liefert Empfehlung.
- **Konsequenz:** zwei parallele Hotkey-Pfade nebeneinander — bestehender CGEventTap bleibt unverändert; neuer Pfad ist additiv. Pipeline-Trigger (`onTrigger(Mode, Action)`) bleibt gemeinsame Schnittstelle.

### Default-Set & Migration

- **Defaults bei Erst-Install und Reset:** Hold-Pfad behält fn+Shift / fn+Ctrl / fn+Option (1:1 wie heute). Toggle-Pfad startet **leer** — User belegt selbst, wenn gewünscht.
- **Migration bestehender Nutzer:** keine erzwungene Änderung. Nutzer, die heute fn+Modifier nutzen, sehen exakt das gleiche Verhalten. Custom-Toggle-Bindings sind opt-in.
- **Persistenz:** Custom-Bindings werden im bestehenden `SettingsStore` (UserDefaults JSON) abgelegt — same Snapshot-Pattern wie restliche Prefs. Researcher prüft Datenmodell (Codable struct mit `mode`, `holdHotkey`, `toggleHotkey`).

### UI für Vergabe

- **Layout:** **eigener Settings-Tab "Hotkeys"** (neben Allgemein, Zugang, Modi etc. in [SettingsView.swift](../../../BlitzText/Settings/SettingsView.swift)).
- **Struktur:** Tabelle mit einer Zeile pro Mode. Spalten: Mode-Name + Beschreibung, Hold-Hotkey (fn+…), Toggle-Hotkey (frei via Recorder), Reset-Button.
- **Recorder:** Standard-Komponente aus dem gewählten SPM-Package (HotKey/MASShortcut liefern beide eine Recorder-View). Falls keine geeignete Komponente: eigene NSEvent-basierte Recorder-View — Researcher entscheidet.

### Konflikt- & Reset-Verhalten

- **System-Konflikte:** **nachsichtig** — App registriert die Kombo trotzdem; bei möglicher Kollision (Spotlight, Mission Control etc.) erscheint ein **dezentes Warn-Banner** im Hotkeys-Tab, die Kombo bleibt gesetzt. Researcher klärt, ob System-Hotkeys via API überhaupt zuverlässig erkennbar sind (sonst Fallback: kuratierte Liste bekannter System-Kombos).
- **In-App-Doppelbelegung:** wird im Recorder **vorab verhindert** — wer ⌘⇧B bereits an Mode A gebunden hat, kann es nicht zusätzlich für Mode B setzen. Klare Inline-Fehlermeldung.
- **Reset:** **pro-Hotkey-Reset-Button** in jeder Tabellenzeile. Setzt nur diese eine Bindung auf Default zurück (Hold-Default oder leer für Toggle). Kein globaler "Alle zurücksetzen".
- **Edge-Case "nur Modifier":** Kombos ohne Buchstaben/Zahl/F-Taste werden vom Recorder abgelehnt (würden mit fn-Pfad kollidieren).

## <canonical_refs>

Downstream agents (researcher, planner) müssen diese Dateien lesen:

- [.planning/ROADMAP.md](../../ROADMAP.md) — Phase 999.6 Eintrag im Backlog
- [.planning/PROJECT.md](../../PROJECT.md) — Performance-Constraint (≤ 3 s end-to-end), Tech-Stack (Swift 6 strict-concurrency: minimal, kein Sandbox)
- [.planning/REQUIREMENTS.md](../../REQUIREMENTS.md) — kein direktes v1-Requirement, Phase ist BACKLOG
- [.planning/codebase/STRUCTURE.md](../../codebase/STRUCTURE.md) — Dir-Layout (`BlitzText/Hotkeys/`, `BlitzText/Settings/`)
- [.planning/codebase/CONVENTIONS.md](../../codebase/CONVENTIONS.md) — Naming, SwiftUI-Patterns
- [BlitzText/Hotkeys/HotkeyManager.swift](../../../BlitzText/Hotkeys/HotkeyManager.swift) — bestehender CGEventTap-Pfad, Debounce-Konstanten, Hold/Toggle-Statemachine
- [BlitzText/Settings/SettingsStore.swift](../../../BlitzText/Settings/SettingsStore.swift) — Snapshot-Pattern für Persistenz, `triggerMode`-Property
- [BlitzText/Settings/SettingsView.swift](../../../BlitzText/Settings/SettingsView.swift) — bestehende Tab-Struktur, in die der neue "Hotkeys"-Tab integriert wird
- [BlitzText/Modes/Mode.swift](../../../BlitzText/Modes/Mode.swift) — Mode-Enum, an dem die Bindings hängen

## <code_context>

**Wiederverwendbare Assets:**
- `HotkeyManager.onTrigger: (Mode, Action) -> Void` — gemeinsamer Trigger-Callback; neuer Pfad ruft den gleichen Callback
- `SettingsStore.Snapshot` Pattern — etablierte Migrations-fähige UserDefaults-Persistenz mit `?? default`-Fallback für neue Felder
- `SettingsView` Tab-Struktur — neue Tabs werden hier eingehängt; Konvention: deutsche Tab-Labels
- Debounce-Konstanten in `HotkeyManager` (`holdDebounce: 0.05`, `toggleDebounce: 0.30`) — Werte stehen in Phase 1 zur Doku-Konsistenz an, sollten in 999.6 nicht redundant geändert werden

**Integrationspunkte:**
- `AppDelegate.bootstrap()` instanziiert `HotkeyManager` — neuer freier-Kombo-Pfad muss hier ebenfalls verdrahtet werden
- `ModeProcessor` ist Pipeline-Brain — Hotkey-Pfade triggern es nur, keine Pipeline-Änderung nötig

**Risiken / Landminen:**
- Swift-6-Concurrency: bestehender HotkeyManager nutzt `@unchecked Sendable` für CGEvent-Callbacks. Externes SPM-Package muss kompatibel sein oder ähnlich umflaggbar.
- TCC-Permission: freie globale Hotkeys benötigen ebenfalls Accessibility — bereits erteilt für CGEventTap, sollte automatisch funktionieren. Researcher verifiziert.
- Doppelte Hotkey-Registrierung beim App-Restart: NSEvent-Monitor + Carbon-Hotkeys müssen sauber `unregister`-bar sein, sonst Memory-Leak / Doppelfeuer.

## <deferred>

Während der Diskussion erwähnt, aber außerhalb der Phase-Boundary:

- _(keine — Diskussion blieb scope-konform)_

## <next_steps>

Phase ist im Backlog. Bei Promotion zur aktiven Phase:

```
/gsd-plan-phase 999.6
```

Vorher idealerweise `/gsd-review-backlog` ausführen, um zu entscheiden, in welche Milestone die Phase einsortiert wird.

---
*Context erfasst: 2026-04-30 via /gsd-discuss-phase 999.6*
