---
phase: 7
slug: standard-hotkeys-und-eigene-hotkeys
status: approved
reviewed_at: 2026-05-19
shadcn_initialized: false
preset: none
created: 2026-05-19
---

# Phase 7 — UI Design Contract: Standard-Hotkeys und eigene Hotkeys

> Visual- und Interaktionsvertrag für den neuen "Hotkeys"-Tab im Settings-Fenster.
> Generiert von gsd-ui-researcher. Wird von gsd-ui-checker verifiziert.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none — native macOS SwiftUI + AppKit |
| Preset | not applicable |
| Component library | SwiftUI built-ins (keine Drittbibliothek) |
| Icon library | SF Symbols (system) |
| Font | .system() — macOS System Font (SF Pro) |

**Quelle:** Codebase-Scan (SettingsView.swift — alle anderen Tabs nutzen dieselbe Basis)

---

## Spacing Scale

Native macOS Points (pt), entsprechen dem etablierten 8-pt-Raster im Projekt:

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4 pt | Icon-Gaps, inline between modifier badges, Badge vertical padding |
| sm | 8 pt | Padding innerhalb von Recorder-Feldern, Row-internal gaps, Chip horizontal padding |
| md | 16 pt | Abstand zwischen Tabellen-Zeilen, horizontaler Padding in Rows |
| lg | 20 pt | Tab-Content-Padding (etabliert: `.padding(20)`) |
| xl | 24 pt | Abstand zwischen Sections (VStack spacing: 16–24) |
| 2xl | 32 pt | — (nicht genutzt in Settings-Tab-Kontext) |
| 3xl | 64 pt | — (nicht genutzt in Settings-Tab-Kontext) |

Exceptions:
- Row-internal padding: 8 pt (`.padding(8)` — auf 4-pt-Raster)
- Section-VStack spacing: 8 pt (identisch mit allen bestehenden Sections — `VStack(alignment: .leading, spacing: 8)`)
- Tab-level VStack spacing: 16 pt (`VStack(alignment: .leading, spacing: 16)` — auf 4-pt-Raster)

Alle anderen Spacing-Werte liegen auf dem 4-pt-Raster. Kein 1 pt, 2 pt, 3 pt oder 6 pt im Layout erlaubt.

**Quelle:** Codebase-Scan (SettingsView.swift — Messung an `SpeakerRow`, `LocalModelRow`, `AnpassenTab`)

---

## Typography

Native SwiftUI Text-Styles — keine Custom-Font-Sizes. Mapping auf macOS-Systemwerte:

| Role | SwiftUI Style | Pt (approx.) | Weight | Usage |
|------|--------------|--------------|--------|-------|
| Section Header | `.caption` + `.bold()` | 11 pt | Semibold (600) | Section-Titel in ALLCAPS (z.B. "HOLD-HOTKEYS") |
| Row Title | `.body` + `.bold()` | 13 pt | Semibold (600) | Mode-Name (z.B. "Blitztext") — `Text(mode.title).font(.body).bold()` |
| Row Subtitle | `.body` (default) | 13 pt | Regular (400) | Binding-Anzeige, sekundäre Row-Labels |
| Caption / Hint | `.caption` | 11 pt | Regular (400) | Erklärungstexte unter Sections, Banner-Body |
| Fine Print | `.caption2` | 10 pt | Regular (400) | Sekundäre Infos, mode.subtitle, Tooltip-Ersatz-Texte |
| Banner Header | `.body` + `.bold()` | 13 pt | Semibold (600) | ConflictWarningBanner Titel-Zeile |

Heading Line Height: 1.2 (System-Default bei `.caption` bold)
Body Line Height: 1.4 (System-Default bei `.body`)

**Quelle:** Codebase-Scan (AnpassenTab, SprecherTab — identische Verwendung durchgehend)

---

## Color

Ausschliesslich macOS-System-Farben — keine Hard-coded Hex-Werte:

