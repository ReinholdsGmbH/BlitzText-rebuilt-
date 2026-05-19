# Phase 7: Standard-Hotkeys & eigene Hotkeys — Research

**Researched:** 2026-05-19
**Domain:** macOS Global Hotkeys (Carbon API, CGEventTap), SwiftUI Settings-Tab, SettingsStore-Erweiterung
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (aus CONTEXT.md)

### Locked Decisions

**Trigger-Architektur**
- Hybrid-Schema: fn-Schnellpfad (CGEventTap, wie heute) bleibt **für Hold-Mode** erhalten — niedrige Latenz beim Halten ist Markenversprechen. Zusätzlich kann pro Mode eine freie Tastenkombo (z.B. ⌘⇧B) für **Toggle-Mode** hinterlegt werden.
- Implementierungspfad freie Kombos: externes Swift-Package — Kandidaten `soffes/HotKey` oder `shpakovski/MASShortcut`. Researcher prüft Swift-6-Concurrency-Kompatibilität und liefert Empfehlung.
- Zwei parallele Hotkey-Pfade nebeneinander — bestehender CGEventTap bleibt **unverändert**; neuer Pfad ist additiv. Gemeinsamer `onTrigger(Mode, Action)` Callback.

**Default-Set & Migration**
- Defaults bei Erst-Install und Reset: Hold-Pfad behält fn+Shift / fn+Ctrl / fn+Option (1:1 wie heute). Toggle-Pfad startet **leer** — User belegt selbst.
- Migration bestehender Nutzer: keine erzwungene Änderung. Custom-Toggle-Bindings sind opt-in.
- Persistenz: Custom-Bindings im bestehenden `SettingsStore` (UserDefaults JSON), gleiche Snapshot-Pattern.

**UI**
- Eigener Settings-Tab "Hotkeys" (neben Anpassen, Zugang, etc. in SettingsView.swift).
- Tabelle mit einer Zeile pro Mode. Spalten: Mode-Name + Beschreibung, Hold-Hotkey (fn+…) read-only, Toggle-Hotkey (frei via Recorder), Reset-Button.
- Recorder: bestehende `KeyRecorderViewModel`-Infrastruktur aus SettingsView.swift wird wiederverwendet (kein separates SPM UI-Package nötig laut UI-SPEC).

**Konflikt- & Reset-Verhalten**
- System-Konflikte: nachsichtig — App registriert trotzdem; bei möglicher Kollision erscheint dezentes Warn-Banner. Prüfmechanismus: **statische Liste** bekannter System-Kombos (keine dynamische API).
- In-App-Doppelbelegung: wird im Recorder **vorab verhindert**. Klare Inline-Fehlermeldung.
- Reset: **pro-Hotkey-Reset-Button** (löscht nur ein Binding, kein globaler Reset).
- Edge-Case "nur Modifier": Kombos ohne Buchstaben/Zahl/F-Taste werden vom Recorder abgelehnt.

### Claude's Discretion

- _(keine — Diskussion blieb scope-konform)_

### Deferred Ideas (AUSSERHALB DES SCOPE)

- Neue Modes (neue Hotkey-Domains)
- Globale Aufnahme-/Cancel-Shortcuts
- Snippet-Hotkeys
</user_constraints>

---

## Summary

Phase 7 erweitert BlitzText um einen neuen Settings-Tab "Hotkeys" und einen **zweiten, additiven Hotkey-Registrierungspfad** (freie Tastenkombos für Toggle-Mode) neben dem bestehenden CGEventTap-Pfad für fn+Modifier-Hold-Hotkeys.

**Wichtigste Erkenntnis aus der Forschung:** Die im CONTEXT.md genannten Kandidaten `soffes/HotKey` und `shpakovski/MASShortcut` sind beide **nicht empfehlenswert** für dieses Projekt. Stattdessen ist `sindresorhus/KeyboardShortcuts` (v2.4.0, Sept. 2025) die überlegene Wahl: Swift 6 mit `swift-tools-version:6.2`, `@MainActor`-Default-Isolation, `Shortcut` als `Codable & Sendable`-Struct, aktiv gepflegt, 2.7k+ Stars, Carbon-API-Wrapper (kein TCC-Bedarf), klar kompatibel mit `SWIFT_STRICT_CONCURRENCY: minimal`.

**Zweite wichtige Erkenntnis:** Die bestehende `KeyRecorderViewModel`-Klasse in `SettingsView.swift` deckt den UI-Recorder-Use-Case bereits vollständig ab. Das SPM-Package wird **ausschliesslich für die Hintergrundregistrierung** (HotkeyManager) benötigt, nicht für die UI. Die Phase 7 UI kann komplett nativ gebaut werden.

**Dritte Erkenntnis:** Carbon `RegisterEventHotKey` (wie `KeyboardShortcuts` es nutzt) und `CGEventTap` (bestehender fn-Pfad) **koexistieren problemlos** in derselben macOS-App — sie beobachten verschiedene Event-Ebenen und stören sich nicht gegenseitig.

**Primäre Empfehlung:** `sindresorhus/KeyboardShortcuts` als Toggle-Hotkey-Registrierungspfad. Neuer `ToggleHotkeyManager`-Layer additiv in `HotkeyManager.swift`. Neuer `HotkeysTab` in `SettingsView.swift` mit bestehender `KeyRecorderViewModel`-Infrastruktur und neuen `SettingsStore`-Properties für Toggle-Bindings.

---

## Project Constraints (aus CLAUDE.md)

