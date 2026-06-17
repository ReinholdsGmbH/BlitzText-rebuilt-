# Phase 7: Standard-Hotkeys & eigene Hotkeys — Pattern Map

**Mapped:** 2026-05-19
**Files analyzed:** 5 neue/geänderte Dateien
**Analogs found:** 5 / 5

---

## File Classification

| Neue / geänderte Datei | Role | Data Flow | Closest Analog | Match Quality |
|------------------------|------|-----------|----------------|---------------|
| `BlitzText/Settings/SettingsStore.swift` | model/store | CRUD | Sich selbst (additive Erweiterung) | exact |
| `BlitzText/Hotkeys/HotkeyManager.swift` | service | event-driven | Sich selbst (additiver Layer) | exact |
| `BlitzText/Settings/SettingsView.swift` (Tab-Enum + AnpassenTab-Refactor) | component | request-response | `SprecherTab` in SettingsView.swift | exact |
| `BlitzText/Settings/SettingsView.swift` → `HotkeysTab` (neu) | component | request-response | `AnpassenTab` + `SprecherTab` in SettingsView.swift | exact |
| `BlitzTextTests/Hotkeys/ToggleHotkeyTests.swift` (neu) | test | CRUD | `BlitzTextTests/HotkeyStateMachineTests` (bestehendes Muster) | role-match |

---

## Pattern Assignments

### 1. `BlitzText/Settings/SettingsStore.swift` — Additive Erweiterung

**Analog:** Sich selbst. Jede neue Phase erweitert `SettingsStore` nach demselben Snapshot-Pattern.

**Imports-Pattern** (Zeilen 1–3):
```swift
import Foundation
import Combine
```

**Neue @Published Properties — nach bestehenden Hotkey-Properties einfügen** (Referenz: Zeilen 11–13):
```swift
// Neu in Phase 7 — nach den bestehenden hotkeyFor*-Properties:
@Published var toggleHotkeyForBlitztext: HotkeyBinding?     = nil
@Published var toggleHotkeyForBlitztextPlus: HotkeyBinding? = nil
@Published var toggleHotkeyForBlitztextRant: HotkeyBinding? = nil
```

**Snapshot-Erweiterung — additive Optionals mit nil-Default** (Referenz: Zeilen 158–183, Pattern: `var aiSuggestProperNouns: Bool?`, `var ollamaModel: String?`):
```swift
private struct Snapshot: Codable {
    // ... alle bestehenden Felder unverändert ...
    // Neu: Toggle-Hotkey-Bindings — optional mit nil-Default für Rückwärtskompatibilität
    var toggleHotkeyForBlitztext: HotkeyBinding?     = nil
    var toggleHotkeyForBlitztextPlus: HotkeyBinding? = nil
    var toggleHotkeyForBlitztextRant: HotkeyBinding? = nil
}
```

**load()-Erweiterung — ?? nil Fallback** (Referenz: Zeilen 185–212, Pattern: `aiSuggestProperNouns = snap.aiSuggestProperNouns ?? true`):
```swift
// In load() — nach den bestehenden hotkeyFor*-Zuweisungen:
toggleHotkeyForBlitztext     = snap.toggleHotkeyForBlitztext     ?? nil
toggleHotkeyForBlitztextPlus = snap.toggleHotkeyForBlitztextPlus ?? nil
toggleHotkeyForBlitztextRant = snap.toggleHotkeyForBlitztextRant ?? nil
```

**save()-Erweiterung** (Referenz: Zeilen 214–244, Pattern: alle bestehenden Properties im Snapshot-Init):
```swift
// In save() — Snapshot-Init erweitern:
let snap = Snapshot(
    // ... alle bestehenden Parameter ...
    toggleHotkeyForBlitztext:     toggleHotkeyForBlitztext,
    toggleHotkeyForBlitztextPlus: toggleHotkeyForBlitztextPlus,
    toggleHotkeyForBlitztextRant: toggleHotkeyForBlitztextRant
)
```