| Role | SwiftUI Value | Usage |
|------|--------------|-------|
| Dominant (60%) | `.background` (System-Window-Background) | Tab-Hintergrund, ScrollView-Fläche |
| Secondary (30%) | `.quaternary` (system adaptive) | Row-Hintergründe (HStack + RoundedRectangle), Recording-Feld-Idle |
| Accent (10%) | `.accentColor` | Recorder-Feld im aktiven Aufnahme-Zustand (Rahmen + Hintergrund tinted), "Hotkey ändern"-Button primary |
| Destructive | `.red` | Reset-Icon-Button falls Binding explizit gelöscht wird; nicht für den Reset-auf-Default-Button |
| Warning | `.orange` | Conflict-Warning-Banner (Hintergrund: `Color.orange.opacity(0.1)`, Icon: `exclamationmark.triangle.fill`) |
| Success | `.green` | Nicht in diesem Tab verwendet |

Accent reserved for:
1. Recorder-Feld im Aufnahme-Modus — Border: `Color.accentColor` lineWidth 1, Background: `Color.accentColor.opacity(0.12)`
2. Primär-Action-Button wenn vorhanden (analog `.buttonStyle(.borderedProminent)`)

**NICHT** für: Row-Backgrounds, Section-Header, Standard-Labels, Hold-Hotkey-Anzeige-Badge

**Quelle:** CONTEXT.md (Locked: "dezentes Warn-Banner"), Codebase-Scan (HotkeyRecorderRow Zeile 1052–1053 für Accent-Pattern)

### Visuals

Visueller Anker im aktiven Zustand: ToggleHotkeyRow mit `.accentColor`-Border (Recorder-Modus State C).

---

## Surface 1: HotkeysTab (neuer Settings-Tab)

### Tab-Integration

- Tab-Label: `"Hotkeys"` (Deutsch, einheitlich mit "Anpassen", "Zugang", "Lokales Modell", "Sprecher")
- Tab-Case im `SettingsView.Tab`-Enum: `.hotkeys`
- Position: nach `.sprecher`, vor Ende der `Tab.allCases`-Liste
- Fensterbreite bleibt 560 pt (keine Änderung nötig — alle Inhalte passen)

### Layout-Struktur

```
ScrollView
  VStack(alignment: .leading, spacing: 16)
    ┌─ Section "HOLD-HOTKEYS" ───────────────────────────────┐
    │  Caption: "fn + Modifier — Halten aktiviert Aufnahme"  │
    │  HoldHotkeyRow(mode: .blitztext)                       │
    │  HoldHotkeyRow(mode: .blitztextPlus)                   │
    │  HoldHotkeyRow(mode: .blitztextRant)                   │
    └────────────────────────────────────────────────────────┘
    Divider
    ┌─ Section "TOGGLE-HOTKEYS" ─────────────────────────────┐
    │  Caption: "Freie Tastenkombination — optional"         │
    │  ToggleHotkeyRow(mode: .blitztext)                     │
    │  ToggleHotkeyRow(mode: .blitztextPlus)                 │
    │  ToggleHotkeyRow(mode: .blitztextRant)                 │
    └────────────────────────────────────────────────────────┘
    Divider (nur wenn ConflictBanner sichtbar)
    ConflictWarningBanner (conditional — nur bei Konflikt)
```

---

## Surface 2: HoldHotkeyRow

Read-only Zeile. Hold-Hotkeys (fn+Modifier) sind **nicht editierbar** — CGEventTap-Pfad bleibt unverändert (CONTEXT.md Decision: "Hold-Pfad bleibt unverändert").

### Layout

```
HStack(spacing: 8)
  [Mode-Icon]  SF Symbol (mode.systemImage), foreground .secondary, frame width 20
  VStack(alignment: .leading, spacing: 0)   // spacing: 0 — Label direkt über Subtitle, kein Gap nötig
    Text(mode.title)  .font(.body) .bold()
    Text(mode.subtitle)  .font(.caption2) .foregroundStyle(.secondary)
  Spacer()
  [BindingBadge]  Read-only Modifier-Anzeige
```

### BindingBadge (Hold, read-only)

```
HStack(spacing: 4)
  ForEach(orderedModifiers) { ModifierKey(symbol: $0.symbol) }
.padding(.horizontal, 8)
.padding(.vertical, 4)
.background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
```

Einzelner Modifier-Chip:
```
Text(symbol)  // z.B. "fn", "⇧", "⌃", "⌥"
  .font(.system(.caption, design: .monospaced))
  .padding(.horizontal, 8)   // 8 pt — auf 4-pt-Raster (zuvor 6 pt)
  .padding(.vertical, 4)     // 4 pt — auf 4-pt-Raster (zuvor 2 pt)
  .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
```

