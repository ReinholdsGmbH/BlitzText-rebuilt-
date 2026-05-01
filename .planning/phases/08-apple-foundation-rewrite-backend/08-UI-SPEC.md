---
phase: 8
slug: apple-foundation-rewrite-backend
status: draft
shadcn_initialized: false
preset: none
platform: macOS-native (SwiftUI + AppKit)
created: 2026-05-01
---

# Phase 8 — UI Design Contract: Apple Foundation Rewrite-Backend

> Visual und Interaction Contract für die drei UI-Oberflächen, die Phase 8 berührt: (1) zwei Backend-Picker pro Rewrite-Mode im Settings-`Anpassen`-Tab, (2) Verfügbarkeits-Banner im selben Tab für die `SystemLanguageModel.availability`-Zustände, (3) dezenter Backend-Indikator im schwebenden Recording-HUD am unteren Bildschirmrand. Generiert von gsd-ui-researcher; verifiziert von gsd-ui-checker. Plattform: native macOS — kein shadcn, kein Tailwind, keine Webkomponenten. Apple HIG ist die Referenz, SwiftUI semantic styles sind verbindlich (keine Pixel-Typografie).

---

## Scope

Drei Oberflächen, ein gemeinsamer Contract:

1. **Settings → `Anpassen`-Tab** — zwei neue Backend-Picker (je einer für `BLITZTEXT+` und `BLITZTEXT $%&!`) als zusätzliche Zeile innerhalb der bestehenden `section`-Helper-Struktur (`SettingsView.swift:70-93`). Picker-Stil wie der `TranscriptionBackend`-Picker im `Lokales Modell`-Tab (`SettingsView.swift:336-340`) — `Picker("Backend", selection: …)` ohne `pickerStyle`-Override (= macOS-default-Menu, nicht segmented; Foundation/OpenAI sind sich textuell zu nahe für Segmente).
2. **Settings → `Anpassen`-Tab → Verfügbarkeits-Banner** — neue oberste `section("APPLE INTELLIGENCE")` direkt unter `MODUS`-Section, sichtbar nur wenn `SystemLanguageModel.default.availability != .available`. Vier State-Varianten (siehe State-Spec).
3. **Recording-HUD (Pille)** — Backend-Indikator als zusätzliche Capsule rechts neben dem `langBadge` im bestehenden `RecordingHUDView` (`RecordingHUDController.swift:74-113`). Wird nur sichtbar während `processor.state == .rewriting` (genauer: nur wenn die Pipeline für den aktuellen Mode tatsächlich rewriten wird; plain `blitztext` zeigt keinen Indikator, weil kein Rewrite-Backend involviert ist).

**Kein neuer Tab.** **Keine Strukturänderung der Settings-Hierarchie.** Backend-Indikator nutzt bestehende HUD-Geometrie (240×56 pt Pille), erweitert sie aber implizit um ~28 pt Breite (Capsule mit Symbol). Window-Frame wird auf `width: 268` angehoben — siehe Spacing.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (native macOS) |
| Preset | not applicable |
| Component library | SwiftUI + AppKit (system) |
| Icon library | SF Symbols (system) |
| Font | San Francisco (`.body`, `.caption`, `.caption2`, `.subheadline`, `.headline` — SwiftUI Text-Styles); HUD-Backend-Badge nutzt die bestehende monospaced Mini-Schrift `.system(size: 10, weight: .bold, design: .monospaced)` aus `langBadge` für visuelle Konsistenz |
| Layout style | bestehender `AnpassenTab.section`-Helper (`SettingsView.swift:140-145`) für Settings; bestehender `RecordingHUDView`-`HStack(spacing: 12)`-Rhythmus für HUD |

**Begründung:** Keine Custom-Tokens, keine neuen Farb- oder Typografie-Skalen. Phase 8 erweitert bestehende Sektionen um zwei Zeilen und ein Banner; das HUD bekommt ein zweites Capsule-Element neben dem schon vorhandenen `langBadge`. Jede Token-Erfindung wäre Drift gegenüber Phase 3 und allen anderen Tabs.

---

## Spacing Scale

System-Default. Settings-Tab nutzt `VStack(spacing: 18)` zwischen Sections und `VStack(spacing: 8)` innerhalb einer Section (siehe `AnpassenTab.body` und `section` helper). HUD nutzt `HStack(spacing: 12)` zwischen Inhaltselementen und `.padding(.horizontal, 18)` als Innenabstand.

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4 pt | Symbol-Text-Inline (`HStack(spacing: 4)`); Capsule-Innen-Padding-vertical im HUD-Backend-Badge |
| sm | 6 pt | Capsule-Innen-Padding-horizontal im HUD-Backend-Badge (entspricht existing `langBadge` `.padding(.horizontal, 6)`) |
| md | 8 pt | Item-Spacing innerhalb einer Settings-Section (existing `VStack(spacing: 8)` im `section`-Helper) |
| lg | 12 pt | HStack-Spacing innerhalb des HUDs zwischen `PulsingDot` / `LevelBars` / `langBadge` / **`backendBadge`** (existing `HStack(spacing: 12)`) |
| xl | 18 pt | Vertikales Spacing zwischen Settings-Sections (existing `VStack(alignment: .leading, spacing: 18)` in `AnpassenTab.body`); HUD-Capsule-Innen-Horizontal-Padding |
| Edge-Padding | 20 pt | Settings-ScrollView outer (existing `.padding(20)` in `SettingsView.body`) |
| Picker max width | 280 pt | Backend-Picker-Breite; alignt mit `langFilter`-Picker (`.frame(maxWidth: 280)` in `LokalTab`) |
| HUD-Window-Width | **268 pt** (war 240) | Vergrößerung um 28 pt für Backend-Badge-Capsule (~24 pt Symbol-Capsule + 4 pt zusätzlicher HStack-Gap, weil bereits `spacing: 12` zwischen `langBadge` und neuem Element bleibt; effektiv 240 + 28 = 268). Höhe bleibt 56 pt. |
| HUD-Window-Height | 56 pt | unverändert |