**Accessor-Methoden — exaktes Pattern wie `hotkeyBinding(for:)` / `setHotkeyBinding(_:for:)`** (Referenz: Zeilen 122–137):
```swift
// Analog zu hotkeyBinding(for:) — Zeilen 122–128
func toggleHotkeyBinding(for mode: Mode) -> HotkeyBinding? {
    switch mode {
    case .blitztext:     return toggleHotkeyForBlitztext
    case .blitztextPlus: return toggleHotkeyForBlitztextPlus
    case .blitztextRant: return toggleHotkeyForBlitztextRant
    }
}

// Analog zu setHotkeyBinding(_:for:) — Zeilen 130–137
// WICHTIG: KEIN manuelles save() aufrufen — Combine-Debounce übernimmt auto-save (Zeilen 95–98)
func setToggleHotkeyBinding(_ binding: HotkeyBinding?, for mode: Mode) {
    switch mode {
    case .blitztext:     toggleHotkeyForBlitztext     = binding
    case .blitztextPlus: toggleHotkeyForBlitztextPlus = binding
    case .blitztextRant: toggleHotkeyForBlitztextRant = binding
    }
    // Kein save() — objectWillChange-Debounce (Zeile 96) übernimmt
}
```

**Auto-Save-Pattern (zur Erinnerung — nicht ändern)** (Zeilen 95–98):
```swift
objectWillChange
    .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
    .sink { [weak self] _ in self?.save() }
    .store(in: &cancellables)
```

---

### 2. `BlitzText/Hotkeys/HotkeyManager.swift` — Additiver Toggle-Layer

**Analog:** Sich selbst. Bestehender CGEventTap-Pfad bleibt vollständig unverändert. Neuer Pfad wird als private Methoden am Ende der Klasse eingefügt.

**Wichtige bestehende Patterns, die wiederverwendet werden:**

**`@unchecked Sendable`-Deklaration** (Zeile 9):
```swift
final class HotkeyManager: @unchecked Sendable {
```

**Idempotenz-Guard-Pattern** (Zeile 85 — genau so für `setupToggleHotkeys` nachbauen):
```swift
private func installEventTap() {
    guard eventTap == nil else { return }   // idempotent — kein doppelter Tap
    // ...
}
```

**DispatchQueue.main.async für Callback-Dispatch** (Zeilen 193–196):
```swift
DispatchQueue.main.async { trigger(m, .start) }
// bzw.
DispatchQueue.main.async { trigger(m, .toggle) }
```

**Neue Properties in HotkeyManager** (additiv nach bestehenden privaten Properties, ab Zeile 47):
```swift
// Neu: Combine-Subscriptions für Toggle-Hotkey-Binding-Änderungen
private var cancellables = Set<AnyCancellable>()
// Neu: Idempotenz-Guard für doppelte Registration verhindern (Pitfall 4)
private var toggleHotkeysActive = false
```

**Neue KeyboardShortcuts.Name-Erweiterung** (als Extension am Ende der Datei, nach HotkeyBinding):
```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleBlitztext     = Self("toggleBlitztext")
    static let toggleBlitztextPlus = Self("toggleBlitztextPlus")
    static let toggleBlitztextRant = Self("toggleBlitztextRant")
}
```

