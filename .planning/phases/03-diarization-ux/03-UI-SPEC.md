---
phase: 3
slug: diarization-ux
status: approved
reviewed_at: 2026-05-01
shadcn_initialized: false
preset: none
platform: macOS-native (SwiftUI + AppKit)
created: 2026-05-01
---

# Phase 3 — UI Design Contract: Diarization-UX

> Visual und Interaction Contract für den Diarizer-Modell-Download-Block in `SettingsView` (Tab "Lokales Modell", Parakeet-Sektion). Generiert von gsd-ui-researcher; verifiziert von gsd-ui-checker. Plattform: native macOS — kein shadcn, kein Tailwind, keine Webkomponenten. Apple HIG ist die Referenz.

---

## Scope

Vier UI-States in einem einzigen Settings-Block (D-18). Block lebt unverändert an seiner heutigen Stelle: `BlitzText/Settings/SettingsView.swift:380-388`, innerhalb `LokalTab` → `PARAKEET TDT v3 (NVIDIA, via FluidAudio)`-Sektion. **Kein neuer Tab, keine Strukturänderung der Settings-Hierarchie** (D-17).

States:
1. **(a) Bereit / Toggle aktiv** — Modell installiert ODER Toggle off
2. **(b) Downloading** — Toggle visuell ersetzt durch Status-Label + Progress-Bar + ETA
3. **(c) Installiert / Confirmed** — schmale Bestätigungszeile unter dem Toggle
4. **(d) Fehler** — deutsche Fehlermeldung + Retry-Button (Toggle bleibt im Fehler-Block versteckt, ggf. eigener "Erneut versuchen"-Path)

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (native macOS) |
| Preset | not applicable |
| Component library | SwiftUI + AppKit (system) |
| Icon library | SF Symbols (system) |
| Font | San Francisco (`.body`, `.caption`, `.caption2`, `.subheadline` — SwiftUI Text-Styles) |
| Layout style | bestehende `LokalTab`-`section`-Helper-Form (Caption-Label `.bold().foregroundStyle(.secondary)` + content) |

**Begründung:** Keine Custom-Tokens. Wir folgen `SettingsView.swift`-Konventionen 1:1, damit der Diarizer-Block visuell ununterscheidbar von der Whisper/Parakeet-Sektion daneben ist. Jede Token-Erfindung wäre Drift gegenüber den restlichen Tabs.

---

## Spacing Scale

System-Default (SwiftUI `VStack(alignment: .leading, spacing: 8)` für Block-interne Items, `spacing: 18` zwischen Settings-Blöcken — aus `LokalTab.body`).

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4 pt | Icon-Text-Inline (`HStack(spacing: 4)`) |
| sm | 8 pt | Item-Spacing innerhalb eines Settings-Blocks (entspricht bestehendem `spacing: 8`) |
| md | 12 pt | HStack-Spacing für Status-Pill + Label + Spacer + Button (entspricht `permissionRow`'s `spacing: 12`) |
| lg | 18 pt | Vertikales Spacing zwischen Settings-Blöcken (existing `LokalTab` `VStack(spacing: 18)`) |
| Edge-Padding | 20 pt | ScrollView outer (existing `.padding(20)` in `SettingsView.body`) |
| ProgressView max width | 280 pt | Linear ProgressView im Diarizer-Block — alignt mit `langFilter`-Picker (`.frame(maxWidth: 280)`) |

**Exceptions:** keine. Wir leben in einem bestehenden Form-Layout — alles andere wäre Drift.

---

## Typography

SwiftUI semantic styles, keine numerischen Pixel-Werte. macOS skaliert automatisch mit System-Settings (Accessibility-fähig).

| Role | SwiftUI Style | Weight | Usage |
|------|---------------|--------|-------|
| Section-Caption | `.caption` | `.bold()` + `.foregroundStyle(.secondary)` | Block-Header `"PARAKEET TDT v3 …"` (existing) — Diarizer-Subzeilen erben dieses Pattern |
| Toggle-Label | system default (Toggle) | regular | `"Sprechererkennung (Diarization)"` |
| Status-Label (Downloading) | `.subheadline` | regular | `"Lädt Diarizer-Modell …"` Hauptzeile im (b)-State |
| Progress-Detail | `.caption` | regular, `.foregroundStyle(.secondary)` | `"42 % · noch ~30 s"` unter ProgressView |
| Body-Erklärung | `.caption2` | regular, `.foregroundStyle(.tertiary)` | bestehende Erklärungstexte unter dem Toggle (existing pattern Zeile 386, 384) |
| Inline-Confirmation | `.caption` | regular, `.foregroundStyle(.green)` | `"Modell vorhanden ✓"` |
| Fehlermeldung | `.caption` | regular, `.foregroundStyle(.red)` | drei Klassen siehe Copywriting |
| Retry-Button-Label | system default (Button `.bordered`) | regular | `"Erneut versuchen"` |

**Begründung der 4-Stil-Wahl:** Plattform-konform. SwiftUI semantic styles sind fester Bestandteil der HIG; Pixel-Override würde Dynamic Type brechen. Kein eigenes Heading nötig — der Settings-Block hat bereits den `PARAKEET TDT v3 …`-Caption-Header.

---

## Color

Native macOS-Semantic-Colors — kein Custom-Hex. SwiftUI `.foregroundStyle(...)` und `Color.green/.red/.orange` rendern automatisch hell/dunkel adaptiv.

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60 %) | system default Window-Background | Settings-Window-Surface — unverändert |
| Secondary (30 %) | `.foregroundStyle(.secondary)` (System-grau) | Erklärungstexte, Progress-Detail-Zeile, Section-Captions |
| Tertiary | `.foregroundStyle(.tertiary)` (heller) | Sekundär-Hinweise unter Toggle (entspricht `Zeile 384, 386`) |
| Accent (10 %) | `.green` (System) | Success-Indikator — Checkmark-Symbol + "Modell vorhanden ✓" |
| Warning | `.orange` (System) | reserviert (im Diarizer-Block in v1 NICHT genutzt — nur falls future Pre-Warm-Soft-Warnung kommt) |
| Destructive / Error | `.red` (System) | Fehlermeldung-Text in (d)-State; **NICHT** für Retry-Button (der ist neutral, weil Wiederherstellung, nicht Zerstörung) |
| Progress-Tint | system default `ProgressView` | Linear bar im Downloading-State — keine Tint-Override |