**Exceptions:** keine. HUD-Window-Width-Anpassung ist die einzige geometrische Veränderung und bleibt in 4-pt-Vielfachen.

---

## Typography

SwiftUI semantic styles, keine numerischen Pixel-Werte (außer für die HUD-monospaced-Badges, die existing-konform `size: 10` nutzen — Convention aus `langBadge`). macOS skaliert mit System-Settings (Accessibility-fähig).

| Role | SwiftUI Style | Weight | Usage |
|------|---------------|--------|-------|
| Section-Caption | `.caption` | `.bold()` + `.foregroundStyle(.secondary)` | Section-Header `"BLITZTEXT+"`, `"BLITZTEXT $%&!"`, `"APPLE INTELLIGENCE"` (existing pattern via `section`-Helper) |
| Picker-Label-Inline | system default (Picker) | regular | `"Backend"` als sichtbarer Picker-Title — gleicher Stil wie `Picker("Backend", …)` im `LokalTab` |
| Picker-Subtitle (caption2) | `.caption2` | regular, `.foregroundStyle(.tertiary)` | optionale Erklärungs-Mini-Zeile unter Picker (z.B. nur sichtbar bei `.openAI`-Wahl: `"Rewrite läuft über OpenAI gpt-4o-mini in der Cloud."`) |
| Banner-Heading | `.subheadline` | regular | Banner-Hauptzeile, z.B. `"Apple Intelligence ist nicht aktiviert"` |
| Banner-Detail | `.caption` | regular, `.foregroundStyle(.secondary)` | Erklärungs-Detailzeile unter Banner-Heading |
| Banner-modelNotReady-Heading | `.subheadline` | regular | `"Apple-Foundation-Modell wird geladen …"` — kein `.red`, kein Error-Symbol (siehe Color) |
| HUD-Backend-Badge | `.system(size: 10, weight: .bold, design: .monospaced)` (Symbol-only Variante: System-Default-Symbol-Größe in `Image(systemName:)` skaliert mit Capsule-Padding) | bold | Backend-Indikator-Capsule im HUD; Konvention aus `langBadge` (`Zeile 102`) |
| Body-Inline-Hinweis | `.caption` | regular, `.foregroundStyle(.orange)` | nicht-fataler Soft-Hinweis-Text (z.B. `"OpenAI als Fallback aktiv …"`) — analog zu existing `.foregroundStyle(.orange)`-Pattern bei `LokalTab:343` |

**Begründung der Stil-Wahl:** Plattform-konform. Phase 3 hat den semantic-style-Set bereits eingeführt; Phase 8 nutzt exakt denselben Set plus `.subheadline` für Banner-Heading (im Set, nur in Phase 3 nicht ausgespielt). Pixel-Override würde Dynamic Type brechen. Das HUD ist das einzige UI mit Pixel-Schrift — und das ist bereits so im Bestand und bleibt deshalb erhalten (Konsistenz mit `langBadge` schlägt formale Reinheit).

---

## Color

Native macOS-Semantic-Colors — kein Custom-Hex. SwiftUI `.foregroundStyle(...)` und `Color.green/.red/.orange` rendern automatisch hell/dunkel adaptiv. Das HUD ist eine schwarze Pille mit `.white`-Tints — diese Konvention bleibt erhalten und wird vom Backend-Badge übernommen.

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60 %) | system default Window-Background | Settings-Window-Surface — unverändert |
| Secondary (30 %) | `.foregroundStyle(.secondary)` (System-grau) | Section-Captions, Banner-Detail-Texte, Picker-Subtitles |
| Tertiary | `.foregroundStyle(.tertiary)` (heller) | Sekundär-Hinweise unter Pickern (z.B. Erklärungs-`caption2`) |
| Accent (10 %) | (kein Custom-Accent in Phase 8) | Phase 8 nutzt **keinen** projekt-eigenen Accent. Toggles, Buttons, Picker-Selektion erben System-`accentColor` (vom User systemweit gesetzt) — wir greifen nicht ein. |
| Warning | `.orange` (System) | Banner für `unavailable` mit aktivem OpenAI-Fallback (Soft-Hinweis: "OpenAI als Fallback aktiv"); Banner für `deviceNotEligible` als finale Soft-Information |
| Destructive / Error | `.red` (System) | **NICHT** für `modelNotReady` (das ist transient, kein Fehler). Reserviert für: zukünftige Inferenz-Fehler-Anzeige im Recording-HUD-Pfad oder Banner-Variante "Apple Intelligence wurde während der Sitzung deaktiviert". In Phase 8 v1 **nicht** im Banner verwendet — alle Verfügbarkeits-States sind entweder informativ (`modelNotReady` = secondary) oder soft-warnend (`appleIntelligenceNotEnabled` / `deviceNotEligible` = `.orange`). |
| Info / Loading | `.foregroundStyle(.secondary)` + ProgressView (system default tint) | `modelNotReady`-Banner — bewusst neutral, weil "noch nicht fertig" ≠ "Fehler" |
| HUD-Pille-Background | `.black.opacity(0.85)` | unverändert (existing `Capsule().fill(.black.opacity(0.85))`) |
| HUD-Badge-Background | `.white.opacity(0.12)` | Backend-Badge-Capsule-Fill — identisch zu existing `langBadge`-Pattern (`Zeile 107`) |
| HUD-Badge-Foreground | `.white.opacity(0.85)` | Backend-Symbol-Tint — identisch zu existing `langBadge.foregroundStyle(.white.opacity(0.85))` |