**setupToggleHotkeys() — Kern-Pattern** (abgeleitet aus RESEARCH.md Pattern 4, analog zu installEventTap()):
```swift
private func setupToggleHotkeys() {
    guard !toggleHotkeysActive else { return }  // Idempotenz-Guard (Pitfall 4)
    toggleHotkeysActive = true

    for mode in Mode.allCases {
        if let binding = settings.toggleHotkeyBinding(for: mode),
           !binding.isEmpty, !binding.isModifierOnly {
            registerToggleHotkey(binding, for: mode)
        }
    }

    for mode in Mode.allCases {
        let captured = mode
        KeyboardShortcuts.onKeyDown(for: toggleName(for: mode)) { [weak self] in
            guard let self else { return }
            let trigger = self.onTrigger
            DispatchQueue.main.async { trigger(captured, .toggle) }
        }
    }

    // Auf Binding-Änderungen reagieren (Pitfall 5: .receive(on: RunLoop.main))
    Publishers.MergeMany([
        settings.$toggleHotkeyForBlitztext.map { _ in () }.eraseToAnyPublisher(),
        settings.$toggleHotkeyForBlitztextPlus.map { _ in () }.eraseToAnyPublisher(),
        settings.$toggleHotkeyForBlitztextRant.map { _ in () }.eraseToAnyPublisher()
    ])
    .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
    .receive(on: RunLoop.main)
    .sink { [weak self] in self?.reloadToggleHotkeys() }
    .store(in: &cancellables)
}

private func teardownToggleHotkeys() {
    toggleHotkeysActive = false
    cancellables.removeAll()
    KeyboardShortcuts.removeAllHandlers()
    for mode in Mode.allCases {
        KeyboardShortcuts.setShortcut(nil, for: toggleName(for: mode))
    }
}

private func reloadToggleHotkeys() {
    teardownToggleHotkeys()
    setupToggleHotkeys()
}

private func registerToggleHotkey(_ binding: HotkeyBinding, for mode: Mode) {
    guard let keyCode = binding.keyCode else { return }
    // fn-Modifier hat kein Carbon-Äquivalent — Guard (Pitfall 3)
    guard !binding.modifiers.contains(.fn) else { return }
    let carbonMods = binding.modifiers.reduce(UInt32(0)) { $0 | $1.carbonModifierFlag }
    let shortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: UInt32(keyCode),
                                               carbonModifiers: carbonMods)
    KeyboardShortcuts.setShortcut(shortcut, for: toggleName(for: mode))
}

private func toggleName(for mode: Mode) -> KeyboardShortcuts.Name {
    switch mode {
    case .blitztext:     return .toggleBlitztext
    case .blitztextPlus: return .toggleBlitztextPlus
    case .blitztextRant: return .toggleBlitztextRant
    }
}
```

**HotkeyModifier-Erweiterung** (als Extension in HotkeyManager.swift nach HotkeyModifier-Enum, Zeile 344):
```swift
extension HotkeyModifier {
    /// Carbon-Modifier-Flag für KeyboardShortcuts. fn hat kein Carbon-Äquivalent (= 0).
    var carbonModifierFlag: UInt32 {
        switch self {
        case .fn:      return 0          // kein Carbon-Äquivalent — muss im Caller abgefangen werden
        case .command: return UInt32(cmdKey)     // 0x0100
        case .shift:   return UInt32(shiftKey)   // 0x0200
        case .option:  return UInt32(optionKey)  // 0x0800
        case .control: return UInt32(controlKey) // 0x1000
        }
    }
}
```

**Integration in `start()` und `stop()`** (nach bestehenden Calls in Zeilen 60–82):
```swift
func start() {
    let trusted = ensureAccessibilityPermission()
    if trusted {
        installEventTap()
        setupToggleHotkeys()  // NEU — additiv nach installEventTap()
    } else {
        startPermissionWatcher()
    }
}

func stop() {
    permissionTimer?.cancel()
    permissionTimer = nil
    // ... bestehender cleanup ...
    teardownToggleHotkeys()  // NEU — additiv am Ende von stop()
}
```

---

### 3. `BlitzText/Settings/SettingsView.swift` — Tab-Enum + HotkeysTab (neu)

**Analog:** `AnpassenTab` (Zeilen 53–188) für Section-Struktur, `SprecherTab` (Zeilen 539–574) für Warn-Banner-Pattern.

