# 07-02 SUMMARY: SPM-Dependency + SettingsStore Toggle-Hotkeys

**Status:** DONE
**Wave:** 1
**Datum:** 2026-05-19

## Was wurde getan

KeyboardShortcuts 2.4.0 (sindresorhus/KeyboardShortcuts) als SPM-Package in project.yml eingetragen, via xcodegen generate in das Xcode-Projekt übernommen und erfolgreich aufgelöst. Zusätzlich wurde SettingsStore.swift additiv um drei Toggle-Hotkey @Published-Properties, Snapshot-Felder, load/save-Logik und Accessor-Methoden erweitert — ohne bestehenden Code zu verändern.

## Artefakte

- `project.yml`: KeyboardShortcuts 2.4.0 unter `packages:` und BlitzText-Target-`dependencies:` eingetragen
- `BlitzText.xcodeproj/project.pbxproj`: via xcodegen generate aktualisiert
- `BlitzText.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: KeyboardShortcuts @ 2.4.0 eingetragen
- `BlitzText/Settings/SettingsStore.swift`: 3 @Published Toggle-Hotkey-Properties + Snapshot-Erweiterung + load/save + Accessor-Methoden

## Build-Status

xcodebuild build exit 0: **ja**

## Verifikation

- `grep -c "KeyboardShortcuts" project.yml` → 4 (>= 2 gefordert)
- `grep -c "toggleHotkeyForBlitztext" SettingsStore.swift` → 18 (>= 6 gefordert)
- `xcodebuild -resolvePackageDependencies -scheme BlitzText` → KeyboardShortcuts @ 2.4.0 erfolgreich aufgelöst
- Snapshot-Struct: `var toggleHotkeyForBlitztext: HotkeyBinding? = nil` (Zeile 207)
- load(): `toggleHotkeyForBlitztext = snap.toggleHotkeyForBlitztext ?? nil` (Zeile 239)
- setToggleHotkeyBinding: kein manuelles save() — Combine-Debounce-Konvention eingehalten

## Commits

- 262b1e8 feat(07-02): KeyboardShortcuts 2.4.0 als SPM-Dependency in project.yml
- 2222c8a feat(07-02): SettingsStore — 3 Toggle-Hotkey-Properties + Snapshot + Accessoren

## Deviations

Keine — Plan exakt wie beschrieben ausgeführt. Acceptance Criteria "grep -c toggleHotkeyBinding >= 2" ist im Plan leicht falsch formuliert (Setter heißt setToggleHotkeyBinding mit großem T), aber beide Methoden existieren korrekt. Funktionale Anforderung vollständig erfüllt.

## Known Stubs

Keine — SettingsStore-Erweiterung ist vollständig funktional.

## Threat Flags

Keine neuen sicherheitsrelevanten Surfaces eingeführt. SettingsStore speichert Toggle-Hotkey-Bindings in UserDefaults als JSON — kein Keychain-Zugriff, keine Netzwerk-Requests.