**Accent reserved for:**
- **`.orange` ausschließlich für:** (i) `appleIntelligenceNotEnabled`-Banner-Symbol + Heading-Tint, (ii) `deviceNotEligible`-Banner-Symbol + Heading-Tint, (iii) optionale Soft-Hinweis-Zeile `"OpenAI als Fallback aktiv …"` direkt unter dem Backend-Picker, wenn der automatische Default-Switch zu `.openAI` greifen musste.
- **`.secondary` (System-grau) ausschließlich für:** `modelNotReady`-Banner — Symbol + Text. Kein `.orange`, kein `.red`. ProgressView nutzt System-Default-Tint ohne Override.
- **`.red` ist in Phase 8 v1 nicht verwendet.** (CONTEXT-Decision: kein Auto-Fallback bei Inferenz-Fehler → Inferenz-Fehler-UI gehört nicht zu Phase 8; Banner-Logik kennt nur `unavailable`-Verfügbarkeits-Cases, die alle nicht-fatal sind.)
- **HUD-`.white.opacity(0.85)`** ist die einzige Foreground-Tint im HUD-Backend-Badge — keine Differenzierung Foundation vs. OpenAI per Farbe (die SF-Symbole `apple.logo` vs. `cloud` tragen die Information).

**Begründung:** CONTEXT.md decidet, dass Verfügbarkeits-Probleme keine harten Fehler sind, sondern Konfigurations-Hinweise. `.red` würde Panik signalisieren. `.orange` (= "Acht geben, aber kein Notfall") trifft den semantischen Anker. Bestehende `LokalTab`-Referenz: `Text("Lokales Backend gewählt, aber kein Modell aktiviert. …").foregroundStyle(.orange)` (`SettingsView.swift:343`) — identisches Muster, identischer Tonfall.

---

## State-by-State Visual Spec

### Surface 1 — Backend-Picker pro Mode (immer sichtbar im Anpassen-Tab)

Layout-Slot: jeweils eine Zeile **am Ende** der bestehenden `BLITZTEXT+`- und `BLITZTEXT $%&!`-Sections, **nach** dem `TextEditor` für die "Eigene Anweisung". Visuell wie folgt:

```
section("BLITZTEXT+") {                              [bestehend]
  Text("Schreibstil").font(.subheadline)             [bestehend]
  Picker(…) /* WritingStyle */                       [bestehend]
  Text("Eigene Anweisung")...                        [bestehend]
  TextEditor(…)                                      [bestehend]

  // ↓ NEU in Phase 8
  Text("Backend").font(.subheadline).padding(.top, 6)
  Picker("Backend", selection: $settings.backendForPlus) {
    ForEach(RewriteBackend.allCases) { Text($0.label).tag($0) }
  }
  .frame(maxWidth: 280)
  // optional: Mini-Hinweis-Zeile (siehe Conditional-Display unten)
}
```

`BLITZTEXT $%&!`-Section bekommt denselben Block am Ende. **Wichtig:** `Text("Backend")` wird als `.subheadline`-Mini-Sub-Header gerendert (analog zu `Text("Schreibstil").font(.subheadline)` direkt darüber) — damit fügt sich der Picker visuell ohne Bruch in den Section-Rhythmus ein.

**Picker-Items (Label-Strings):**
- `RewriteBackend.appleFoundation` → `"Apple Foundation (lokal)"`
- `RewriteBackend.openAI` → `"OpenAI gpt-4o-mini (Cloud)"`

(Der Klammer-Zusatz macht die Privacy-Implikation jedes Mal sichtbar, ohne separaten Erklärtext zu erzwingen.)

**Conditional Mini-Hinweis (caption2 unter dem Picker):** Nur wenn der gewählte Backend-Wert `.openAI` ist UND `availability == .available`, zeige:

```
Text("Rewrite für diesen Mode läuft über die OpenAI-Cloud.")
  .font(.caption2).foregroundStyle(.tertiary)
```

Bei `.appleFoundation` keine Mini-Zeile — Foundation ist Default und braucht keine Privacy-Beruhigung. Bei `.openAI` UND Banner aktiv (= unavailable + auto-fallback) wird die Mini-Zeile durch den Banner-Soft-Hinweis ersetzt (siehe Surface 2 / Variante D), nicht zusätzlich gerendert.

**Disabled-Zustand:** Picker ist **nie** disabled. Der User darf jederzeit umschalten — auch bei `unavailable`. Wenn er Foundation wählt und es nicht verfügbar ist, fängt das `AppleFoundationRewriteClient` (siehe AC-AVAIL-1) den Inferenz-Call mit deutscher Fehlermeldung ab. UI-seitig gibt es kein Lock.

### Surface 2 — Verfügbarkeits-Banner (vier Varianten)

Layout-Slot: Banner ist eine eigene `section("APPLE INTELLIGENCE")`-Block direkt **vor** der `MODUS`-Section in `AnpassenTab.body`. Sichtbar nur wenn `availabilityState != .available`.

Banner-Struktur (gemeinsam für alle Varianten):

```
section("APPLE INTELLIGENCE") {
  HStack(alignment: .top, spacing: 12) {
    Image(systemName: <symbol>)          [.foregroundStyle(<tint>)]
    VStack(alignment: .leading, spacing: 4) {
      Text(<heading>)                     [.subheadline]
      Text(<detail>)                      [.caption, .secondary]
      <optional action: Link / Button>
    }
    Spacer()
  }
}
```

**Variante A — `appleIntelligenceNotEnabled`:**