**Tab-Enum-Erweiterung** (Zeilen 10–21 — `.hotkeys` additiv einfügen):
```swift
enum Tab: String, CaseIterable, Identifiable {
    case anpassen, zugang, lokal, sprecher, hotkeys  // hotkeys NEU
    var id: String { rawValue }
    var label: String {
        switch self {
        case .anpassen:  return "Anpassen"
        case .zugang:    return "Zugang"
        case .lokal:     return "Lokales Modell"
        case .sprecher:  return "Sprecher"
        case .hotkeys:   return "Hotkeys"   // NEU
        }
    }
}
```

**Switch in body — `.hotkeys` Case hinzufügen** (Zeilen 36–41):
```swift
switch selectedTab {
case .anpassen:  AnpassenTab()
case .zugang:    ZugangTab()
case .lokal:     LokalTab()
case .sprecher:  SprecherTab()
case .hotkeys:   HotkeysTab()   // NEU
}
```

**Section-Helper-Pattern** (Zeilen 182–187 — von AnpassenTab verwenden, nicht in HotkeysTab duplizieren):
```swift
// In AnpassenTab: section() ist @ViewBuilder-Hilfsfunktion
private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.caption).foregroundStyle(.secondary).bold()
        content()
    }
}
```
**Hinweis:** `HotkeysTab` ist eine eigene `private struct` — die `section()`-Methode aus `AnpassenTab` ist nicht zugänglich. `HotkeysTab` baut Sections direkt als `VStack(alignment: .leading, spacing: 8)` nach dem identischen Inline-Pattern aus `LokalTab` (Zeilen 360–367).

**HotkeysTab — Kern-Layout** (analog AnpassenTab body-Struktur, Zeilen 57–63):
```swift
// MARK: - Hotkeys Tab (Phase 7)

private struct HotkeysTab: View {
    @EnvironmentObject var settings: SettingsStore

    // Statische Konflikt-Liste (CONTEXT.md: "nachsichtig, statische Liste")
    private let knownConflicts: [HotkeyBinding: String] = [
        HotkeyBinding(modifiers: [.command], keyCode: 49, keyLabel: "Space"):          "Spotlight",
        HotkeyBinding(modifiers: [.command, .option], keyCode: 49, keyLabel: "Space"): "Spotlight (Finder-Suche)",
        HotkeyBinding(modifiers: [.control], keyCode: 49, keyLabel: "Space"):          "Eingabequellen wechseln",
        HotkeyBinding(modifiers: [.command, .control], keyCode: 12, keyLabel: "Q"):    "Bildschirm sperren",
        HotkeyBinding(modifiers: [.command, .shift], keyCode: 20, keyLabel: "3"):      "Screenshot",
        HotkeyBinding(modifiers: [.command, .shift], keyCode: 21, keyLabel: "4"):      "Screenshot (Auswahl)",
        HotkeyBinding(modifiers: [.command, .shift], keyCode: 23, keyLabel: "5"):      "Screenshot-Optionen",
        HotkeyBinding(modifiers: [.control], keyCode: 0x78, keyLabel: "F2"):           "Menüleiste fokussieren",
        HotkeyBinding(modifiers: [.control], keyCode: 0x63, keyLabel: "F3"):           "Dock fokussieren",
    ]

    private var conflictingModes: [(Mode, String)] {
        Mode.allCases.compactMap { mode in
            guard let binding = settings.toggleHotkeyBinding(for: mode) else { return nil }
            if let conflictName = knownConflicts[binding] { return (mode, conflictName) }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // HOLD-HOTKEYS Section
            VStack(alignment: .leading, spacing: 8) {
                Text("HOLD-HOTKEYS").font(.caption).foregroundStyle(.secondary).bold()
                Text("fn + Modifier — Halten aktiviert Aufnahme. Nicht konfigurierbar.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Mode.allCases) { HoldHotkeyRow(mode: $0) }
            }

            Divider()

            // TOGGLE-HOTKEYS Section
            VStack(alignment: .leading, spacing: 8) {
                Text("TOGGLE-HOTKEYS").font(.caption).foregroundStyle(.secondary).bold()
                Text("Freie Tastenkombination für den Drücken-Modus. Optional — leer = kein Toggle-Hotkey.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Mode.allCases) { ToggleHotkeyRow(mode: $0) }
            }

            // ConflictWarningBanner (conditional)
            if !conflictingModes.isEmpty {
                Divider()
                ConflictWarningBanner(conflicts: conflictingModes)
            }
        }
    }
}
```