| Direktive | Auswirkung auf Phase 7 |
|-----------|----------------------|
| Swift 6, `SWIFT_STRICT_CONCURRENCY: minimal` | SPM-Package muss Swift-6-kompatibel sein oder sicher unter `minimal` laufen |
| Kein Sandbox (`com.apple.security.app-sandbox: false`) | Carbon API (Basis von KeyboardShortcuts) braucht keine Entitlements |
| German UI strings | Alle neuen UI-Strings in RESEARCH.md/PLAN.md auf Deutsch |
| English code identifiers | Swift-Typen, Properties, Methoden auf Englisch |
| `project.yml` nie manuell editieren / xcodeproj nie hand-editieren | Neues SPM-Package via `project.yml` `packages:` Sektion eintragen |
| `SettingsStore` nur via Snapshot-Pattern erweitern | Neue Toggle-Hotkey-Properties als Optional mit `?? nil` in `load()` |
| `save()` nie manuell aufrufen | Combine-Debounce-Pipeline übernimmt auto-save |
| XCTest `BlitzTextTests`-Target existiert | Neue Tests landen in `BlitzTextTests/Hotkeys/` |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| fn+Modifier-Hold-Hotkeys | CGEventTap (HotkeyManager) | — | Unverändert. CGEventTap wird nicht berührt. |
| Freie Toggle-Hotkey-Registrierung | Carbon API via KeyboardShortcuts | HotkeyManager (Dispatch) | Carbon RegisterEventHotKey registriert globale Kombo. HotkeyManager leitet an onTrigger weiter. |
| Hotkey-Persistenz (Toggle-Bindings) | SettingsStore (UserDefaults JSON Snapshot) | — | Etabliertes Snapshot-Pattern, additiv erweiterbar. |
| Konflikt-Erkennung | Statische Liste im HotkeysTab | — | API unzuverlässig, kuratierte Liste ausreichend. |
| Recorder-UI | KeyRecorderViewModel (bereits vorhanden) | ToggleHotkeyRow (neu) | Bestehende ViewModel-Infrastruktur vollständig wiederverwendbar. |
| In-App-Doppelbelegungsprüfung | ToggleHotkeyRow / HotkeysTab | SettingsStore | Validierung vor `setToggleHotkeyBinding()` call. |
| Hold-Hotkey-Anzeige (read-only) | HoldHotkeyRow (neu) | — | Rein informativ, kein Recorder. |

---

## Standard Stack

### Core

| Library | Version | Purpose | Warum Standard |
|---------|---------|---------|----------------|
| `sindresorhus/KeyboardShortcuts` | 2.4.0 (Sept. 2025) | Globale Hotkey-Registrierung via Carbon API | Swift 6 (`swift-tools-version:6.2`), `@Sendable` + `@MainActor`-Isolation, `Shortcut: Codable & Sendable`, aktiv gepflegt (50 Releases, letztes Sept. 2025), kein TCC-Bedarf, non-sandbox-kompatibel. [VERIFIED: GitHub + SwiftPackageIndex] |
| `SwiftUI` | System (macOS 26) | HotkeysTab, HoldHotkeyRow, ToggleHotkeyRow, ConflictWarningBanner | Bereits im Projekt; alle bestehenden Settings-Tabs nutzen SwiftUI nativ. [VERIFIED: Codebase-Scan] |
| `Combine` | System | SettingsStore auto-save, @Published toggle-hotkey-Bindings | Bereits im Projekt; SettingsStore.objectWillChange-Debounce. [VERIFIED: Codebase-Scan] |

### Supporting (bereits vorhanden, keine Neu-Installation)

| Library | Version | Purpose | Wenn nötig |
|---------|---------|---------|------------|
| `KeyRecorderViewModel` | In-Codebase | Recorder-UI-Logic für ToggleHotkeyRow | Existiert bereits in SettingsView.swift (Zeile 926–998). Direkt wiederverwendbar. |
| `HotkeyBinding` | In-Codebase | Datenmodell für Hold- und Toggle-Bindings | Existiert bereits in HotkeyManager.swift (Zeile 348–397). Codable, Sendable, Equatable. |
| `HotkeyModifier` | In-Codebase | Modifier-Enum (fn, cmd, ctrl, opt, shift) | Existiert bereits in HotkeyManager.swift (Zeile 312–344). Codable, CaseIterable. |

### Alternativen (ausgeschlossen)

| Statt | Könnte man nutzen | Trade-off / Ausschlussgrund |
|-------|-------------------|-----------------------------|
| `sindresorhus/KeyboardShortcuts` | `soffes/HotKey` | HotKey: `swift-tools-version:5.0`, kein Swift-6-Concurrency-Support deklariert, letzte Version 0.2.1 (Dez. 2024), 32 offene Issues ohne aktive Bearbeitung, letzter PR vor >1 Jahr. Kein `Sendable` / `@MainActor`. [ASSUMED: Keine explizite Swift-6-Deklaration im Package.swift] |
| `sindresorhus/KeyboardShortcuts` | `shpakovski/MASShortcut` | MASShortcut: Objective-C-basiert, kein Swift-Package-First-Design, kein Swift-6-Concurrency, wartungsarmer Status. [ASSUMED: aus öffentlich sichtbaren GitHub-Commit-Frequenzen] |
| `sindresorhus/KeyboardShortcuts` | Eigene Carbon-Wrapper | Carbon `RegisterEventHotKey` hat komplexes Event-Handling, Lifecycle, Re-Registrierung nach App-Sleep — nicht hand-rollen. |

**Installation (project.yml):**

```yaml
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.4.0"
```

Und im Target-Dependencies-Block:

```yaml
dependencies:
  - package: KeyboardShortcuts
    product: KeyboardShortcuts
```

**Version-Verifikation:**
```bash
# Geprüft via GitHub Releases (sindresorhus/KeyboardShortcuts)
# Aktuellste Version: 2.4.0, veröffentlicht Sept. 18, 2025
# swift-tools-version:6.2 (verifiziert via Package.swift auf GitHub)
```

---

## Package Legitimacy Audit

> slopcheck konnte in dieser Umgebung nicht installiert werden. Alle Pakete sind daher `[ASSUMED]`-getaggt nach dem eingeschränkten Fallback-Protokoll. Da `KeyboardShortcuts` über WebFetch auf GitHub/SwiftPackageIndex verifiziert wurde (offizielle Quelle), ist das Risiko gering — trotzdem formales Tagging.

| Package | Registry | Alter | Downloads / Stars | Source Repo | slopcheck | Disposition |
|---------|----------|-------|-------------------|-------------|-----------|-------------|
| `KeyboardShortcuts` | Swift PM / GitHub | ~5 Jahre (2019–) | 2.7k+ GitHub Stars | github.com/sindresorhus/KeyboardShortcuts | N/A (slopcheck nicht verfügbar) | [ASSUMED] — Approved nach manueller GitHub-Verifikation |

**Pakete entfernt wegen slopcheck [SLOP]:** keine

**Pakete als verdächtig markiert [SUS]:** keine — KeyboardShortcuts ist ein etabliertes, bekanntes Swift-Package von sindresorhus (bekannter OSS-Autor, >200 Swift-Packages, verifiziertes GitHub-Profil).

*slopcheck war zum Forschungszeitpunkt nicht installierbar. Package wurde manuell über offizielle GitHub-Quelle verifiziert. Planner fügt optional einen `checkpoint:human-verify`-Task vor dem SPM-Install ein.*