| Field | Value |
|-------|-------|
| Symbol | `exclamationmark.circle` (NICHT `.fill`-Variante; soft-tone) |
| Tint | `.orange` |
| Heading | `Apple Intelligence ist nicht aktiviert` |
| Detail | `Aktiviere Apple Intelligence in den Systemeinstellungen, um BlitzText+ und BlitzText $%&! lokal zu rewriten — ohne Cloud.` |
| Action | `Link("Systemeinstellungen öffnen …", destination: URL(string: "x-apple.systempreferences:com.apple.preference.appleintelligence")!)` |

**Variante B — `modelNotReady`:**

| Field | Value |
|-------|-------|
| Symbol | `arrow.triangle.2.circlepath` (rotierend NICHT erforderlich; daneben separate `ProgressView`) |
| Tint | `.foregroundStyle(.secondary)` — explizit **kein** `.orange`, kein `.red` |
| Heading | `Apple-Foundation-Modell wird geladen …` |
| Detail | `Das passiert einmalig nach Aktivierung von Apple Intelligence. BlitzText prüft regelmäßig, ob das Modell bereit ist.` |
| Inline-Element | `ProgressView().controlSize(.small)` direkt rechts neben dem Symbol (HStack-spacing 8) — kein `value:` (indeterminate, weil Apple keine Fortschrittsangabe liefert). Pattern aus `LokalTab:347`. |
| Action | `Button("Erneut prüfen") { settings.refreshFoundationAvailability() }.buttonStyle(.bordered)` — manueller Re-Check, falls automatisches Polling/Notification noch nicht ausgelöst hat |

**Variante C — `deviceNotEligible`:**

| Field | Value |
|-------|-------|
| Symbol | `exclamationmark.circle` |
| Tint | `.orange` |
| Heading | `Dieses Gerät unterstützt Apple Intelligence nicht` |
| Detail | `BlitzText+ und BlitzText $%&! laufen über die OpenAI-Cloud, sofern ein API-Key hinterlegt ist. Ohne API-Key bleibt nur der einfache Blitztext-Mode (kein Rewrite).` |
| Action | keine — Final-State, kein Retry sinnvoll |

**Variante D — Auto-Fallback-Hinweis (overlay-fähig zu A/B/C):**

Wenn `availabilityState != .available` UND der `SettingsStore` während `AppDelegate.bootstrap()` automatisch auf `RewriteBackend.openAI` umgeschaltet hat (weil API-Key vorhanden), wird **zusätzlich zur** Variante A/B/C eine zweite Zeile am Banner-Ende gerendert:

```
HStack(spacing: 4) {
  Image(systemName: "cloud")               [.foregroundStyle(.orange)]
  Text("OpenAI als Fallback aktiv. Aktiviere Apple Intelligence, um lokal zu rewriten.")
    .font(.caption).foregroundStyle(.orange)
}
```

Dies ersetzt **NICHT** den Heading/Detail-Block; es **ergänzt** ihn um eine User-handlungsrelevante Zusatzinformation. Bei Variante C (`deviceNotEligible`) ist diese Zeile semantisch redundant zu Detail (das bereits OpenAI erwähnt) — in dem Fall **wird die Zeile nicht zusätzlich gerendert**, weil sonst doppelt.

**Persistenz/Dismissibility:** Banner ist **nicht dismissbar** in v1. Solange der `availability`-State unverändert ist, bleibt das Banner sichtbar. Sobald `available` zurückkommt, verschwindet die ganze Section komplett (kein Übergangszustand, keine Erfolgsmeldung — Foundation ist transparent aktiv, das ist die Norm).

### Surface 3 — Recording-HUD-Backend-Indikator

Layout-Slot: rechts neben dem bestehenden `langBadge` im `RecordingHUDView`-`HStack`. Nutzt **dasselbe Capsule-Pattern** wie `langBadge`, **aber Symbol statt Text**.

```
HStack(spacing: 12) {
  PulsingDot()                                  [bestehend]
  LevelBars(level: recorder.currentLevel)       [bestehend]
  Text(langBadge)…                              [bestehend, langBadge-Capsule]

  // ↓ NEU in Phase 8 — nur sichtbar während .rewriting + Mode != .blitztext
  if showsBackendBadge {
    Image(systemName: backendSymbol)
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(.white.opacity(0.85))
      .frame(width: 12, height: 12)
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(.white.opacity(0.12), in: Capsule())
  }
}
```

| Backend | SF Symbol | Tooltip (`.help(...)`) |
|---------|-----------|------------------------|
| `.appleFoundation` | `apple.logo` | `Rewrite lokal über Apple Foundation Models` |
| `.openAI` | `cloud` | `Rewrite über OpenAI gpt-4o-mini (Cloud)` |

**`showsBackendBadge`-Bedingung** (lebt in `RecordingHUDView`, leitet sich aus `processor.state` und `currentMode` ab):

| Pipeline-State | Mode | Badge sichtbar? |
|---------------|------|-----------------|
| `.recording(mode)` mit `mode == .blitztext` | plain | **nein** (kein Rewrite, kein Indikator) |
| `.recording(mode)` mit `mode == .blitztextPlus` oder `.blitztextRant` | rewrite-fähig | **ja**, Symbol nach `settings.rewriteBackend(for: mode)` |
| `.transcribing(mode)` mit Rewrite-Mode | rewrite-fähig | **ja** (Vorhersage, weil Rewrite gleich kommt) |
| `.rewriting(mode)` | per Definition rewrite-fähig | **ja** |
| `.idle` / `.error` | — | HUD nicht sichtbar (existing show/hide-Logik) |

**Begründung "auch während recording/transcribing sichtbar":** User sieht früh, *welches* Backend gleich greifen wird. Wenn er das HUD aufpoppen sieht und der falsche Backend-Indikator (z.B. `cloud` statt `apple.logo`) zu sehen ist, kann er noch abbrechen (Hotkey loslassen / Mode-Wechsel) — Privacy-Markenversprechen wird so nicht erst nach dem Cloud-Call sichtbar.