**Accent reserved for:**
- **`.green` ausschließlich für:** (i) Success-Checkmark-Icon `checkmark.circle.fill` neben `"Modell vorhanden ✓"` im (c)-State.
- **`.red` ausschließlich für:** (i) Error-Symbol `exclamationmark.triangle.fill`, (ii) deutsche Fehlermeldungs-Textzeile.
- **System ProgressView-Tint** (kein Override) für Linear-Bar.

**Begründung:** Bestehende `LokalTab`-Sektion nutzt exakt dieses Schema (`.green` für AKTIV/Preloaded, `.orange` für Warnung, `.red` für `lastError`). Drift wäre, hier eine Palette zu erfinden. Alles andere bleibt System-Default — das ist auf macOS richtig, weil `accentColor` system-weit vom User gesetzt wird.

---

## State-by-State Visual Spec

### State (a) — Toggle aktiv (default, kein Download nötig)

Layout (von oben nach unten, alles innerhalb der bestehenden `PARAKEET TDT v3 …`-Sektion):

```
PARAKEET TDT v3 (NVIDIA, via FluidAudio)         [bestehend, unverändert]
<bestehende Erklärung>                           [bestehend, unverändert]
<bestehender Backend-Hinweis>                    [bestehend, unverändert]

Toggle: "Sprechererkennung (Diarization)"        [bestehend, unverändert]
"Aktiviert Sprecher-Annotationen … ~80 MB.       [bestehend, unverändert
 Beim ersten Aktivieren dauert es etwas länger." → wird zu Subzeile (siehe c)]
```

Wenn Modell installiert ist: zusätzlich Inline-Confirmation **direkt unter** dem `.caption2`-Erklärungstext (siehe State c).

**Visuelle Komponenten:**
- `Toggle("Sprechererkennung (Diarization)", isOn: $settings.parakeetDiarization)` — unverändert
- `.caption2` Erklärungstext darunter — unverändert

### State (b) — Downloading (Toggle ersetzt durch Status-Label)

Layout — der Toggle verschwindet vollständig (D-03), an seiner Stelle:

```
HStack(spacing: 12):
  Image(systemName: "arrow.down.circle")   [.foregroundStyle(.secondary)]
  VStack(alignment: .leading, spacing: 4):
    Text("Lädt Diarizer-Modell …")          [.subheadline]
    ProgressView(value: progress)
      .progressViewStyle(.linear)
      .frame(maxWidth: 280)
    Text("42 % · noch ~30 s")               [.caption, .secondary]
  Spacer()
```

