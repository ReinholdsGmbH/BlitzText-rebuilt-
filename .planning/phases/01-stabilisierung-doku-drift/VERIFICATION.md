---
phase: 01-stabilisierung-doku-drift
verified: 2026-04-30T00:00:00Z
status: human_needed
score: 4/4 must-haves code-verified (3 manuelle UAT-Items offen)
overrides_applied: 0
human_verification:
  - test: "Schlüsselbund-Roundtrip (STAB-01)"
    expected: "Nach Speichern eines Dummy-Keys 'sk-test123' in Settings → Schlüsselbund.app zeigt Eintrag Service=de.reinholds.blitztext / Account=openai-api-key. `defaults read de.reinholds.blitztext de.reinholds.blitztext.apiKey` gibt 'does not exist' zurück."
    why_human: "Erfordert interaktive macOS-Session + Schlüsselbund-Prompt-Bestätigung; nicht headless reproduzierbar."
  - test: "Legacy-UserDefaults-Migration End-to-End (STAB-01)"
    expected: "Mit `defaults write de.reinholds.blitztext de.reinholds.blitztext.apiKey 'sk-legacy-123'` einen Legacy-Wert setzen, App starten, danach Schlüsselbund-Eintrag vorhanden + `defaults read … apiKey` → 'does not exist'."
    why_human: "Setzt Live-Schlüsselbund-Zugriff voraus; Code-Pfad ist statisch verifiziert, aber realer Migration-Roundtrip erfordert UI-Session."
  - test: "Accessibility-Permission Auto-Recovery (STAB-03)"
    expected: "Bei deaktivierter Accessibility-Permission App starten (Log: '… 1 Hz Polling'), Permission in Systemeinstellungen aktivieren, innerhalb 1–2 s ohne App-Restart Log-Einträge 'Accessibility erteilt — Tap wird gestartet.' und 'CGEventTap aktiv'. fn+Shift halten startet Aufnahme."
    why_human: "TCC-Permission-Toggle benötigt Touch-ID + GUI; CGEventTap-Verhalten kann nur live geprüft werden."
---

# Phase 1: Stabilisierung & Doku-Drift — Verification Report

**Phase Goal:** STAB-01..STAB-04 schließen — Keychain-Migration, Hotkey-Debounce-Konsistenz, Accessibility-Auto-Recovery, LocalWhisperClient-Doku-Drift.
**Verifiziert:** 2026-04-30
**Status:** human_needed (alle Code-Truths verified; 3 Live-UAT-Items offen)

## Must-Have-Verifikation pro Requirement

### STAB-01 — API-Key in Keychain ✓ VERIFIED (Code) / ⚠ UAT offen

| Truth | Status | Evidence |
| --- | --- | --- |
| Keychain-backed `apiKey`-Property | ✓ | `SettingsStore.swift:29-39` — Getter `Keychain.shared.read(account: …)`, Setter delete/write |
| Synchroner Getter/Setter erhalten | ✓ | Property bleibt `var apiKey: String { get … set … }`, kein async/throws (SettingsStore.swift:29) |
| Migration `migrateAPIKeyFromUserDefaultsIfNeeded` idempotent | ✓ | `SettingsStore.swift:61-75`. Aufruf in `init()` Zeile 50, vor objectWillChange-Sink (Zeile 52). Guard `legacy.isEmpty` → No-Op; nur schreiben wenn Keychain leer; bei Write-Fail `return` vor `removeObject` |
| Datenverlust-Schutz bei Keychain-Fail | ✓ | `SettingsStore.swift:69-72` — Log + return, Legacy-UserDefaults bleibt erhalten |
| UI-Hilfetext: macOS-Schlüsselbund | ✓ | `SettingsView.swift:245` — „Der Schlüssel liegt in deinem macOS-Schlüsselbund (Service `de.reinholds.blitztext`, Account `openai-api-key`)…" |
| Konstanten umbenannt | ✓ | `apiKeyLegacyDefaultsKey` (Zeile 40), `apiKeyKeychainAccount = "openai-api-key"` (Zeile 41) |

