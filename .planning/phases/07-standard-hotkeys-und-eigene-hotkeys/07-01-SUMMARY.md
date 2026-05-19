# 07-01 SUMMARY: A3-Spike keyCode-Aequivalenz

**Status:** DONE
**Wave:** 0
**Datum:** 2026-05-19
**Dauer:** ca. 15 min

## Was wurde getan

Wave-0-Spike zur Verifikation von Assumption A3: Eine swiftc-Probe (`/tmp/a3_spike/KeyCodeProbe.swift`) verglich 19 `kVK_ANSI_*`-Werte aus `HIToolbox/Events.h` (MacOSX26.5.sdk) mit den erwarteten keyCode-Werten fuer Buchstaben, Ziffern, Sondertasten (Space, Return, Escape, Delete, Tab), F1-F20 und Numpad-Tasten. Ergebnisse wurden in `07-RESEARCH.md` dokumentiert.

## Ergebnis

**A3 VERIFIZIERT:** CGEvent-keyCodes (`kVK_ANSI_*`) und Carbon-keyCodes sind fuer alle 19 getesteten Standard-Tasten auf Apple-Silicon identisch — 19/19 Match.

Konkrete Werte (Auswahl):
- `kVK_ANSI_A = 0x00`, `kVK_ANSI_B = 0x0B`, `kVK_ANSI_Z = 0x06`
- `kVK_Space = 0x31`, `kVK_Return = 0x24`, `kVK_Escape = 0x35`, `kVK_Delete = 0x33`, `kVK_Tab = 0x30`
- `kVK_F1 = 0x7A`, `kVK_F12 = 0x6F`, `kVK_F13 = 0x69`, `kVK_F20 = 0x5A`
- `kVK_ANSI_Keypad0 = 0x52`, `kVK_ANSI_KeypadEnter = 0x4C`

Bekannte Nicht-ANSI-Ausnahmen (fuer Toggle-Hotkey-Use-Case irrelevant):
- `kVK_ISO_Section = 0x0A` (ISO-Tastatur, Taste links von Z)
- `kVK_JIS_*` (Japan-spezifisch)

## Impact auf Plan 07-03

**Keine Lookup-Table noetig.**

`registerToggleHotkey(_:for:)` in Plan 07-03 kann `UInt32(binding.keyCode)` direkt als `carbonKeyCode`-Argument verwenden:

```swift
let shortcut = KeyboardShortcuts.Shortcut(
    carbonKeyCode: UInt32(binding.keyCode),   // direkt — keine Konvertierung noetig
    carbonModifiers: UInt32(carbonMods)
)
```

Plan 07-03 kann ohne Einschraenkung implementiert werden.

## Deviationen vom Plan

Keine — Plan exakt wie beschrieben ausgefuehrt.

**Hinweis:** Die erste Probe-Variante mit `import Carbon` verursachte einen Segfault (Carbon/HIToolbox braucht laufenden macOS Event-Loop), daher wurde auf direkte Konstanten-Definitionen aus den Header-Werten umgestellt. Das Ergebnis ist aequivalent und robuster.

## Commits

- `9c9877d` docs(07-01): A3 verified — CGEvent/Carbon keyCodes identisch fuer Standard-Tasten