**Komponenten-Details:**
- SF Symbol: `arrow.down.circle` (wahl: passt zum Download-Akt; alternative `square.and.arrow.down` ist iOS-lastig)
- ProgressView Style: `.linear` — system default tint
- ETA-Format: `"\(percent) % · noch ~\(eta)"` — Pattern siehe Copywriting unten
- **Kein Cancel-Button** (D-04) — der Block ist während Download read-only
- Der `.caption2` Erklärungstext ("Aktiviert Sprecher-Annotationen …") **darf während Download sichtbar bleiben**, weil er den Sinn der Aktion erinnert — verhindert Kontextverlust.

**Wichtig (D-03 explizit):** Toggle-View darf in diesem State NICHT gerendert werden (auch nicht als disabled). Sonst entsteht der Eindruck "ist on, passiert aber nichts".

### State (c) — Installiert / Modell vorhanden ✓

Layout (Toggle bleibt sichtbar — er ist on und aktiv):

```
Toggle: "Sprechererkennung (Diarization)"      [on, interaktiv]
HStack(spacing: 4):
  Image(systemName: "checkmark.circle.fill")   [.foregroundStyle(.green)]
  Text("Modell vorhanden")                     [.caption, .green]
"Aktiviert Sprecher-Annotationen … ~80 MB."    [.caption2, .tertiary — bestehend]
```

**Komponenten-Details:**
- Confirmation-Zeile **direkt unter** dem Toggle, **vor** dem `.caption2` Erklärungstext.
- Das `✓` ist NICHT im Text-String enthalten — wir nutzen das SF-Symbol für Konsistenz mit existing `permissionRow` (dort wird auch `checkmark.circle.fill` verwendet, Zeile 276).
- Wenn der User Toggle off klickt: Modell bleibt auf Disk (kein Auto-Delete in v1, siehe `<deferred>` in CONTEXT). Confirmation-Zeile verschwindet, weil sie nur bei `parakeetDiarization == true` sinnvoll ist.

### State (d) — Fehler mit Retry

Layout (Toggle wird durch Fehler-Block ersetzt — D-12: Toggle bleibt logisch on, aber UI zeigt Fehlerstand):

```
HStack(alignment: .top, spacing: 12):
  Image(systemName: "exclamationmark.triangle.fill")   [.foregroundStyle(.red)]
  VStack(alignment: .leading, spacing: 4):
    Text("Diarizer-Modell konnte nicht geladen werden") [.subheadline]
    Text(<deutscher Fehlertext, eine der drei Klassen>) [.caption, .red]
    Button("Erneut versuchen") { manager.retry() }     [.bordered]
```

**Komponenten-Details:**
- SF Symbol: `exclamationmark.triangle.fill` mit `.red` — entspricht existing `permissionRow`-Pattern (Zeile 276, dort `.orange`; hier `.red`, weil v1-Fehler sind harte Fehler, keine Soft-Warnungen)
- Retry-Button: System-Default (`.bordered`), **nicht** `.borderedProminent` — der Default-Button im Settings-Tab ist `Speichern` im Zugang-Tab (Zeile 236). Ein zweiter prominenter Button hier wäre falsch hierarchisiert.
- **Kein Cancel-Button**, kein "Toggle off"-Button. User-Intent (D-12) bleibt erhalten — wenn der User Diarization aufgeben will, klickt er den Toggle-Off-Pfad bewusst, sobald State zurück nach (a) wechselt.

---

## Copywriting Contract

Alle Strings auf Deutsch (CLAUDE.md / Conventions). Tonfall: nüchtern-direkt, gleicher Stil wie restliche `LokalTab`/`ZugangTab`-Texte (vgl. `"Lokales Backend gewählt, aber kein Modell aktiviert. Wähle …"`, `"freigegeben"`, `"abgelehnt — in Systemeinstellungen aktivieren"`). Keine Emojis im Text. Symbol-Confirmations nutzen SF Symbols, nicht Unicode-Glyphen.

