# 07-03 SUMMARY: HotkeyManager — Toggle-Layer

**Status:** DONE
**Wave:** 2

## Was wurde getan

HotkeyManager.swift wurde additiv um einen zweiten Hotkey-Pfad via Carbon/KeyboardShortcuts erweitert. Der bestehende CGEventTap-Pfad (Hold-Mode, fn+Modifier) blieb vollständig unverändert.

Konkret hinzugefügt:
- Imports: `Carbon.HIToolbox`, `Combine`, `KeyboardShortcuts`
- `HotkeyModifier.carbonModifierFlag`-Extension (fn→0, cmd/shift/opt/ctrl→Carbon-Int-Flags)
- `KeyboardShortcuts.Name`-Extension: `toggleBlitztext`, `toggleBlitztextPlus`, `toggleBlitztextRant`
- `HotkeyBinding: Hashable`-Conformance (benötigt von HotkeysTab-knownConflicts, pre-existing Fehler)
- Neue Properties: `cancellables: Set<AnyCancellable>` und `toggleHotkeysActive: Bool`
- Private Methoden: `setupToggleHotkeys()`, `teardownToggleHotkeys()`, `reloadToggleHotkeys()`, `registerToggleHotkey(_:for:)`, `toggleName(for:)`
- `start()` ruft `setupToggleHotkeys()` nach `installEventTap()` auf
- `stop()` ruft `teardownToggleHotkeys()` am Ende auf

## Build-Status

xcodebuild build exit 0: **ja**

## CGEventTap unverändert

Bestätigt: `installEventTap()`, `handleFlagsChanged()`, `handleKeyDown()`, `handleKeyUp()` und `handleTapDisabled`-Logik wurden nicht modifiziert. Alle Änderungen sind additiv.

## Deviationen

1. **[Rule 1 - Bug] HotkeyBinding: Hashable-Conformance ergänzt**
   - Gefunden: Pre-existing Compile-Fehler in SettingsView.swift (HotkeyBinding als Dictionary-Key in HotkeysTab.knownConflicts)
   - Fix: `Hashable` zu `struct HotkeyBinding: Codable, Equatable, Hashable, Sendable` hinzugefügt
   - Synthesized Hashable ist korrekt (alle Properties Hashable: Set<HotkeyModifier>, UInt16?, String?)
   - Datei: `BlitzText/Hotkeys/HotkeyManager.swift`
   - Commit: bcca20c

2. **API-Anpassung: carbonModifierFlag als `Int` statt `UInt32`**
   - KeyboardShortcuts.Shortcut(carbonKeyCode:carbonModifiers:) erwartet `Int`, nicht `UInt32`
   - Angepasst: `var carbonModifierFlag: Int` (statt `UInt32` wie im Plan-Template)
   - `reduce(0) { $0 | $1.carbonModifierFlag }` liefert `Int` — passend für API

## Commits

- `bcca20c` feat(07-03): HotkeyModifier.carbonModifierFlag + KeyboardShortcuts.Name-Extensions
- `8ee6ac4` feat(07-03): HotkeyManager — additiver Toggle-Layer via Carbon/KeyboardShortcuts

## Self-Check

- [x] `grep -c "setupToggleHotkeys" HotkeyManager.swift` = 3 (>= 3)
- [x] `grep -c "teardownToggleHotkeys" HotkeyManager.swift` = 3 (>= 3)
- [x] `grep "toggleHotkeysActive"` = Property + guard + true + false
- [x] `grep "cancellables"` = Property-Deklaration + store(in:) + removeAll()
- [x] `grep "guard !binding.modifiers.contains(.fn)"` = 1 Treffer
- [x] CGEventTap-Code unverändert
- [x] xcodebuild build exit 0