**Manuell offen:** Schlüsselbund.app-Eintrag-Inspektion und Live-Migration-Roundtrip.

### STAB-02 — Hotkey-Debounce konsistent ✓ VERIFIED

| Truth | Status | Evidence |
| --- | --- | --- |
| Benannte Konstanten statt Magic Numbers | ✓ | `HotkeyManager.swift:115` `holdDebounce: TimeInterval = 0.05`; `:119` `toggleDebounce: TimeInterval = 0.30` |
| Deutscher Doc-Comment mit Begründung | ✓ | `HotkeyManager.swift:111-114` (Hold) / `:117-118` (Toggle) — Rationale auf CGEvent-Doppelfeuer / Doppeltipp |
| Self.holdDebounce / Self.toggleDebounce in Call-Sites | ✓ | `:150` Hold-Branch, `:167` Toggle-Branch — keine Magic Numbers mehr |
| ARCHITECTURE.md exakt 50 ms / 300 ms | ✓ | Zeile 208 „debounce (50 ms hold, 300 ms toggle)" + Zeile 209 „Debounce-Rationale" |
| Keine `250 ms`-Reste | ✓ | `grep -nE "250\s*ms\|250ms\|0\.25\s*s"` → 0 Treffer |
| Refresh-Marker auf 2026-04-30 | ✓ | ARCHITECTURE.md Zeile 1 |

### STAB-03 — Accessibility Auto-Recovery ✓ VERIFIED (Code) / ⚠ UAT offen

| Truth | Status | Evidence |
| --- | --- | --- |
| `installEventTap()` extrahiert + idempotent | ✓ | `HotkeyManager.swift:56-90`, Guard `eventTap == nil` Zeile 57 |
| `startPermissionWatcher()` 1 Hz DispatchSourceTimer | ✓ | `HotkeyManager.swift:92-107` — `DispatchSource.makeTimerSource(queue: .main)`, `repeating: 1.0` |
| Watcher prompt-frei (`AXIsProcessTrusted()` ohne Options) | ✓ | `:98` — `if AXIsProcessTrusted()` ohne Options-Dictionary |
| Selbstabschaltung des Watchers | ✓ | `:100-101` — `cancel()` + `permissionTimer = nil` vor `installEventTap()` |
| `start()` verzweigt an AXIsProcessTrusted | ✓ | `:32-41` |
| `stop()` räumt Timer auf | ✓ | `:44-45` `permissionTimer?.cancel(); permissionTimer = nil` |
| SettingsView ohne Restart-Hinweis | ✓ | `:209` „… kein App-Neustart nötig"; alter String „einmal beenden und neu starten" entfernt |
| Keychain.swift-Header verlinkt auf BlitzText Local Dev Cert | ✓ | `Keychain.swift:7` |
| Datei-Header HotkeyManager dokumentiert 1-Hz-Polling | ✓ | `:6-8` |

**Manuell offen:** Real-TCC-Toggle + Live-Tap-Recovery.

### STAB-04 — LocalWhisperClient-Doku-Drift ✓ VERIFIED

| Truth | Status | Evidence |
| --- | --- | --- |
| RISKS.md kein „Stub"/„whisper.cpp"-Wording | ✓ | Zeile 30 jetzt „Lokales Whisper läuft über WhisperKit/CoreML"; Cold-Start als verbleibendes Risiko benannt |
| ARCHITECTURE.md kein Stub/Placeholder/TODO im Whisper-Kontext | ✓ | `grep -rEi "Local.*Whisper.*(stub\|placeholder\|TODO\|whisper\.cpp\|fake\|mock\|dummy)"` über RISKS.md + ARCHITECTURE.md → leer (exit 1) |
| Doku konsistent mit Code | ✓ | RISKS.md verlinkt explizit auf `BlitzText/Transcription/LocalWhisperClient.swift` (WhisperKit-Implementierung mit `warmUp`, `ensureLoaded`, `transcribe`) |