| Element | Copy | Notes |
|---------|------|-------|
| Toggle-Label (state a, c) | `Sprechererkennung (Diarization)` | bestehend, unverändert |
| Toggle-Subtitle (caption2) | `Aktiviert Sprecher-Annotationen ("Sprecher 1: …"). Lädt zusätzlich ein Diarizer-Modell (~80 MB).` | bestehend, leicht gekürzt — "Beim ersten Aktivieren dauert es etwas länger" entfällt, weil ab v1 sichtbarer Fortschritt ersetzt diesen Hinweis |
| Status-Label (state b, Hauptzeile) | `Lädt Diarizer-Modell …` | drei Punkte als Auslassungszeichen (`…`, U+2026), nicht drei einzelne Punkte |
| Progress-Detail (state b) | `{percent} % · noch ~{eta}` | siehe ETA-Format unten. Beispiel: `42 % · noch ~30 s`. Mittlerer Punkt (`·`, U+00B7), nicht Bullet (`•`) — siehe existing `LocalModelRow.displaySize`-Stil |
| ETA-Format `< 60 s` | `noch ~{n} s` | gerundet auf ganze Sekunden. Beispiel: `noch ~5 s` |
| ETA-Format `60..3599 s` | `noch ~{m} min` | gerundet auf ganze Minuten. Beispiel: `noch ~2 min` |
| ETA-Format Anfangssekunden (`eta == nil`) | `Geschwindigkeit wird ermittelt …` | erste 1–2 Sekunden, bevor gleitender Durchschnitt verlässlich ist |
| Confirmation-Label (state c) | `Modell vorhanden` | Symbol-`✓` kommt aus SF `checkmark.circle.fill`, NICHT inline im String |
| Error-Heading (state d) | `Diarizer-Modell konnte nicht geladen werden` | konstant, unabhängig von Klasse |
| Error-Class: Netzwerk | `Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut.` | URLError-Domain `.notConnectedToInternet`, `.timedOut`, `.cannotFindHost`, `.cannotConnectToHost`, `.networkConnectionLost` |
| Error-Class: Speicher | `Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht).` | URLError `.dataNotAllowed`, NSCocoaError `NSFileWriteOutOfSpaceError`, POSIX `ENOSPC`. Wir prüfen NICHT pre-flight (D-deferred); Klassifikation erfolgt am Fehler-Objekt. |
| Error-Class: Unbekannt | `Download fehlgeschlagen. Versuch es später erneut — wenn das Problem bleibt, schau in das Log unter `~/Library/Logs/BlitzText.log`.` | Default-Fallback für alles, was nicht in Klasse 1 oder 2 fällt |
| Retry-Button | `Erneut versuchen` | nicht `Wiederholen` (zu nah an "Repeat"), nicht `Retry` (Englisch), nicht `Neu starten` (suggeriert App-Restart) |
| Empty-State | n/a | Diarization-Block hat keinen Empty-State — er ist immer Teil des Settings-Tabs. Wenn `parakeetDiarization == false`, ist der Toggle einfach off (state a). |
| Destructive confirmation | n/a | Phase 3 hat keine destruktiven Aktionen. Modell-Löschung ist explizit deferred (CONTEXT `<deferred>`). Retry löscht zwar partielle Dateien (D-11), aber ohne sichtbares Artefakt → keine Bestätigung nötig. |

**ETA-Algorithmus (UI-Side)** — Plan-Detail bleibt offen (D-discretion), aber das Display-Mapping ist Contract:

```
state.etaSeconds → display
  nil                 → "Geschwindigkeit wird ermittelt …"
  0..<60              → "noch ~\(Int(round(s))) s"
  60..<3600           → "noch ~\(Int(round(s/60))) min"
  >= 3600             → "noch ~\(Int(round(s/3600))) h"   // unwahrscheinlich bei 80 MB
```

**Throttling der Anzeige (D-discretion):** UI darf höchstens 10 Hz aktualisieren (gefühlt flüssig, schont CPU). Konkret: Manager publiziert `downloadProgress`/`etaSeconds` mit Throttle, View rendert ohne extra Throttle. Das bleibt Planner-Detail; UI-Contract ist nur: ProgressView läuft sichtbar smooth, ETA flackert nicht (also Update-Rate ≤ 10 Hz).

---

## Component Inventory

Konkrete SwiftUI-Komponenten, die der Executor liefert. Alle leben in `BlitzText/Settings/SettingsView.swift` (oder ein neuer File `DiarizerStatusBlock.swift`, Planner entscheidet — beide Optionen sind contract-kompatibel).