---

## Architecture Patterns

### System Architecture Diagram

```
                    ┌─────────────────────────────────────┐
                    │         HotkeyManager                │
                    │                                     │
  fn+Modifier ──►  │  CGEventTap                         │
  (flagsChanged)    │  (unverändert, Hold + Toggle fn-Path)│─────────────────────────┐
                    │                                     │                         │
  freie Kombo  ──►  │  Carbon API via KeyboardShortcuts   │                         │
  (⌘⇧B etc.)        │  (neuer additiver Toggle-Pfad)      │                         │
                    └─────────────────────────────────────┘                         │
                                    │                                               │
                          onTrigger(Mode, Action)                                   │
                                    │                                               │
                                    ▼                                               │
                            ModeProcessor (unverändert)                            │
                                    │                                               │
                                    ▼                                         SettingsStore
                              Pipeline (Transkription, Rewrite, Clipboard)         │
                                                                                    │
  SettingsView.HotkeysTab ──────── read/write toggleHotkeyBinding(mode:) ──────────┘
         │
         ├── HoldHotkeyRow     (read-only, zeigt fn+Modifier-Binding)
         ├── ToggleHotkeyRow   (Recorder: KeyRecorderViewModel → HotkeyBinding)
         │       └── Validierung: Doppelbelegung + "nur Modifier"-Check
         └── ConflictWarningBanner (statische Liste, conditional sichtbar)
```

### Recommended Project Structure

Keine neue Directories nötig. Alle Änderungen in bestehenden Directories:

```
BlitzText/Hotkeys/
└── HotkeyManager.swift         # Erweiterung: ToggleHotkeyManager-Inner-Layer + register/unregister

BlitzText/Settings/
├── SettingsStore.swift         # +3 @Published var toggleHotkey{Mode}: HotkeyBinding?
│                               # +Snapshot-Erweiterung (3 optionale Felder)
│                               # +toggleHotkeyBinding(for:) + setToggleHotkeyBinding(_:for:)
└── SettingsView.swift          # +Tab.hotkeys Case + HotkeysTab + HoldHotkeyRow + ToggleHotkeyRow + ConflictWarningBanner
```

### Pattern 1: KeyboardShortcuts — Hotkey registrieren und deregistrieren

**Was:** Carbon-basierte globale Hotkey-Registrierung über `KeyboardShortcuts.Name` (benannte Shortcuts).

**Wann nutzen:** Einmalig beim App-Start (und bei Binding-Änderung) aufrufen, um freie Toggle-Combos zu registrieren.

```swift
// Source: github.com/sindresorhus/KeyboardShortcuts (README + Package.swift)
import KeyboardShortcuts

// Step 1: Namen deklarieren (1x, z.B. in HotkeyManager oder einem ToggleHotkeyManager)
extension KeyboardShortcuts.Name {
    static let toggleBlitztext     = Self("toggleBlitztext")
    static let toggleBlitztextPlus = Self("toggleBlitztextPlus")
    static let toggleBlitztextRant = Self("toggleBlitztextRant")
}

// Step 2: Shortcut aus HotkeyBinding konvertieren und setzen
// (HotkeyBinding → KeyboardShortcuts.Shortcut via carbonKeyCode + carbonModifiers)
func registerToggleHotkey(_ binding: HotkeyBinding, for mode: Mode) {
    guard let keyCode = binding.keyCode else { return }
    let carbonMods = binding.modifiers.reduce(0) { $0 | $1.carbonModifier }
    let shortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: UInt32(keyCode),
                                               carbonModifiers: UInt32(carbonMods))
    KeyboardShortcuts.setShortcut(shortcut, for: toggleName(mode))
}

// Step 3: Listener registrieren
func startListening() {
    KeyboardShortcuts.onKeyDown(for: .toggleBlitztext) { [weak self] in
        self?.onTrigger(.blitztext, .toggle)
    }
    // ... für alle 3 Modes
}

// Step 4: Deregistrieren bei App-Terminierung oder Binding-Änderung
func unregisterAll() {
    for mode in Mode.allCases {
        KeyboardShortcuts.setShortcut(nil, for: toggleName(mode))
    }
    KeyboardShortcuts.removeAllHandlers()
}
```

**Wichtig:** `KeyboardShortcuts` speichert Shortcuts intern in `UserDefaults` mit dem Präfix `"KeyboardShortcuts_"`. Da BlitzText seine Bindings im eigenen `SettingsStore.Snapshot` hält, muss die Synchronisation **einseitig** sein: SettingsStore ist Source-of-Truth, KeyboardShortcuts-intern wird nur als Registrierungs-Mechanismus genutzt (nicht als Persistenz-Backend). Bei jedem App-Start aus SettingsStore laden und via `KeyboardShortcuts.setShortcut(_:for:)` neu setzen. [VERIFIED: GitHub-Quellcode-Analyse]

### Pattern 2: HotkeyBinding → Carbon-Codes

`KeyboardShortcuts` erwartet `carbonKeyCode` (UInt32) und `carbonModifiers` (UInt32). Die bestehende `HotkeyBinding`-Struktur speichert `keyCode: UInt16?` (CGEventKeyCode) und `modifiers: Set<HotkeyModifier>`.

CGEvent-keyCodes sind **nicht identisch** mit Carbon-Key-Codes — sie sind aber für Standard-Tasten (Buchstaben, F-Tasten, Ziffern) in der Praxis identisch auf Apple-Silicon. Für Modifier braucht man Carbon-Flags:

```swift
// Source: github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/Shortcut.swift
// + Apple Carbon/Events.h (cmdKey, shiftKey, optionKey, controlKey)
extension HotkeyModifier {
    var carbonModifierFlag: UInt32 {
        switch self {
        case .command: return UInt32(cmdKey)        // 0x0100
        case .shift:   return UInt32(shiftKey)      // 0x0200
        case .option:  return UInt32(optionKey)     // 0x0800
        case .control: return UInt32(controlKey)    // 0x1000
        case .fn:      return 0                     // fn hat kein Carbon-Äquivalent — wird ABGELEHNT
        }
    }
}
```

**fn-Modifier muss aus Toggle-Bindings ausgeschlossen werden** — fn hat kein Carbon-Äquivalent und würde mit dem fn-CGEventTap-Pfad kollidieren. Dies ist bereits durch den UI-Spec-Edge-Case "nur Modifier" abgedeckt (Kombos ohne Buchstaben/F-Taste werden abgelehnt), aber fn muss **zusätzlich** als alleiniger Modifier abgelehnt werden. [CITED: Carbon/Events.h via developer.apple.com + KeyboardShortcuts Shortcut.swift]

### Pattern 3: SettingsStore-Erweiterung für Toggle-Hotkeys

Exakt dasselbe Pattern wie alle bisherigen Erweiterungen (Phase 3, Phase 8):

```swift
// Source: BlitzText/Settings/SettingsStore.swift (bestehendes Muster)
// Neue @Published Properties (Toggle-Hotkeys)
@Published var toggleHotkeyForBlitztext: HotkeyBinding? = nil
@Published var toggleHotkeyForBlitztextPlus: HotkeyBinding? = nil
@Published var toggleHotkeyForBlitztextRant: HotkeyBinding? = nil

// Snapshot-Erweiterung (optional mit nil-Default für Rückwärtskompatibilität)
private struct Snapshot: Codable {
    // ... bestehende Felder ...
    var toggleHotkeyForBlitztext: HotkeyBinding?      = nil
    var toggleHotkeyForBlitztextPlus: HotkeyBinding?  = nil
    var toggleHotkeyForBlitztextRant: HotkeyBinding?  = nil
}

// Accessor-Methoden (analog hotkeyBinding(for:) / setHotkeyBinding(_:for:))
func toggleHotkeyBinding(for mode: Mode) -> HotkeyBinding? { ... }
func setToggleHotkeyBinding(_ binding: HotkeyBinding?, for mode: Mode) { ... }
```

`HotkeyBinding` ist bereits `Codable + Equatable + Sendable` — keine Anpassung nötig. [VERIFIED: Codebase-Scan HotkeyManager.swift Zeile 348]

### Pattern 4: Additive Erweiterung des HotkeyManagers

Der bestehende CGEventTap in `HotkeyManager` darf **nicht verändert** werden. Der neue Pfad wird additiv als innere Schicht eingefügt:

```swift
// Konzept — Source: Ableitung aus CONTEXT.md + KeyboardShortcuts-API
final class HotkeyManager: @unchecked Sendable {
    // ... bestehende CGEventTap-Properties unverändert ...

    // Neu: Toggle-Hotkey-Registrierung via Carbon/KeyboardShortcuts
    // Kein separater Manager nötig — direkt als private Methoden in HotkeyManager

    private func setupToggleHotkeys() {
        for mode in Mode.allCases {
            guard let binding = settings.toggleHotkeyBinding(for: mode),
                  !binding.isEmpty, !binding.isModifierOnly else { continue }
            registerToggleHotkey(binding, for: mode)
        }
    }

    private func teardownToggleHotkeys() {
        KeyboardShortcuts.removeAllHandlers()
        for mode in Mode.allCases {
            KeyboardShortcuts.setShortcut(nil, for: toggleName(for: mode))
        }
    }
}
```

`start()` ruft `setupToggleHotkeys()` auf, `stop()` ruft `teardownToggleHotkeys()` auf.

Bei Binding-Änderung (über `SettingsStore.$toggleHotkeyForXxx.sink`) muss de-/re-registriert werden:

```swift
// Im HotkeyManager.start() nach installEventTap():
settings.$toggleHotkeyForBlitztext
    .sink { [weak self] _ in self?.reloadToggleHotkeys() }
    .store(in: &cancellables)
// ... analog für Plus und Rant
```

`cancellables: Set<AnyCancellable>` wird als neue private Property hinzugefügt. [ASSUMED: konkrete Combine-Implementierungsdetails]

### Pattern 5: ConflictWarningBanner — statische Liste

Gemäss CONTEXT.md und UI-SPEC (Abschnitt "Surface 4"): statischer Vergleich nach jedem Commit. Die kuratierte Liste ist bereits in der UI-SPEC festgelegt:

```swift
// Source: 07-UI-SPEC.md Surface 4
private let knownConflicts: [HotkeyBinding: String] = [
    HotkeyBinding(modifiers: [.command], keyCode: 49,  keyLabel: "Space"): "Spotlight",
    HotkeyBinding(modifiers: [.command, .option], keyCode: 49, keyLabel: "Space"): "Spotlight (Finder)",
    HotkeyBinding(modifiers: [.control], keyCode: 49, keyLabel: "Space"): "Eingabequellen wechseln",
    // + ⌘⌃Q, ⌘⇧3, ⌘⇧4, ⌘⇧5, ⌃F2, ⌃F3
]
```

Gleichheitsvergleich via `HotkeyBinding.Equatable`-Konformität — bereits vorhanden. [VERIFIED: Codebase-Scan HotkeyManager.swift Zeile 348]

### Anti-Patterns vermeiden

- **Nicht:** KeyboardShortcuts als Persistenz-Backend nutzen (UserDefaults-Key-Kollision mit eigenem Snapshot möglich). Stattdessen: SettingsStore als Source-of-Truth, KeyboardShortcuts nur als Registrierungs-Mechanismus.
- **Nicht:** CGEventTap für freie Toggle-Kombos erweitern. CGEventTap filtert mit Bitmaske — freie Kombos wären aufwändig zu matchen. Carbon API ist der richtige Layer.
- **Nicht:** `KeyboardShortcuts.Recorder` (die mitgelieferte SwiftUI-View) nutzen — `KeyRecorderViewModel` deckt den Use-Case bereits ab und passt exakt in das bestehende SwiftUI-Pattern.
- **Nicht:** fn-Modifier in Toggle-Bindings zulassen — Carbon kennt fn nicht; würde ausserdem mit dem CGEventTap-Pfad kollidieren.
- **Nicht:** Toggle- und Hold-Bindings in derselben `[Mode: HotkeyBinding]`-Map speichern — separate Properties behalten, sonst Migrations-Chaos.

---

## Don't Hand-Roll