**HoldHotkeyRow** (read-only, neu — kein direktes Analog, nahe an bestehender BindingBadge-Idee aus HotkeyRecorderRow Zeilen 1026–1043):
```swift
private struct HoldHotkeyRow: View {
    let mode: Mode
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: mode.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(mode.title).font(.body).bold()
                Text(mode.subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            // BindingBadge read-only (fn+Modifier-Anzeige)
            let binding = settings.hotkeyBinding(for: mode)
            HStack(spacing: 4) {
                ForEach(HotkeyModifier.allCases.filter { binding.modifiers.contains($0) }, id: \.self) { mod in
                    Text(mod.symbol)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
```

**ToggleHotkeyRow** (interaktiv, neu — direktes Analog: `HotkeyRecorderRow` Zeilen 1002–1075):
```swift
// Kernstruktur — analog HotkeyRecorderRow (Zeilen 1002–1075)
struct ToggleHotkeyRow: View {
    let mode: Mode
    @EnvironmentObject var settings: SettingsStore
    @State private var isRecording = false
    @State private var errorMessage: String? = nil
    @StateObject private var recorder = KeyRecorderViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: mode.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(mode.title).font(.body).bold()
                    Text(mode.subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isRecording {
                    recordingField      // State C
                } else if let binding = settings.toggleHotkeyBinding(for: mode), !binding.isEmpty {
                    occupiedField(binding)  // State B
                } else {
                    emptyField          // State A
                }
            }
            // Fehler-Inline unter der Zeile (State D + E)
            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .onDisappear {
            recorder.stop()
            isRecording = false
        }
    }

    // Commit-Validierung — Kern-Pattern (RESEARCH.md Pattern ToggleHotkeyRow-Validierung)
    private func handleCommit(_ binding: HotkeyBinding?) {
        guard let b = binding, !b.isEmpty else {
            isRecording = false; return  // Escape → kein Commit
        }
        // Validierung 1: Nur Modifier ohne Buchstabe/F-Taste
        if b.isModifierOnly {
            errorMessage = "Kombination ohne Buchstaben oder Funktionstaste ist nicht erlaubt."
            isRecording = false
            clearErrorAfterDelay(); return
        }
        // Validierung 2: fn-Modifier hat kein Carbon-Äquivalent
        if b.modifiers.contains(.fn) {
            errorMessage = "fn-Taste kann nicht für freie Toggle-Hotkeys verwendet werden."
            isRecording = false
            clearErrorAfterDelay(); return
        }
        // Validierung 3: Doppelbelegung
        for other in Mode.allCases where other != mode {
            if let existing = settings.toggleHotkeyBinding(for: other), existing == b {
                errorMessage = "\(b.displayString) ist bereits für \(other.title) vergeben."
                isRecording = false
                clearErrorAfterDelay(); return
            }
        }
        settings.setToggleHotkeyBinding(b, for: mode)
        isRecording = false
        errorMessage = nil
    }

    private func clearErrorAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { errorMessage = nil }
    }
    // ... @ViewBuilder-Helpers für State A/B/C analog HotkeyRecorderRow ...
}
```