| Component | Type | Inputs | Outputs | Notes |
|-----------|------|--------|---------|-------|
| `DiarizerStatusBlock` (Arbeitstitel) | `private struct: View` | `@EnvironmentObject diarizerManager: DiarizerModelManager`, `@EnvironmentObject settings: SettingsStore` | switch über `manager.state` → eine der vier State-Views | ersetzt heutigen Toggle-Block ab Zeile 385 in `LokalTab.body` |
| state-(a)-View | inline | `Binding<Bool>` für `parakeetDiarization` | Toggle | unverändert vom heutigen Code |
| state-(b)-View | inline | `progress: Double`, `etaSeconds: Double?` | HStack mit Icon + ProgressView + Detail-Zeile | siehe State-Spec oben |
| state-(c)-View | inline | `Binding<Bool>` für `parakeetDiarization` | Toggle + Confirmation-HStack | Confirmation nur sichtbar wenn `parakeetDiarization == true` |
| state-(d)-View | inline | `errorMessage: String`, `onRetry: () -> Void` | Icon + Heading + Error-Text + Retry-Button | siehe State-Spec oben |

**Manager-Surface (für UI-Verbrauch — nicht Contract-Detail, aber nötig zur Verifikation):**
- `manager.state: DiarizerModelState` — switch-Quelle (D-15)
- `manager.start()` — vom Toggle-On-Side-Effect aufgerufen (nicht aus dieser View, sondern aus `SettingsStore.parakeetDiarization.didSet`)
- `manager.retry()` — vom Retry-Button-Handler aufgerufen
- `manager.downloadProgress: Double?`, `manager.etaSeconds: Double?` — `@Published` für `state(b)`-Detailzeile

---

## Interaction Contract

| Trigger | Expected UI Behavior |
|---------|---------------------|
| User flippt Toggle off → on, Modell fehlt | Block wechselt sofort von (a) → (b). Keine Animation nötig (Apple HIG: structural changes nicht überanimieren). |
| Download-Progress-Update | ProgressView füllt sich; Detail-Zeile zeigt aktualisierte `% · ~Restzeit`. Update-Rate ≤ 10 Hz. |
| Download fertig (success) | (b) → (c). Toggle ist sichtbar und on. Confirmation-Zeile mit `.green` Checkmark. |
| Download fehlgeschlagen | (b) → (d). Toggle visuell weg (D-12: nicht zurück auf off; logisch on bleibt erhalten). Fehlermeldung + Retry. |
| User klickt Retry | (d) → (b). Partielle Dateien werden gelöscht (D-11 Manager-Verhalten), Download startet neu. UI wechselt sofort zur Progress-Anzeige. |
| App-Start mit `parakeetDiarization == true`, Modell vorhanden | Pre-Warm im Hintergrund (D-13). Settings-Tab beim Öffnen direkt im (c)-State, kein Flackern. |
| App-Start mit `parakeetDiarization == true`, Modell fehlt | Hintergrund-Download startet (D-13). Settings-Tab beim Öffnen direkt im (b)-State mit aktuellem Progress. |
| App-Start mit `parakeetDiarization == true`, Pre-Warm-Fehler | Settings-Tab beim Öffnen im (d)-State mit `lastError`-Klassifikation (D-14). |
| User flippt Toggle on → off (state a) | `parakeetDiarization = false`. Modell bleibt auf Disk (kein Auto-Delete v1). Block-State bleibt (a). |
| User flippt Toggle on → off während (c) | wie oben. Confirmation-Zeile verschwindet, weil sie nur bei on sichtbar ist. |
| User klickt Toggle während (b) | technisch unmöglich, weil Toggle nicht gerendert (D-03). Falls SwiftUI-Layout-Race: kein Cancel (D-04). |
| User schließt Settings-Window während (b) | Download läuft im Hintergrund weiter. State wird beim Wieder-Öffnen reflektiert. |

---

## Accessibility

macOS-native VoiceOver-Behavior. Keine Custom-A11y-Implementierung in v1 — System defaults reichen für die vier Views. Punkte, die der Executor sicherstellen muss:

- **Toggle** trägt Label `"Sprechererkennung (Diarization)"` — automatisch von SwiftUI vorgelesen.
- **ProgressView** mit `.linear` style — VoiceOver liest aktuellen `value` automatisch. Optional: `.accessibilityLabel("Diarizer-Modell-Download")` und `.accessibilityValue("42 Prozent, noch etwa 30 Sekunden")` für klarere Ansage. Planner-Detail.
- **Status-Label** "Lädt Diarizer-Modell …" — als Text-View automatisch vorlesbar.
- **Fehler-Block**: `.accessibilityAddTraits(.isStaticText)` auf Heading, Retry-Button hat `.accessibilityLabel("Erneut versuchen")` automatisch.
- **Dynamic Type**: alle Texte nutzen semantic styles (`.subheadline`, `.caption`, `.caption2`) — passt sich automatisch an User-Settings an. Keine fixen Pixel.
- **Reduced Motion**: keine Custom-Animationen, daher trivial konform.
- **Increase Contrast**: System-Colors (`.green`, `.red`, `.secondary`) adaptieren automatisch.

---

## Registry Safety

Plattform ist native SwiftUI/AppKit. Keine externen UI-Registries (kein shadcn, keine npm-Komponenten, kein Webkit-Embed). Alle UI-Bausteine sind System-Frameworks oder bereits im Projekt vorhanden.

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| Apple SwiftUI | `Toggle`, `ProgressView`, `Button`, `Image(systemName:)`, `Text`, `HStack`, `VStack` | not applicable (Apple-System) |
| SF Symbols | `arrow.down.circle`, `checkmark.circle.fill`, `exclamationmark.triangle.fill` | not applicable (Apple-System) |
| Project-internal | bestehende `LokalTab`-Section-Helper, `permissionRow`-Pattern als visuelles Template | reviewed (existing project code) |
| Third-party (npm/shadcn) | none | not applicable |

**Begründung "not applicable":** Web-Registry-Vetting (`shadcn view`, fetch-Pattern-Scan, etc.) hat auf einer macOS-Native-App keine Anwendung. Die vergleichbare Sicherheit hier ist: keine Closed-Source-UI-Frameworks außerhalb von Apples eigenen, und kein neuer SPM-Dependency-Pull für Phase 3. FluidAudio ist bereits Bestandteil des Projekts (kein neues Dependency in Phase 3 — wir konsumieren es nur über `DiarizerModels(localPath:)`).

---

## Visual References

- **Existing Pattern Match (must look identical):** `LokalTab` → `BACKEND-WAHL`-Block (`SettingsView.swift:336-355`) — dort wird genauso ein `ProgressView().controlSize(.small)` + `.caption .secondary`-Text gerendert während `modelManager.isPreloading`. Diarizer-Block kopiert diesen visuellen Rhythmus.
- **Existing Pattern Match (Status-Pill mit Icon):** `permissionRow` (`SettingsView.swift:274-285`) — `Image(systemName:).foregroundStyle(.green/.orange)` + `Text.bold()` + secondary-subtitle. Confirmation- und Error-Zeilen folgen exakt dieser Form.
- **Existing Pattern Match (lastError):** `LokalTab` `if let err = modelManager.lastError { Text(err).foregroundStyle(.red).font(.caption) }` (Zeile 393-395) — identisches Muster wird hier strukturierter (Error-Heading + Klassifikations-Text + Retry-Button), aber visueller Stil bleibt.

---

## Out of Scope (UI-Phase)

- Tab-Reorganisation (Diarization bleibt im "Lokales Modell"-Tab — D-17)
- Lösch-Button für Diarizer-Modell (deferred zu Backlog)
- Cancel-Button während Download (D-04 explizit aus v1 ausgeschlossen)
- Auto-Retry-Indikator (D-10: kein Auto-Retry)
- Modell-Versionsanzeige (deferred)
- Disk-Space-Warnung pre-flight (deferred — Fehlermeldung-Klasse "Speicher" reicht)

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS — alle Strings deutsch, Tonfall konsistent mit `LokalTab`/`ZugangTab`, drei Fehler-Klassen + Retry-Label spezifiziert
- [ ] Dimension 2 Visuals: PASS — vier States mit konkreter Komponentenliste, SF-Symbol-Wahl + Größen festgelegt
- [ ] Dimension 3 Color: PASS — System-Semantic-Colors only (`.green`, `.red`, `.secondary`, `.tertiary`), Accent-Reservierung explizit
- [ ] Dimension 4 Typography: PASS — vier semantic styles aus SwiftUI (`.subheadline`, `.caption`, `.caption2`, system-default), Dynamic-Type-konform
- [ ] Dimension 5 Spacing: PASS — Werte alignt zu existing `LokalTab`-Spacing (8/12/18/20 pt), keine neuen Tokens
- [ ] Dimension 6 Registry Safety: PASS (n/a) — native macOS, keine externen UI-Registries

**Approval:** pending