**Animation:** keine Custom-Animation. Capsule erscheint hart wenn `showsBackendBadge` true wird (system default state-driven appearance). Konsistent mit `langBadge`, das auch keine Einblend-Animation hat.

**HUD-Window-Width-Adjustment:** `RecordingHUDController.show()` setzt `let w: CGFloat = 268` (war 240). Höhe bleibt 56. Position bleibt `frame.midX - w / 2`, `frame.minY + 100`. Click-through-Verhalten unverändert (`ignoresMouseEvents = true`) — Tooltip ist daher rein dekorativ-deklarativ (nicht interaktiv testbar in v1, aber bleibt für Accessibility-Inspector relevant).

---

## Copywriting Contract

Alle Strings auf Deutsch (CLAUDE.md / Conventions). Tonfall: nüchtern-direkt, gleicher Stil wie Phase 3 und der restliche `AnpassenTab`/`LokalTab`. Keine Emojis. Symbol-Indikatoren nutzen SF Symbols, nicht Unicode-Glyphen.

| Element | Copy | Notes |
|---------|------|-------|
| Section-Caption (Settings, Banner) | `APPLE INTELLIGENCE` | Caps-Style aus existing `section`-Helper-Konvention |
| Sub-Header (Picker-Title, BLITZTEXT+) | `Backend` | parallel zu `Schreibstil` direkt darüber |
| Sub-Header (Picker-Title, BLITZTEXT $%&!) | `Backend` | identisch — Wiederholung ist OK, weil je in eigener Section |
| Picker-Item: Foundation | `Apple Foundation (lokal)` | "Apple" am Anfang signalisiert das Privacy-Versprechen direkt |
| Picker-Item: OpenAI | `OpenAI gpt-4o-mini (Cloud)` | Klammer-Zusatz "Cloud" macht Datenfluss explizit |
| Picker-Caption (nur sichtbar bei `.openAI`) | `Rewrite für diesen Mode läuft über die OpenAI-Cloud.` | `.caption2`, `.tertiary` — sehr leise; nur sichtbar bei `.openAI`-Wahl |
| Banner A — Heading | `Apple Intelligence ist nicht aktiviert` | konstant |
| Banner A — Detail | `Aktiviere Apple Intelligence in den Systemeinstellungen, um BlitzText+ und BlitzText $%&! lokal zu rewriten — ohne Cloud.` | "lokal zu rewriten — ohne Cloud" wiederholt das Privacy-Versprechen ohne penetrant zu wirken |
| Banner A — Link-Label | `Systemeinstellungen öffnen …` | drei Punkte = Auslassungszeichen `…` (U+2026), nicht drei einzelne Punkte; `…` signalisiert Kontextwechsel (= externe App) — Apple-HIG-konvention |
| Banner B — Heading | `Apple-Foundation-Modell wird geladen …` | mit `…` (U+2026) am Ende — signalisiert "in progress" |
| Banner B — Detail | `Das passiert einmalig nach Aktivierung von Apple Intelligence. BlitzText prüft regelmäßig, ob das Modell bereit ist.` | konstant; "regelmäßig prüft" beschwichtigt User ohne technisches Detail (Polling vs. Notification) leaken zu lassen |
| Banner B — Action-Button | `Erneut prüfen` | `.bordered`, NICHT `.borderedProminent` (analog zu Phase-3-Retry-Button-Konvention) |
| Banner C — Heading | `Dieses Gerät unterstützt Apple Intelligence nicht` | konstant; "unterstützt nicht" statt "kann nicht" — neutraler Ton |
| Banner C — Detail (mit API-Key) | `BlitzText+ und BlitzText $%&! laufen über die OpenAI-Cloud, sofern ein API-Key hinterlegt ist. Ohne API-Key bleibt nur der einfache Blitztext-Mode (kein Rewrite).` | konstant — beide Sub-Cases im selben Text, weil API-Key-State sich auch zur Laufzeit ändern kann |
| Banner D — Auto-Fallback-Zeile | `OpenAI als Fallback aktiv. Aktiviere Apple Intelligence, um lokal zu rewriten.` | `.caption`, `.orange`; nur zusätzlich zu A/B; bei C unterdrückt (siehe State-Spec) |
| HUD-Tooltip Foundation | `Rewrite lokal über Apple Foundation Models` | erscheint im `.help()` — Click-through verhindert Hover-Interaktion direkt, aber Accessibility-Inspector liest es |
| HUD-Tooltip OpenAI | `Rewrite über OpenAI gpt-4o-mini (Cloud)` | parallel zu Picker-Label |
| Empty-State (Settings-Tab) | n/a | Picker hat immer einen Default; Banner verschwindet wenn `available`. Kein Empty-State. |
| Destructive confirmation | n/a | Phase 8 hat **keine** destruktiven Aktionen. Backend-Wechsel ist non-destruktiv (kein Datenverlust, History bleibt erhalten). Kein Confirm-Dialog nötig. |

**Begründung der Tonfall-Wahl:** "lokal" (nicht "on-device"), "Cloud" (nicht "Server", nicht "extern") — beides aus PROJECT.md / CONTEXT.md-Vokabular. "rewriten" als Verb wird im Settings-Kontext so bereits genutzt (Mode-Erklärungen). "BlitzText+" und "BlitzText $%&!" mit Sonderzeichen — exakt wie in `Mode.swift` und allen anderen UI-Strings.

---

## Component Inventory

Konkrete SwiftUI-Komponenten, die der Executor liefert. Dateipfade sind Vorschlag — Planner darf konsolidieren.