| Problem | Nicht selbst bauen | Stattdessen nutzen | Warum |
|---------|--------------------|--------------------|-------|
| Globale Hotkey-Registrierung (Carbon) | Eigener Carbon-Wrapper mit `RegisterEventHotKey` + Event-Callback-Loop + Re-Register nach Sleep | `KeyboardShortcuts` | Carbon-Lifecycle (Un/Re-Register, Tap-Disabled-Recovery, App-Activation-State) hat >10 Edge-Cases. Existierende Library hat 5 Jahre Bug-Fixes. |
| Conflict-Detection via macOS-API | `CGSCopySpacesList`, `CGEventTapCreate` zur System-Hotkey-Enumeration | Statische kuratierte Liste (siehe UI-SPEC) | Apple stellt keine öffentliche API zum Lesen registrierter System-Shortcuts bereit. Alle bekannten Workarounds nutzen private APIs oder sind unzuverlässig auf macOS 14+. [CITED: AeroSpace Issue #1012 + Apple DTS Response] |
| Recorder-UI | Neue NSView-basierte Recorder-Komponente | Bestehende `KeyRecorderViewModel` (SettingsView.swift) | Bereits vollständig: keyDown/flagsChanged-Handling, Escape-Cancel, liveDisplay, onCommit-Callback. |

**Key Insight:** Carbon `RegisterEventHotKey` feuert **nachdem** die Frontmost-App das Event verarbeitet hat. Das ist für Toggle-Mode (freie Kombos im Nicht-Recording-Zustand) ausreichend — der User drückt ⌘⇧B, das Event geht durch die App, Carbon fängt es ab. Für fn+Modifier-Hold brauchen wir CGEventTap (vor der App), weil fn keine Standard-Carbon-Modifier ist. Genau das ist das Hybrid-Schema.

---

## Common Pitfalls

### Pitfall 1: KeyboardShortcuts-interne UserDefaults vs. SettingsStore

**Was schiefläuft:** `KeyboardShortcuts` speichert Shortcuts intern mit Präfix `"KeyboardShortcuts_"` in UserDefaults. Wenn der App-Start beide Quellen liest, kann es zu Inkonsistenzen kommen (SettingsStore hat Binding X, aber KeyboardShortcuts hat intern Binding Y registriert).

**Warum es passiert:** Die Library ist darauf ausgelegt, selbst als Persistenz-Backend zu fungieren. Wir verwenden sie aber nur als Registrierungs-Mechanismus.

**Wie vermeiden:** Beim App-Start (in `HotkeyManager.start()` nach `installEventTap()`) immer aus SettingsStore lesen und via `KeyboardShortcuts.setShortcut(_:for:)` die Library-interne Registry mit SettingsStore synchronisieren. Die Library speichert dabei intern — das ist akzeptabel solange SettingsStore Source-of-Truth bleibt.

**Warnsignal:** Hotkey funktioniert nach App-Restart nicht, obwohl SettingsStore die Binding enthält.

### Pitfall 2: Kein `cancellables` in `HotkeyManager` → Binding-Änderungen werden nicht re-registriert

**Was schiefläuft:** User ändert Toggle-Binding in Settings. Der alte Hotkey bleibt registriert, der neue nicht. Doppelfeuer oder keine Reaktion.

**Warum es passiert:** `HotkeyManager` ist `@unchecked Sendable` (CGEvent-C-Callback-Kontext) und hat bisher keine `AnyCancellable`-Set. Combine-Subscriptions auf SettingsStore-Properties werden nicht gespeichert und sofort dealloziert.

**Wie vermeiden:** `private var cancellables = Set<AnyCancellable>()` in `HotkeyManager` hinzufügen. `.store(in: &cancellables)` für alle drei Toggle-Hotkey-Publisher. In `stop()` `cancellables.removeAll()`.

**Warnsignal:** Test zeigt Doppelfeuer nach Binding-Wechsel.

### Pitfall 3: fn-Modifier in Carbon-Konvertierung führt zu lautlosem Fehler

**Was schiefläuft:** User tippt fn+⌘+B. `HotkeyBinding` enthält `.fn` in `modifiers`. Carbon-Konvertierung liefert `carbonModifiers = cmdKey | 0` (fn ignoriert). Carbon registriert ⌘B statt fn+⌘B — unerwartetes Verhalten.

**Warum es passiert:** fn hat kein Carbon-Äquivalent. Der Recorder erlaubt fn technisch (da NSEvent flagsChanged fn liefert), aber der Validierungscheck "nur Modifier" greift nur wenn KEIN Buchstabe/F-Taste gedrückt wurde.

**Wie vermeiden:** Beim Commit der Toggle-Binding **zusätzlich prüfen**: `if binding.modifiers.contains(.fn) { reject }`. Diese Validierung gehört in `ToggleHotkeyRow.onCommit()` VOR dem SettingsStore-Schreiben. Entsprechende Fehlermeldung: "fn-Taste kann nicht für freie Hotkeys verwendet werden."

**Warnsignal:** ⌘B statt fn+⌘B wird ausgelöst.

### Pitfall 4: Re-Registrierung beim App-Restart ohne Cleanup

**Was schiefläuft:** `HotkeyManager.start()` ruft `setupToggleHotkeys()` auf. Wenn `start()` zweimal aufgerufen wird (z.B. durch Permission-Watcher nach TCC-Grant), werden Hotkeys doppelt registriert. Carbon feuert Event doppelt → zwei `onTrigger`-Aufrufe → Race Condition in Pipeline.

**Warum es passiert:** `installEventTap()` hat bereits einen `guard eventTap == nil` Idempotenz-Check. `setupToggleHotkeys()` braucht denselben Schutz.

**Wie vermeiden:** `private var toggleHotkeysActive = false` als Guard. `setupToggleHotkeys()` früh returnen wenn `toggleHotkeysActive == true`. In `teardownToggleHotkeys()` auf `false` setzen.

**Warnsignal:** Double-fire beim ersten Hotkey-Press.

### Pitfall 5: Swift-6-Concurrency — `@MainActor` vs. `@unchecked Sendable` in HotkeyManager

**Was schiefläuft:** `KeyboardShortcuts.onKeyDown(for:handler:)` ruft den Handler auf dem Main Thread (da `@MainActor`-Default-Isolation im Package). `HotkeyManager` ist `@unchecked Sendable`. Der bestehende CGEventTap-Callback dispatcht via `DispatchQueue.main.async`. Beide Pfade landen auf dem Main Thread — kein Problem. Aber wenn der Combine-Sink für Binding-Änderungen auf einem anderen Thread feuert, kann es Probleme geben.

**Wie vermeiden:** Combine-Sinks mit `.receive(on: RunLoop.main)` wrappen:

```swift
settings.$toggleHotkeyForBlitztext
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in self?.reloadToggleHotkeys() }
    .store(in: &cancellables)
```

[ASSUMED: exakter Threading-Kontext des SettingsStore.objectWillChange ohne explizite Verifikation]

---

## Code Examples

### HotkeyManager-Erweiterung (Konzeptskizze)

```swift
// Source: Abgeleitet aus HotkeyManager.swift (Codebase) + KeyboardShortcuts README
import KeyboardShortcuts
import Combine

// In HotkeyManager — neue Properties
private var cancellables = Set<AnyCancellable>()
private var toggleHotkeysActive = false

// In start() — nach installEventTap() bzw. in startPermissionWatcher()-Callback:
private func setupToggleHotkeys() {
    guard !toggleHotkeysActive else { return }  // Idempotenz-Guard
    toggleHotkeysActive = true

    // Aus SettingsStore laden und Carbon-Registry befüllen
    for mode in Mode.allCases {
        if let binding = settings.toggleHotkeyBinding(for: mode), !binding.isEmpty {
            registerToggleHotkey(binding, for: mode)
        }
    }

    // Handler registrieren (Carbon feuert auf Main Thread via KeyboardShortcuts)
    for mode in Mode.allCases {
        KeyboardShortcuts.onKeyDown(for: toggleName(for: mode)) { [weak self] in
            guard let self else { return }
            let trigger = self.onTrigger
            DispatchQueue.main.async { trigger(mode, .toggle) }
        }
    }

    // Auf Binding-Änderungen reagieren
    Publishers.MergeMany([
        settings.$toggleHotkeyForBlitztext.map { _ in () }.eraseToAnyPublisher(),
        settings.$toggleHotkeyForBlitztextPlus.map { _ in () }.eraseToAnyPublisher(),
        settings.$toggleHotkeyForBlitztextRant.map { _ in () }.eraseToAnyPublisher()
    ])
    .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
    .sink { [weak self] in self?.reloadToggleHotkeys() }
    .store(in: &cancellables)
}

private func reloadToggleHotkeys() {
    teardownToggleHotkeys()
    setupToggleHotkeys()
}

private func teardownToggleHotkeys() {
    toggleHotkeysActive = false
    cancellables.removeAll()
    KeyboardShortcuts.removeAllHandlers()
    for mode in Mode.allCases {
        KeyboardShortcuts.setShortcut(nil, for: toggleName(for: mode))
    }
}

private func toggleName(for mode: Mode) -> KeyboardShortcuts.Name {
    switch mode {
    case .blitztext:     return .toggleBlitztext
    case .blitztextPlus: return .toggleBlitztextPlus
    case .blitztextRant: return .toggleBlitztextRant
    }
}
```

### ToggleHotkeyRow-Validierung beim Commit

```swift
// Source: Abgeleitet aus KeyRecorderViewModel + CONTEXT.md Entscheidungen
private func handleCommit(_ binding: HotkeyBinding?) {
    guard let b = binding, !b.isEmpty else {
        // Escape gedrückt → keine Änderung
        isRecording = false
        return
    }

    // Validierung 1: Nur Modifier ohne Buchstabe/F-Taste → ablehnen
    if b.isModifierOnly {
        errorMessage = "Kombination ohne Buchstaben oder Funktionstaste ist nicht erlaubt."
        isRecording = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.errorMessage = nil }
        return
    }

    // Validierung 2: fn-Modifier in Toggle-Binding → ablehnen
    if b.modifiers.contains(.fn) {
        errorMessage = "fn-Taste kann nicht für freie Toggle-Hotkeys verwendet werden."
        isRecording = false
        return
    }

    // Validierung 3: Doppelbelegung prüfen
    for otherMode in Mode.allCases where otherMode != mode {
        if let existing = settings.toggleHotkeyBinding(for: otherMode), existing == b {
            errorMessage = "\(b.displayString) ist bereits für \(otherMode.title) vergeben."
            isRecording = false
            return
        }
    }

    // OK → Binding setzen, Recorder beenden
    settings.setToggleHotkeyBinding(b, for: mode)
    isRecording = false
    errorMessage = nil
}
```

### HotkeysTab — Tab-Integration

```swift
// Source: SettingsView.swift (Codebase) — Bestehendes Tab-Pattern
enum Tab: String, CaseIterable, Identifiable {
    case anpassen, zugang, lokal, sprecher, hotkeys  // hotkeys NEU
    var id: String { rawValue }
    var label: String {
        switch self {
        // ... bestehende Cases ...
        case .hotkeys: return "Hotkeys"
        }
    }
}
```

---

## State of the Art

| Alter Ansatz | Aktueller Ansatz | Seit | Impact |
|--------------|-----------------|------|--------|
| `soffes/HotKey` (2017) | `sindresorhus/KeyboardShortcuts` (2019, v2.x 2023+) | ~2023 | Swift 6, `Sendable`, `@MainActor` — keine @unchecked-Umgehung nötig |
| Objective-C MASShortcut | Pure-Swift-Package (KeyboardShortcuts) | ~2020 | Einfachere Integration, Swift-Concurrency-kompatibel |
| Carbon API direkt (deprecated 2007) | Carbon über KeyboardShortcuts-Abstraktionsschicht | — | API bleibt intern, keine direkte Carbon-Nutzung im App-Code |

**Deprecated/veraltet:**
- `shpakovski/MASShortcut`: Objective-C, kein Swift-Package-First, de facto in Maintenance-Mode. Nicht empfohlen für neue Projekte.
- `soffes/HotKey`: swift-tools-version:5.0, kein Swift-6-Concurrency-Support. Letzte aktive Entwicklung >1 Jahr zurück.
- `NSEvent.addGlobalMonitorForEvents` als Alternative: braucht Accessibility-Permission (wie CGEventTap), liefert keine Events wenn die eigene App frontmost ist. Für diesen Use-Case schlechter als Carbon.

---

## Assumptions Log

| # | Claim | Abschnitt | Risiko wenn falsch |
|---|-------|-----------|-------------------|
| A1 | `soffes/HotKey` hat keinen Swift-6-Concurrency-Support (nur `swift-tools-version:5.0` verifiziert) | Standard Stack | Gering — HotKey ist sowieso nicht empfohlen; falls doch Swift-6-kompatibel, ändert das die Empfehlung nicht (KeyboardShortcuts ist trotzdem besser) |
| A2 | `shpakovski/MASShortcut` ist in Maintenance-Mode / nicht Swift-6-kompatibel | Standard Stack | Gering — selbst wenn gepflegt, bleibt ObjC-Basis ein Nachteil; Empfehlung bleibt gleich |
| A3 | CGEvent-keyCodes und Carbon-keyCodes sind auf Apple-Silicon für Standard-Tasten identisch | Pattern 2 | MITTEL — wenn falsch, braucht man eine Lookup-Table für die Konvertierung. Muss im Wave-0-Spike verifiziert werden via kurzen Test. |
| A4 | `KeyboardShortcuts.onKeyDown`-Handler läuft auf Main Thread (durch `@MainActor`-Default-Isolation im Package) | Pitfall 5 | Gering — falls auf Background-Thread: `DispatchQueue.main.async`-Wrapper reicht |
| A5 | Combine-Sink auf `SettingsStore.$toggleHotkeyForBlitztext` kann vom Main Thread oder Background-Thread kommen | Pitfall 5 | Gering — `.receive(on: RunLoop.main)` als defensive Massnahme |
| A6 | `KeyboardShortcuts.removeAllHandlers()` entfernt alle Handler aller Namen, nicht nur die eigenen | Pattern 4 | MITTEL — falls die App noch andere KeyboardShortcuts-Handler hat (Phase 7 fügt erstmals das Package hinzu, also kein Konflikt aktuell) |

---

## Open Questions

1. **A3-Verifikation: keyCode-Äquivalenz CGEvent ↔ Carbon**
   - Was wir wissen: CGEvent nutzt `kVK_ANSI_*`-Konstanten (HID-keyCodes), Carbon nutzt `kHIKeyCode*`-Konstanten. Auf Apple-Silicon sind diese für die meisten Tasten identisch (z.B. `kVK_ANSI_A = 0x00`, `kHIKeyCode_A = 0x00`).
   - Was unklar ist: Ob es Ausnahmen gibt (Sondertasten, Numpad, F13–F20).
   - Empfehlung: Wave-0-Spike im Plan: kurzes `swiftc -typecheck`-Probe, das `KeyboardShortcuts.Shortcut(carbonKeyCode:carbonModifiers:)` mit einem bekannten keyCode (z.B. `kVK_ANSI_B = 0x0B`) initialisiert und zurück-konvertiert. Wenn identisch: A3 verifiziert, keine Lookup-Table nötig.

2. **`KeyboardShortcuts.removeAllHandlers()` vs. pro-Name-Entfernung**
   - Was wir wissen: Die Public API hat `removeAllHandlers()`. Es ist nicht dokumentiert ob es alle Handler aller registrierten `Name`-Instanzen entfernt.
   - Was unklar ist: Falls im restlichen Projekt-Leben weitere `KeyboardShortcuts.Name`s hinzukommen (andere Phase), könnte `removeAllHandlers()` zu aggressiv sein.
   - Empfehlung: Alternative: `KeyboardShortcuts.disable(.toggleBlitztext)` pro Name in `teardownToggleHotkeys()`. Planner soll prüfen ob diese API existiert.

3. **Bestehender Test-Failure in SpeakerMatchingTests**
   - Was wir wissen: `SpeakerMatchingTests.testApplyDiarization_mixedSpeakers_correctLabels` schlägt fehl (Phase 4/6-Scope-Issue, unabhängig von Phase 7).
   - Was unklar ist: Ob dieser Fehler Phase-7-Tests beeinflusst (eigene Test-Suite in `BlitzTextTests/Hotkeys/`).
   - Empfehlung: Phase 7 Tests in `BlitzTextTests/Hotkeys/ToggleHotkeyTests.swift` isolieren. Der bestehende Fehler ist nicht Phase-7-Scope.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build + Test | ✓ | 26.5 | — |
| Swift PM | Package-Resolution | ✓ | 6.3.2 | — |
| macOS 26 | Deployment-Target (project.yml) | ✓ | 25.5.0 | — |
| `sindresorhus/KeyboardShortcuts` | Toggle-Hotkey-Registrierung | Noch nicht im Projekt | 2.4.0 | Muss via `project.yml` hinzugefügt werden |

**Fehlende Dependencies ohne Fallback:** Keine — `KeyboardShortcuts` hat keinen Build-Blocker; Hinzufügen zu `project.yml` + `xcodegen generate` reicht.

**Hinweis zum Deployment-Target:** `project.yml` zeigt `MACOSX_DEPLOYMENT_TARGET: "26.0"` und `deploymentTarget: "26.0"`. `KeyboardShortcuts` unterstützt `macOS 10.15+`. Kein Kompatibilitätsproblem.

---

## Validation Architecture

### Test-Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode 26.5) |
| Config-Datei | `project.yml` (BlitzTextTests-Target bereits vorhanden) |
| Quick-Run | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/HotkeyStateMachineTests -only-testing:BlitzTextTests/ToggleHotkeyTests` |
| Full-Suite | `xcodebuild test -scheme BlitzText -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req ID | Verhalten | Test-Typ | Automatisierter Command | Datei vorhanden? |
|--------|----------|----------|------------------------|-----------------|
| SC-1 | Hold-Pfad (fn+Shift/Ctrl/Opt) verhält sich unverändert | unit | `-only-testing:BlitzTextTests/HotkeyStateMachineTests` | ✅ (bestehend) |
| SC-2 | Toggle-Hotkey-Registrierung: Binding in SettingsStore → KeyboardShortcuts registriert | unit | `-only-testing:BlitzTextTests/ToggleHotkeyTests` | ❌ Wave 0 |
| SC-2 | Toggle-Hotkey: Doppelbelegung wird abgelehnt | unit | `-only-testing:BlitzTextTests/ToggleHotkeyTests` | ❌ Wave 0 |
| SC-2 | Toggle-Hotkey: fn-Modifier wird abgelehnt | unit | `-only-testing:BlitzTextTests/ToggleHotkeyTests` | ❌ Wave 0 |
| SC-2 | Toggle-Hotkey: nur-Modifier-Kombo wird abgelehnt | unit | `-only-testing:BlitzTextTests/ToggleHotkeyTests` | ❌ Wave 0 |
| SC-2 | SettingsStore-Persistenz: Toggle-Binding überlebt Snapshot-Roundtrip | unit | `-only-testing:BlitzTextTests/ToggleHotkeyTests` | ❌ Wave 0 |
| SC-3 | HotkeysTab: Tab existiert in Tab-Enum | smoke | SmokeTests (bestehend) oder neuer SettingsViewTests | ❌ Wave 0 |
| SC-4 | ConflictWarning: bekannte Kombo triggert Banner-Visibility | unit | `-only-testing:BlitzTextTests/ToggleHotkeyTests` | ❌ Wave 0 |

**Hinweis zu SC-2 / HotkeyManager-Tests:** `HotkeyManager` ist `@unchecked Sendable` mit CGEvent-C-Callback — echter Carbon-Aufruf (`KeyboardShortcuts`) ist in Unit-Tests nicht testbar ohne laufende App. Der Testbare Seam ist die **Validierungslogik** (Doppelbelegung, fn-Check, nur-Modifier-Check) und die **SettingsStore-Persistenz**. Der eigentliche Registrierungs-Call kann nur in einem Manual-UAT-Schritt verifiziert werden.

### Sampling Rate

- **Per Task Commit:** `-only-testing:BlitzTextTests/HotkeyStateMachineTests -only-testing:BlitzTextTests/ToggleHotkeyTests`
- **Per Wave Merge:** Full Suite
- **Phase Gate:** Full Suite grün (mit Ausnahme des bereits bestehenden `SpeakerMatchingTests`-Failures, der Phase-4-Scope ist) vor `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `BlitzTextTests/Hotkeys/ToggleHotkeyTests.swift` — deckt SC-2 (Validierungslogik + SettingsStore-Roundtrip)
- [ ] `BlitzTextTests/Hotkeys/ConflictDetectionTests.swift` (optional, kann in ToggleHotkeyTests integriert werden)

*(Keine neuen Fixtures nötig — bestehende `SettingsStore()`-Initialisierung reicht)*

---

## Security Domain

> `security_enforcement: true` in config.json. ASVS Level 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | nein | — |
| V3 Session Management | nein | — |
| V4 Access Control | nein | — |
| V5 Input Validation | ja | Hotkey-Binding-Validierung im Recorder (fn-Check, nur-Modifier-Check, Doppelbelegung). Kein User-Input gelangt in Shell oder Netzwerk. |
| V6 Cryptography | nein | — |

### Known Threat Patterns für diesen Stack

| Pattern | STRIDE | Standard-Mitigation |
|---------|--------|---------------------|
| Hotkey-Hijacking durch Malware | Elevation of Privilege | Carbon `RegisterEventHotKey` ist auf .cgSessionEventTap-Ebene — keine Root-Rechte, nur User-Session. Accessibility ist bereits erteilt. Kein zusätzliches Risiko. |
| UserDefaults-Injection (Snapshot-Manipulation) | Tampering | Bestehender Schutzmechanismus: `JSONDecoder().decode(Snapshot.self, from: data)` mit optionalen Feldern — ungültige Daten führen zu `nil`-Fallback, nicht zu Crash. Toggle-Hotkey-Felder sind `HotkeyBinding?` — `nil` bei Decode-Fehler → kein Toggle-Hotkey gesetzt. |
| Ressourcen-Erschöpfung durch Hotkey-Re-Registrierung | Denial of Service | Idempotenz-Guard in `setupToggleHotkeys()` (`toggleHotkeysActive` Flag). Debounce-50ms auf Combine-Sink verhindert Registrierungs-Storm. |

**Bewertung:** Phase 7 hat kein High-ASVS-Risk. Die einzige sicherheitsrelevante Erweiterung ist UserDefaults-Persistenz neuer Felder — vollständig durch bestehendes Snapshot-Pattern abgedeckt.

---

## Sources

### Primary (HIGH confidence)

- `BlitzText/Hotkeys/HotkeyManager.swift` — Codebase-Scan: vollständige `HotkeyBinding`-Struct, `HotkeyModifier`-Enum, `CGEventTap`-Implementierung, `@unchecked Sendable`-Pattern
- `BlitzText/Settings/SettingsStore.swift` — Codebase-Scan: Snapshot-Pattern, `hotkeyBinding(for:)`-Accessor, bestehende Toggle-Hotkey-Persistenz-Struktur
- `BlitzText/Settings/SettingsView.swift` — Codebase-Scan: `KeyRecorderViewModel` (Zeile 926–998), `HotkeyRecorderRow` (Zeile 1002–1075), `Tab`-Enum
- `github.com/sindresorhus/KeyboardShortcuts` — WebFetch (README, Package.swift, Shortcut.swift, KeyboardShortcuts.swift): Swift 6 `swift-tools-version:6.2`, `Shortcut: Codable & Sendable`, Carbon-API-Basis, `@MainActor`-Default-Isolation
- `07-CONTEXT.md` — User-Entscheidungen (Locked Decisions)
- `07-UI-SPEC.md` — UI Design Contract (kuratierte Konflikt-Liste, State-Maschine der Rows, Copywriting)
- `project.yml` — Build-Konfiguration: Swift 6.0, macOS 26, SWIFT_STRICT_CONCURRENCY: minimal, bestehende SPM-Packages

### Secondary (MEDIUM confidence)

- AeroSpace Issue #1012 (nikitabobko/AeroSpace) — WebFetch: Apple DTS-Antwort zu CGEventTap vs. Carbon API-Koexistenz
- dev.to (quicopy): Carbon `RegisterEventHotKey` Koexistenz-Analyse — bestätigt Carbon-After-App-Processing-Behaviour
- `swiftpackageindex.com/sindresorhus/KeyboardShortcuts` — Swift-6-Kompatibilitäts-Bestätigung (HTTP 403 bei Direktaufruf, Daten via WebSearch bestätigt)

### Tertiary (LOW confidence)

- WebSearch-Ergebnis zu `soffes/HotKey` Maintenance-Status (nicht direkt via Repository-API verifiziert)
- WebSearch-Ergebnis zu `shpakovski/MASShortcut` Swift-6-Status

---

## Metadata

**Confidence breakdown:**

- Standard Stack (KeyboardShortcuts-Empfehlung): HIGH — Swift-6 via Package.swift direkt verifiziert, aktives Repository, 2.4.0 Sept. 2025
- Architecture (additiver Pfad): HIGH — vollständig aus bestehendem Code abgeleitet
- Pitfalls: MEDIUM — grösstenteils aus Code-Analyse und Carbon-API-Wissen; Pitfall 3 (keyCode-Äquivalenz) durch A3 als ASSUMED markiert
- UI-Pattern: HIGH — bestehende KeyRecorderViewModel voll dokumentiert, UI-SPEC bereits approved

**Research Date:** 2026-05-19
**Valid until:** 2026-07-01 (stable stack — KeyboardShortcuts selten breaking changes; Swift-6 settled)