**ConflictWarningBanner** (neu — Analog: Orange-Banner-Pattern aus SprecherTab Zeilen 554–562):
```swift
// Analog: SprecherTab Warn-Banner (Zeilen 554–562)
// Patern: HStack + Image(systemName:) + Text, .orange, .padding(10/.padding(8)), .background(Color.orange.opacity(0.1))
private struct ConflictWarningBanner: View {
    let conflicts: [(Mode, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Möglicher Konflikt mit einem System-Hotkey")
                    .font(.body).bold()
            }
            ForEach(conflicts, id: \.0) { mode, systemName in
                let binding = ""   // wird aus SettingsStore geholt
                Text("\(mode.title): Möglicher Konflikt mit \(systemName). Der Hotkey funktioniert möglicherweise nicht zuverlässig.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
```

**AnpassenTab — TASTENKÜRZEL-Section ersetzen** (Zeilen 59–63, refactor):
```swift
// ALT (wird entfernt):
// section("TASTENKÜRZEL") {
//     HotkeyRecorderRow(mode: .blitztext)
//     ...
// }

// NEU — Verweis auf Hotkeys-Tab:
VStack(alignment: .leading, spacing: 4) {
    Text("TASTENKÜRZEL").font(.caption).foregroundStyle(.secondary).bold()
    Text("Hotkeys werden im Tab \"Hotkeys\" konfiguriert.")
        .font(.caption).foregroundStyle(.secondary)
}
```

---

### 4. `BlitzTextTests/Hotkeys/ToggleHotkeyTests.swift` (neu)

**Analog:** Bestehende `HotkeyStateMachineTests` (als Referenz für XCTest-Struktur; die Datei liegt in `BlitzTextTests/`).

**Test-Struktur-Pattern** (aus bestehendem Testtarget abgeleitet):
```swift
import XCTest
@testable import BlitzText

final class ToggleHotkeyTests: XCTestCase {

    var settings: SettingsStore!

    override func setUp() {
        super.setUp()
        settings = SettingsStore()
        // Toggle-Hotkeys auf nil zurücksetzen (sauber)
        settings.setToggleHotkeyBinding(nil, for: .blitztext)
        settings.setToggleHotkeyBinding(nil, for: .blitztextPlus)
        settings.setToggleHotkeyBinding(nil, for: .blitztextRant)
    }

    // SC-2: SettingsStore-Persistenz — Toggle-Binding überlebt Snapshot-Roundtrip
    func testToggleBinding_snapshotRoundtrip() { ... }

    // SC-2: Doppelbelegung — Validierungslogik
    func testDuplicateBinding_rejected() { ... }

    // SC-2: fn-Modifier — wird abgelehnt
    func testFnModifier_rejected() { ... }

    // SC-2: Nur-Modifier — wird abgelehnt
    func testModifierOnly_rejected() { ... }

    // SC-4: Conflict-Detection — bekannte Kombo triggert conflictingModes
    func testConflict_spotlightDetected() { ... }
}
```

---

## Shared Patterns

### Auto-Save via Combine-Debounce
**Source:** `BlitzText/Settings/SettingsStore.swift`, Zeilen 95–98
**Gilt für:** SettingsStore-Erweiterung (alle neuen `@Published` Properties)
```swift
objectWillChange
    .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
    .sink { [weak self] _ in self?.save() }
    .store(in: &cancellables)
```
**Konsequenz:** `setToggleHotkeyBinding()` ruft KEIN `save()` manuell auf — im Gegensatz zu `setHotkeyBinding()` (Zeile 137), das ein manuelles `save()` hat. Dieses Inkonsistenz-Pattern aus dem Bestand beibehalten — NICHT in der Phase ändern.

### Section-Header-Pattern
**Source:** `BlitzText/Settings/SettingsView.swift`, Zeilen 182–187 (AnpassenTab.section()) sowie Inline in LokalTab (Zeile 363)
**Gilt für:** HotkeysTab — alle Sections
```swift
VStack(alignment: .leading, spacing: 8) {
    Text("SECTION-NAME").font(.caption).foregroundStyle(.secondary).bold()
    // content
}
```