Kein Button, kein Reset. Label unter dem Badge: `"Nicht änderbar — fn-Schnellpfad"` als `.caption2 .foregroundStyle(.tertiary)`.

---

## Surface 3: ToggleHotkeyRow

Interaktive Zeile. Nutzt die bestehende `KeyRecorderViewModel`-Infrastruktur aus `SettingsView.swift`.

### States

#### State A — Leer (kein Toggle-Hotkey vergeben)

```
HStack(spacing: 8)
  [Mode-Icon]  SF Symbol, foreground .secondary, frame width 20
  VStack(alignment: .leading, spacing: 0)   // spacing: 0 — Label direkt über Subtitle
    Text(mode.title)  .body .bold()
    Text(mode.subtitle)  .caption2 .secondary
  Spacer()
  Text("—")
    .font(.system(.body, design: .monospaced))
    .foregroundStyle(.tertiary)
    .frame(minWidth: 100, alignment: .center)
  Button("Hotkey belegen") { startRecording() }
```

#### State B — Belegt (Toggle-Hotkey gesetzt)

```
HStack(spacing: 8)
  [Mode-Icon]  SF Symbol, foreground .secondary, frame width 20
  VStack(alignment: .leading, spacing: 0)   // spacing: 0 — Label direkt über Subtitle
    Text(mode.title)  .body .bold()
    Text(mode.subtitle)  .caption2 .secondary
  Spacer()
  Text(binding.displayString)
    .font(.system(.body, design: .monospaced))
    .padding(.horizontal, 8) .padding(.vertical, 4)   // 4 pt vertikal — auf 4-pt-Raster (zuvor 3 pt)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
  Button("Hotkey ändern") { startRecording() }
  Button {
    clearBinding()
    // Kein Confirm-Dialog erforderlich (Settings-Kontext, Undo via Reset-Button möglich)
  } label: {
    Image(systemName: "xmark.circle")
      .accessibilityLabel("Hotkey entfernen")
  }
  .buttonStyle(.plain)
  .foregroundStyle(.secondary)
  .help("Hotkey entfernen")
```

#### State C — Recorder aktiv

```
HStack(spacing: 8)
  [Mode-Icon]  SF Symbol, foreground .secondary, frame width 20
  VStack(alignment: .leading, spacing: 0)   // spacing: 0 — Label direkt über Subtitle
    Text(mode.title)  .body .bold()
    Text(mode.subtitle)  .caption2 .secondary
  Spacer()
  Text(recorder.liveDisplay)
    .font(.system(.body, design: .monospaced))
    .padding(.horizontal, 8) .padding(.vertical, 4)   // 4 pt vertikal — auf 4-pt-Raster (zuvor 3 pt)
    .frame(minWidth: 160, alignment: .leading)
    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1))
  Button {
    stopRecording()
  } label: {
    Image(systemName: "xmark.circle.fill")
      .accessibilityLabel("Aufnahme abbrechen")
  }
  .buttonStyle(.plain)
  .foregroundStyle(.secondary)
  .help("Abbrechen")
```

#### State D — Fehler: Doppelbelegung

```
// Fehler-Overlay unter der Zeile (kein Modal, kein Alert)
Text("⌘⇧B ist bereits für Blitztext+ vergeben.")
  .font(.caption)
  .foregroundStyle(.red)
  .padding(.top, 4)   // 4 pt — auf 4-pt-Raster (zuvor 2 pt)
```

Verhalten: Recorder wechselt zurück zu State B (oder A) mit Fehlertext. Fehlertext verschwindet nach 3 Sekunden oder bei nächster Interaktion.

#### State E — Fehler: Ungültige Kombination (nur Modifier, kein Buchstabe/F-Taste)

```
Text("Kombination ohne Buchstaben oder Funktionstaste ist nicht erlaubt.")
  .font(.caption)
  .foregroundStyle(.red)
  .padding(.top, 4)   // 4 pt — auf 4-pt-Raster (zuvor 2 pt)
```

Verhalten: identisch mit State D — kein Commit, Recorder abgebrochen.

### Recorder-Bestätigung