## Build-Verifikation

| Befehl | Ergebnis |
| --- | --- |
| `xcodegen generate` | ✓ Created project at BlitzText.xcodeproj |
| `xcodebuild -project BlitzText.xcodeproj -scheme BlitzText -configuration Debug -destination 'platform=macOS' build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` | ✓ `** BUILD SUCCEEDED **` |
| Warnungen | 1 erwartete Warnung („BlitzText isn't code signed but requires entitlements") — nur durch `CODE_SIGN_IDENTITY=""` im Verification-Build, nicht relevant für Phase-Goal |

## Anti-Pattern-Scan

- `grep -E "TODO|FIXME|XXX|HACK|PLACEHOLDER"` auf SettingsStore/HotkeyManager/SettingsView → keine relevanten Treffer im modifizierten Code.
- Keine empty implementations / stub-returns in den Phase-1-Files.

## Requirements Coverage

| Requirement | Status | Evidence |
| --- | --- | --- |
| STAB-01 | ✓ SATISFIED (Code) — UAT pending | Keychain-Code + Migration im Code, Live-Roundtrip offen |
| STAB-02 | ✓ SATISFIED | Konstanten + Doku konsistent |
| STAB-03 | ✓ SATISFIED (Code) — UAT pending | Watcher + idempotente Tap-Installation, Live-Recovery offen |
| STAB-04 | ✓ SATISFIED | Doku-Drift entfernt |

Keine ORPHANED Requirements für Phase 1.

## Human Verification Required

### 1. Schlüsselbund-Roundtrip (STAB-01)

**Test:**
1. App starten, Settings → API-Key „sk-test123" eingeben + Tab/Enter zum Speichern.
2. Schlüsselbund.app öffnen → Suche „de.reinholds.blitztext" → Eintrag mit Account „openai-api-key" muss existieren.
3. Terminal: `defaults read de.reinholds.blitztext de.reinholds.blitztext.apiKey` → erwartete Ausgabe: „does not exist".

### 2. Legacy-UserDefaults-Migration (STAB-01)

**Test:**
1. App beenden. `defaults write de.reinholds.blitztext de.reinholds.blitztext.apiKey "sk-legacy-123"` setzen.
2. App starten. Log enthält „SettingsStore: API-Key von UserDefaults nach Keychain migriert".
3. Schlüsselbund hat den Eintrag, `defaults read …` liefert „does not exist".

### 3. Accessibility-Permission Auto-Recovery (STAB-03)

**Test:**
1. Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → BlitzText-Eintrag entfernen. App vorher beenden.
2. App starten → Log: `AXIsProcessTrusted = false` und `Accessibility fehlt — Hotkeys aus, beobachte TCC-Status (1 Hz Polling).`
3. Permission in Systemeinstellungen aktivieren (Toggle + Touch-ID).
4. Innerhalb 1–2 s im Log **ohne App-Restart**: `Accessibility erteilt — Tap wird gestartet.` + `CGEventTap aktiv …`.
5. fn+Shift halten → Aufnahme startet.

## Gesamt-Verdikt

**Phase 1 Code-Implementation: PASS** — alle vier Requirements (STAB-01..STAB-04) sind im Codebase vollständig + korrekt implementiert, Build grün, keine Doku-Drift mehr.

**Status `human_needed`:** Drei UAT-Items (Schlüsselbund-Inspektion, Migrations-Roundtrip, Permission-Auto-Recovery) erfordern eine interaktive macOS-Session und können nicht headless verifiziert werden. Diese sind keine Blocker für die Phase-Definition (Code-Truths sind alle erfüllt), müssen aber vom User bestätigt werden, bevor STAB-01/STAB-03 als end-to-end „done" markiert werden.

Keine Blocker. Keine Regressionen. Bereit für Phase 2 (Test-Fundament), nachdem die UAT-Items abgehakt sind.

---

_Verifiziert: 2026-04-30 — Claude (gsd-verifier)_