### Orange Warn-Banner-Pattern
**Source:** `BlitzText/Settings/SettingsView.swift`, Zeilen 554–562 (SprecherTab)
**Gilt für:** `ConflictWarningBanner`
```swift
HStack(spacing: 8) {
    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    Text("Warn-Text").font(.caption).foregroundStyle(.orange)
}
.padding(10)
.background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
```

### Recorder-Feld (aktiv) — accentColor-Pattern
**Source:** `BlitzText/Settings/SettingsView.swift`, Zeilen 1046–1053 (HotkeyRecorderRow.recordingField)
**Gilt für:** `ToggleHotkeyRow` State C (Recorder aktiv)
```swift
Text(recorder.liveDisplay)
    .font(.system(.body, design: .monospaced))
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .frame(minWidth: 160, alignment: .leading)
    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1))
```

### @unchecked Sendable + DispatchQueue.main.async für C-Callbacks
**Source:** `BlitzText/Hotkeys/HotkeyManager.swift`, Zeilen 9 und 193–196
**Gilt für:** HotkeyManager — neuer Toggle-Layer erbt dieses Pattern
```swift
final class HotkeyManager: @unchecked Sendable {
    // ...
    DispatchQueue.main.async { trigger(mode, .toggle) }
}
```

### KeyRecorderViewModel (wiederverwendet, nicht neu erstellt)
**Source:** `BlitzText/Settings/SettingsView.swift`, Zeilen 926–998
**Gilt für:** `ToggleHotkeyRow` — `@StateObject private var recorder = KeyRecorderViewModel()`
Vollständig wiederverwendbar ohne Änderungen. `start(onCommit:)` liefert `HotkeyBinding?` — Escape = `nil`, gültige Kombo = binding.

---

## No Analog Found

Alle Dateien haben enge Analoge im Bestand. Keine Datei ohne Match.

| Datei | Bemerkung |
|-------|-----------|
| `KeyboardShortcuts`-SPM-Integration in `project.yml` | Kein Code-Analog — folgt RESEARCH.md Pattern (yaml-Block) |
| `HotkeyModifier.carbonModifierFlag`-Extension | Neues API-Mapping — Carbon-Konstanten aus `Carbon/Events.h`; RESEARCH.md Pattern 2 als Referenz |

---

## Kritische Pitfalls (aus RESEARCH.md — für Planner)

| # | Pitfall | Prävention |
|---|---------|------------|
| P1 | KeyboardShortcuts-interne UserDefaults-Keys kollidieren mit SettingsStore | Beim App-Start immer SettingsStore als Source-of-Truth, `KeyboardShortcuts.setShortcut(_:for:)` zum Synchronisieren aufrufen |
| P2 | `cancellables` in HotkeyManager fehlt → Binding-Änderungen werden nicht re-registriert | `private var cancellables = Set<AnyCancellable>()` als neue Property, `.store(in: &cancellables)` |
| P3 | fn-Modifier in Carbon-Konvertierung führt zu lautlosem Fehler (⌘B statt fn+⌘B) | Guard in `registerToggleHotkey()` + Guard in `ToggleHotkeyRow.handleCommit()` |
| P4 | Doppelte Registration bei zweitem `start()`-Aufruf | `toggleHotkeysActive: Bool`-Guard (Pattern analog zu `guard eventTap == nil` in `installEventTap()`) |
| P5 | Swift-6-Concurrency: Combine-Sink auf Background-Thread | `.receive(on: RunLoop.main)` vor `.sink {}` |

---

## Metadata

**Analog-Suchbereich:** `BlitzText/Hotkeys/`, `BlitzText/Settings/`, `BlitzText/Modes/`, `BlitzTextTests/`
**Gescannte Dateien:** 5 Quelldateien vollständig gelesen
**Pattern-Extraction-Datum:** 2026-05-19