Ablauf: User drückt Tastenkombo → `keyDown`-Event → `onCommit(binding)` → Validierung (Doppelbelegung? Nur Modifier?) → bei OK: `settings.setToggleHotkey(binding, for: mode)` → State B.

Escape-Key: bricht Recorder ab → State B (oder A), kein Fehler.

---

## Surface 4: ConflictWarningBanner

Dezentes Warn-Banner. Erscheint unterhalb der Toggle-Section, wenn eine gesetzte Kombo mit bekannten System-Shortcuts kollidiert.

**Sichtbarkeit:** Nur wenn `conflictingModes` nicht leer. Keine permanente Reservierung von Layout-Platz.

```
VStack(alignment: .leading, spacing: 4)
  HStack(spacing: 8)
    Image(systemName: "exclamationmark.triangle.fill")
      .foregroundStyle(.orange)
    Text("Möglicher Konflikt mit einem System-Hotkey")
      .font(.body) .bold()   // .body .bold() statt .subheadline — bleibt auf 4 deklarierten Rollen
  Text(conflictDetail)  // z.B. "⌘Space ist Spotlight. Der Hotkey funktioniert möglicherweise nicht."
    .font(.caption) .foregroundStyle(.secondary)
.padding(8)
.background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
```

Der Hotkey bleibt **gesetzt** trotz Konflikt-Warning (CONTEXT.md Decision: "nachsichtig — App registriert trotzdem"). Kein hartes Blockieren, kein "Entfernen"-Button im Banner selbst.

**Bekannte konfliktreiche Kombos (kuratierte Liste — da System-API unzuverlässig):**
- `⌘Space` — Spotlight
- `⌘⌥Space` — Spotlight (Finder-Suche)
- `⌃Space` — Eingabequellen wechseln
- `⌃F2`, `⌃F3` — Menüleiste / Dock fokussieren
- `⌘⌃Q` — Bildschirm sperren
- `⌘⇧3`, `⌘⇧4`, `⌘⇧5` — Screenshots

Prüfmechanismus: statischer Vergleich gegen diese Liste nach jedem Commit. Kein dynamischer API-Aufruf.

---

## Surface 5: Anpassen-Tab Refactoring (TASTENKÜRZEL-Section)

**Wichtig:** Die bestehende "TASTENKÜRZEL"-Section in `AnpassenTab` wird **entfernt** und durch einen Verweis auf den neuen "Hotkeys"-Tab ersetzt.

Ersatz-Text in `AnpassenTab`:

```
VStack(alignment: .leading, spacing: 4)
  Text("TASTENKÜRZEL").font(.caption).foregroundStyle(.secondary).bold()
  Text("Hotkeys werden im Tab \"Hotkeys\" konfiguriert.")
    .font(.caption).foregroundStyle(.secondary)
```

Alternativ: Section vollständig entfernen, wenn der Tab-Picker die Navigation übernimmt.

---

## Interaction Details

### Recorder-Verhalten (Toggle-Pfad)

| Event | Reaktion |
|-------|---------|
| Modifiers gedrückt (ohne Key) | `liveDisplay` zeigt Modifier-Symbole live |
| Modifiers + Key gedrückt | `onCommit(binding)` — Validierung |
| Nur Modifiers losgelassen (kein Key) | Verwerfen — Binding nicht gesetzt (Edge-Case: nur fn/⇧/⌃/⌥ ohne Buchstabe) |
| Escape | Abbrechen ohne Commit |
| Klick außerhalb Recorder | Recorder stoppt, kein Commit (`.onDisappear { recorder.stop() }`) |

### Doppelbelegung

- Geprüft wird gegen alle 3 Toggle-Hotkeys des `SettingsStore` (nicht gegen Hold-Hotkeys — unterschiedliche CGEventTap vs. Package-Pfade)
- Fehlertext nennt explizit den bereits belegten Mode: `"[Kombo] ist bereits für [Mode.title] vergeben."`
- Kein Alert-Dialog, kein Sheet — Inline unter der Zeile

### Reset pro Zeile