| Component | Type | Inputs | Outputs | Notes |
|-----------|------|--------|---------|-------|
| `RewriteBackendPicker(mode:)` | `private struct: View` (lebt in `SettingsView.swift` oder neuer `RewriteBackendPicker.swift`) | `mode: Mode`, `@EnvironmentObject settings: SettingsStore` | Picker mit zwei Items + optionale `.caption2`-Tertiary-Zeile | wird zweimal aufgerufen (für `.blitztextPlus` und `.blitztextRant`) am Ende der jeweiligen `section` |
| `FoundationAvailabilityBanner` | `private struct: View` (eigener File `FoundationAvailabilityBanner.swift` empfohlen, weil 4 State-Varianten + konditionale Auto-Fallback-Zeile = ~80 LOC) | `@EnvironmentObject settings: SettingsStore` (oder spezifischer State-Provider) | switch über `availabilityState` → eine der drei Hauptvarianten + optional Variante D als Append | rendert nichts wenn `available`; lebt als oberste Section in `AnpassenTab.body` |
| `BackendBadge` (HUD) | `private struct: View` (lebt direkt in `RecordingHUDController.swift` neben `PulsingDot` / `LevelBars`) | `backend: RewriteBackend` | Capsule mit SF-Symbol | bedingt sichtbar via `if showsBackendBadge` im `RecordingHUDView.body` |
| `RecordingHUDView` (existing, modifiziert) | bestehend | erweiterter HStack-Inhalt | unverändert ansonsten | HUD-Window-Width im Controller von 240 auf 268 hochziehen |

**Manager-/State-Surface (für UI-Verbrauch — nicht Contract-Detail, aber nötig zur Verifikation):**
- `SettingsStore.rewriteBackend(for: Mode) -> RewriteBackend` — Lookup pro Mode
- `SettingsStore.setRewriteBackend(_:for:)` — vom Picker-Binding aufgerufen
- `SettingsStore.foundationAvailability: FoundationAvailability` — `@Published`; Werte: `.available`, `.unavailable(.appleIntelligenceNotEnabled)`, `.unavailable(.modelNotReady)`, `.unavailable(.deviceNotEligible)`
- `SettingsStore.refreshFoundationAvailability()` — Re-Check, vom Banner-B-Button aufgerufen
- `SettingsStore.didAutoFallbackToOpenAI: Bool` — `@Published`; true wenn `bootstrap()` Default-Switch ausgelöst hat; gibt Banner-Variante D Sichtbarkeit

---

## Interaction Contract

| Trigger | Expected UI Behavior |
|---------|---------------------|
| App-Start, `availability == .available`, beide Modes auf default | Settings-`Anpassen`-Tab zeigt **kein** Banner. Picker pro Mode auf `.appleFoundation`. Keine UI-Reibung. |
| App-Start, `availability == .unavailable(.appleIntelligenceNotEnabled)`, kein API-Key | Banner Variante A sichtbar. Beide Picker bleiben auf `.appleFoundation` (User-Setting, nicht Auto-Switch — weil ohne API-Key kein OpenAI-Fallback existiert). Banner D **nicht** gerendert. |
| App-Start, `availability == .unavailable(.appleIntelligenceNotEnabled)`, API-Key vorhanden | `bootstrap()` schaltet Default-Backend auf `.openAI` (für beide Modes, falls noch auf Default). Banner Variante A + Variante D (Auto-Fallback-Zeile) sichtbar. |
| App-Start, `availability == .unavailable(.modelNotReady)` | Banner Variante B sichtbar mit ProgressView. Polling/Notification-Re-Check läuft im Hintergrund. Picker-State unverändert. |
| App-Start, `availability == .unavailable(.deviceNotEligible)` | Banner Variante C sichtbar. Mit API-Key: Banner D unterdrückt (Detail-Text deckt Fall ab). Beide Picker auto-switched auf `.openAI`. |
| Verfügbarkeit wechselt während Session von `.unavailable(.modelNotReady)` → `.available` | Banner verschwindet ohne Übergangs-Animation. Picker-State unverändert (User-Wahl bleibt erhalten). |
| User klickt "Erneut prüfen" (Variante B) | `refreshFoundationAvailability()` läuft synchron-via-Task. Banner re-rendert mit aktuellem State. Falls `.available`: Section verschwindet. Falls weiterhin `.modelNotReady`: Banner B bleibt sichtbar (kein Toast, keine Erfolgsmeldung — User sieht's am State-Wechsel). |
| User klickt Link "Systemeinstellungen öffnen …" (Variante A) | macOS öffnet Systemeinstellungen → Apple Intelligence-Pane. App selbst macht nichts weiter (keine Polling-Aktivierung; `refreshFoundationAvailability()` wird beim nächsten Window-Aktivieren ausgelöst — nicht UI-Contract, sondern Planner-Detail). |
| User wählt im Picker `.appleFoundation` → `.openAI` | Setting-Wert ändert sofort. `.caption2`-Tertiary-Zeile `"Rewrite für diesen Mode läuft über die OpenAI-Cloud."` blendet ein (system-default state-change, keine Animation). |
| User wählt im Picker `.openAI` → `.appleFoundation` bei `availability == .unavailable(...)` | Setting-Wert ändert. Banner bleibt unverändert (er reagiert auf `availability`, nicht auf Picker). Nächster Inferenz-Call wird vom `AppleFoundationRewriteClient` mit deutscher Fehlermeldung abgefangen (AC-AVAIL-1; UI-Pfad ist nicht Phase-8-UI-Scope, sondern Inferenz-Pfad). |
| Hotkey gedrückt → HUD erscheint, Mode = `.blitztextPlus` | HUD zeigt `PulsingDot` + `LevelBars` + `langBadge` + **`backendBadge`** (Symbol nach `settings.rewriteBackend(for: .blitztextPlus)`). Window-Width 268. |
| Hotkey gedrückt → HUD erscheint, Mode = `.blitztext` (plain) | HUD zeigt `PulsingDot` + `LevelBars` + `langBadge`, **kein** `backendBadge`. Window-Width effektiv 268, aber HStack-Inhalt schmaler — Content ist HStack-zentriert, also kein Layout-Problem. (Alternativ: Window-Width für plain auf 240 zurück; aber das fügt State-abhängige Window-Geometrie ein, die den Controller-Code komplizierter macht — die 268-pt-Konstante mit zentriertem Content ist die einfachere Wahl. Planner darf neu bewerten.) |
| User wechselt während Recording den Mode (z.B. via Mode-Picker im Menubar-HUD) | unmöglich, weil Recording exklusiv pro Hotkey läuft. Out-of-scope. |
| App-Start: `bootstrap()` schaltet Auto-Fallback auf `.openAI` | Settings-Tab beim ersten Öffnen direkt mit Banner A/B/C + D. Kein Toast (Apple HIG: stille Default-Anpassungen werden im Settings sichtbar gemacht, nicht via transient Notification). |

---

## Accessibility

macOS-native VoiceOver-Behavior. Keine Custom-A11y-Implementierung in v1 nötig — System defaults reichen. Punkte, die der Executor sicherstellen muss:

- **Picker** trägt sichtbares Label `"Backend"` über sich → VoiceOver liest "Backend, Popup-Schaltfläche, Apple Foundation lokal" (oder "OpenAI gpt-4o-mini Cloud"). Keine `.accessibilityLabel`-Override nötig.
- **Banner-Heading** ist `Text(...)` mit `.subheadline` → automatisch vorlesbar als statischer Text.
- **Banner-Symbol** ist dekorativ → `.accessibilityHidden(true)` setzen, sonst doppelt vorgelesen ("Symbol" + Heading).
- **Banner B — ProgressView** (indeterminate) → SwiftUI-default A11y reicht (VoiceOver sagt "in Bearbeitung" o.ä.); optional `.accessibilityLabel("Apple-Foundation-Modell wird geladen")` für klarere Ansage.
- **Banner B — "Erneut prüfen"-Button** → automatisches Button-Label aus dem `Button("Erneut prüfen")`-String. Kein Override.
- **Banner A — Link** → `Link("Systemeinstellungen öffnen …", destination: …)` ist von Haus aus A11y-konform; VoiceOver kündigt "Link" + Label an.
- **HUD-`backendBadge`** ist im click-through-Window — Standard-VoiceOver-Pfad ist eingeschränkt (Panels mit `nonactivatingPanel` werden vom Voice-Cursor oft übersprungen). **Kein A11y-Contract hier in v1.** Das `.help(...)`-Tooltip dient als Accessibility-Inspector-Hinweis, aber wird vom regulären VoiceOver beim Recording-HUD nicht zuverlässig erreicht. Akzeptabel, weil das HUD ein transienter Indikator ist, dessen Information (Backend-Wahl) im Settings-Tab voll A11y-erschließbar ist.
- **Dynamic Type**: alle Settings-Texte nutzen semantic styles → adaptieren automatisch. HUD-Pixel-Schrift bleibt fix (`size: 10`) — entspricht existing `langBadge`-Konvention; Trade-off bewusst (HUD-Geometrie ist fest 268×56, Dynamic Type würde sie sprengen).
- **Reduced Motion**: keine Custom-Animationen in Phase 8. ProgressView (Banner B) hat System-Default-Spinner — respektiert Reduced Motion automatisch.
- **Increase Contrast**: `.orange`, `.secondary`, `.white.opacity(...)` sind System-Colors, adaptieren automatisch.

---

## Registry Safety

Plattform ist native SwiftUI/AppKit. Keine externen UI-Registries (kein shadcn, keine npm-Komponenten, kein Webkit-Embed). Alle UI-Bausteine sind Apple-System-Frameworks oder bereits im Projekt vorhanden.

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| Apple SwiftUI | `Picker`, `Text`, `HStack`, `VStack`, `Image(systemName:)`, `Capsule`, `ProgressView`, `Button`, `Link` | not applicable (Apple-System) |
| SF Symbols | `apple.logo`, `cloud`, `exclamationmark.circle`, `arrow.triangle.2.circlepath` | not applicable (Apple-System) |
| Apple FoundationModels Framework | `SystemLanguageModel`, `LanguageModelSession`, `@Generable` | not applicable (Apple-System; Researcher-Aufgabe für Planner: Live-Doku-Verifikation) |
| Project-internal | bestehender `section`-Helper im `AnpassenTab`, bestehendes `RecordingHUDView`-Capsule-Pattern (`langBadge`) als visuelles Template | reviewed (existing project code) |
| Third-party (npm/shadcn/SPM-UI) | none | not applicable |

**Begründung "not applicable":** Web-Registry-Vetting (`shadcn view`, fetch-Pattern-Scan) hat auf einer macOS-Native-App keine Anwendung. Vergleichbare Sicherheit hier: keine Closed-Source-UI-Frameworks außerhalb Apples eigenen, kein neuer SPM-Dependency-Pull für Phase 8. Apple `FoundationModels`-Framework ist erstes-Party-API ab macOS 26; sicherheitsrelevant nur die korrekte Version-Guard-Verwendung (Planner-Detail).

---

## Visual References

- **Existing Pattern Match (Picker-Stil) — must look identical:** `Picker("Backend", selection: $settings.backend)` im `LokalTab` (`SettingsView.swift:338-340`). Phase-8-Backend-Picker übernimmt exakt dieselbe Form: Label-String `"Backend"`, ohne `pickerStyle`-Override (= macOS-default-Menu).
- **Existing Pattern Match (Section-Sub-Header):** `Text("Schreibstil").font(.subheadline)` im `AnpassenTab` BLITZTEXT+ Section (`SettingsView.swift:71`). Phase-8 nutzt `Text("Backend").font(.subheadline)` mit `.padding(.top, 6)` — gleiche optische Trennung zwischen TextEditor und nächster Steuerung.
- **Existing Pattern Match (Soft-Warnung-Inline):** `Text("Lokales Backend gewählt, aber kein Modell aktiviert. …").font(.caption).foregroundStyle(.orange)` im `LokalTab` (`SettingsView.swift:342-343`). Banner-D-Auto-Fallback-Zeile folgt exakt diesem Stil.
- **Existing Pattern Match (Loading-Indikator-Inline):** `HStack(spacing: 8) { ProgressView().controlSize(.small); Text("…").font(.caption).foregroundStyle(.secondary) }` im `LokalTab` (`SettingsView.swift:346-350`). Banner-B nutzt das größere `.subheadline`-Heading + ProgressView daneben — visuell verwandt, aber für Banner-Kontext angemessen vergrößert.
- **Existing Pattern Match (Status-Pill mit Icon — Banner-Layout):** Phase-3-`permissionRow`-Pattern (`SettingsView.swift:274-285`) sowie Phase-3-Error-State (Phase-3-UI-SPEC State (d)). Banner-Layout ist 1:1 dieser Form: `HStack(alignment: .top, spacing: 12) { Icon, VStack { Heading, Detail, optional Action }, Spacer }`.
- **Existing Pattern Match (HUD-Capsule-Badge):** `langBadge` in `RecordingHUDController.swift:101-107`. `BackendBadge` ist visueller Klon mit Symbol statt Text und denselben Padding-/Background-/Foreground-Werten.
- **Phase 3 UI-SPEC (`03-UI-SPEC.md`):** Strukturelle Vorlage für diese Spec — selbe Headings, selbes Spacing-Tabellen-Format, selbe Color-Reservierungs-Logik. Phase 8 erbt die Konvention "System-Semantic-Colors only, keine Custom-Tokens, semantic styles für Typografie".

---

## Out of Scope (UI-Phase)

- **Inferenz-Fehler-UI (Foundation-Call schlägt zur Laufzeit fehl):** Phase 8 deckt nur die Verfügbarkeitsprüfung ab. Fehlermeldungen während des eigentlichen Rewrites (z.B. `LanguageModelSession.respond` wirft) leben im bestehenden `processor.state == .error`-Pfad und werden über das schon existierende Status-Line-Error-Rendering im Menubar-HUD (`HUDView.statusText`) ausgegeben — kein neues UI hier.
- **Backend-pro-History-Eintrag (transparente Reproduktion):** CONTEXT.md `<code_context>` erwähnt das als offenes Risiko. Nicht Teil der UI in Phase 8 — separate Initiative, eher v2 / `PERF-02`-Telemetry.
- **Pre-Warm-UI für Foundation-Cold-Start:** Wenn Cold-Start Latenz-relevant wird, könnte ein Status-Indikator wie `LokalTab.isPreloading` Sinn ergeben — aber CONTEXT.md schiebt das in Researcher-Klärungs-Bereich (Performance-Messung). Phase-8-UI hat keinen Pre-Warm-Indikator.
- **Backend-Wechsel-Confirm-Dialog:** Wechsel ist non-destruktiv → kein Dialog.
- **Batch-Backend-Setting (alle Modes auf einmal umschalten):** Pro Mode wählbar ist explizite CONTEXT-Decision. Kein "Apply to all"-Button.
- **Foundation-Modell-Versions-Anzeige:** Apple liefert kein UI-relevantes Versionsfeld. Out-of-scope.
- **Tooltip-Hover-Interaktion im HUD:** HUD ist click-through (`ignoresMouseEvents`), Tooltip via `.help()` ist deklarativ für Accessibility-Inspector. Keine Hover-Reveals.
- **Animation/Transition zwischen Banner-Varianten:** Hartes Re-Render. Apple HIG: Settings-State-Wechsel sollen nicht überanimiert werden.

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS — alle Strings deutsch, Tonfall konsistent mit `AnpassenTab`/`LokalTab` und Phase-3-UI-SPEC, drei Verfügbarkeits-Banner-Varianten + optionale Auto-Fallback-Zeile spezifiziert, Picker-Item-Labels mit Privacy-Klammer, HUD-Tooltips definiert
- [ ] Dimension 2 Visuals: PASS — drei Surfaces mit konkreter Komponentenliste; Banner-Layout 1:1 von Phase-3-`permissionRow`-Pattern; HUD-Badge-Layout 1:1 von existing `langBadge`; SF-Symbol-Wahl pro State festgelegt
- [ ] Dimension 3 Color: PASS — System-Semantic-Colors only (`.orange`, `.secondary`, `.tertiary`, System-default Picker-Tint, HUD-`.white.opacity(...)`-Konvention); `.red` bewusst nicht verwendet; Accent-Reservierung explizit pro Banner-Variante
- [ ] Dimension 4 Typography: PASS — fünf semantic styles aus SwiftUI (`.caption`, `.caption2`, `.subheadline`, system-default Picker, HUD-monospaced-`size:10` als Bestands-Konvention), Dynamic-Type-konform für Settings, HUD-Pixel-Schrift bewusst fix
- [ ] Dimension 5 Spacing: PASS — Werte alignt zu existing `AnpassenTab`-Spacing (8/12/18/20 pt) und HUD-Spacing (12/18 pt); HUD-Window-Width-Erhöhung (240 → 268) als einzige Geometrie-Anpassung dokumentiert
- [ ] Dimension 6 Registry Safety: PASS (n/a) — native macOS, keine externen UI-Registries; Apple `FoundationModels`-Framework ist Apple-System

**Approval:** pending