- Jeder `ToggleHotkeyRow` hat im State B ein `xmark.circle`-Icon-Button — löscht nur diese Bindung
- Kein Confirm-Dialog erforderlich (Settings-Kontext, Undo via Reset-Button möglich)
- `HoldHotkeyRow` hat keinen Reset-Button (Hold-Pfad ist read-only in diesem Tab)
- Kein globaler "Alle zurücksetzen"-Button (CONTEXT.md Decision: "pro-Hotkey-Reset-Button, kein globaler")

---

## Copywriting Contract

| Element | Copy (Deutsch) |
|---------|----------------|
| Tab-Label | "Hotkeys" |
| Section Header Hold | "HOLD-HOTKEYS" |
| Section Header Toggle | "TOGGLE-HOTKEYS" |
| Hold Section Caption | "fn + Modifier — Halten aktiviert Aufnahme. Nicht konfigurierbar." |
| Toggle Section Caption | "Freie Tastenkombination für den Drücken-Modus. Optional — leer = kein Toggle-Hotkey." |
| Hold Badge Label | "Nicht änderbar — fn-Schnellpfad" |
| Recorder Idle | "Drücke Tastenkombination …" |
| Belegen-Button | "Hotkey belegen" |
| Ändern-Button | "Hotkey ändern" |
| Entfernen-Help | "Hotkey entfernen" |
| Abbrechen-Help | "Abbrechen" |
| Entfernen accessibilityLabel | "Hotkey entfernen" |
| Abbrechen accessibilityLabel | "Aufnahme abbrechen" |
| Leer-Placeholder | "—" (Em-Dash, zentriert in Binding-Feld) |
| Fehler: Doppelbelegung | "[Kombo] ist bereits für [Mode.title] vergeben." |
| Fehler: Nur Modifier | "Kombination ohne Buchstaben oder Funktionstaste ist nicht erlaubt." |
| Conflict-Warning Titel | "Möglicher Konflikt mit einem System-Hotkey" |
| Conflict-Warning Body | "[Kombo] wird von [System-Feature] verwendet. Der Hotkey funktioniert möglicherweise nicht zuverlässig." |
| AnpassenTab Verweis | "Hotkeys werden im Tab \"Hotkeys\" konfiguriert." |

Alle Strings sind Deutsch (CLAUDE.md: "German UI strings").

---

## Data Model Contract

Die folgenden Ergänzungen an `SettingsStore` und `SettingsStore.Snapshot` sind für die UI benötigt:

### Neue @Published Properties (Toggle-Hotkeys)

```swift
@Published var toggleHotkeyForBlitztext: HotkeyBinding? = nil
@Published var toggleHotkeyForBlitztextPlus: HotkeyBinding? = nil
@Published var toggleHotkeyForBlitztextRant: HotkeyBinding? = nil
```

Typ: `HotkeyBinding?` (Optional — `nil` = kein Toggle-Hotkey gesetzt). Defaults: `nil` (CONTEXT.md Decision: "Toggle-Pfad startet leer").

### Snapshot-Erweiterung

```swift
struct Snapshot: Codable {
    // ... bestehende Felder ...
    var toggleHotkeyForBlitztext: HotkeyBinding?      = nil
    var toggleHotkeyForBlitztextPlus: HotkeyBinding?  = nil
    var toggleHotkeyForBlitztextRant: HotkeyBinding?  = nil
}
```

Migrations-Kompatibilität: Optional mit `nil`-Default — bestehende JSON-Snapshots ohne diese Keys deserialisieren ohne Fehler.

### Accessor-Methoden

```swift
func toggleHotkeyBinding(for mode: Mode) -> HotkeyBinding?
func setToggleHotkeyBinding(_ binding: HotkeyBinding?, for mode: Mode)
```

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| Kein SPM UI-Package | — | not applicable |

Begründung: Die bestehende `KeyRecorderViewModel` + `HotkeyRecorderRow` Infrastruktur in `SettingsView.swift` deckt den Recorder-Use-Case bereits vollständig ab. Ein externes SPM-Package (soffes/HotKey, shpakovski/MASShortcut) wird **nicht** für die UI-Recorder-Komponente benötigt — es wird nur für die **Hotkey-Registrierung im Hintergrund** (HotkeyManager) benötigt. Die UI bleibt rein nativ.

Das SPM-Package-Vetting (Swift-6-Concurrency-Kompatibilität) ist Aufgabe des Planers/Researchers, nicht Teil des UI-Contracts.

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending
