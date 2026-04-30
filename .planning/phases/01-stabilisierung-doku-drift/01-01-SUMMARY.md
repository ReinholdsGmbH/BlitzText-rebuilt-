---
phase: 01-stabilisierung-doku-drift
plan: 01
subsystem: settings
tags: [keychain, security, migration, stab-01]
requirements_completed: [STAB-01]
dependency_graph:
  requires:
    - BlitzText/Settings/Keychain.swift (Keychain.shared.read/write/delete)
    - BlitzText/App/Log.swift (Log.write)
  provides:
    - Keychain-backed apiKey property in SettingsStore
    - Idempotente UserDefaults→Keychain Migration
  affects:
    - WhisperAPIClient (transparent — synchroner Getter unverändert)
    - OpenAIChatClient (transparent)
    - SettingsView (Hilfetext aktualisiert)
tech_stack:
  added: []
  patterns:
    - On-Device Secret Storage via macOS Keychain (kSecClassGenericPassword, kSecAttrAccessibleWhenUnlocked)
    - Einmalige, idempotente, fail-safe Datenmigration im init()
key_files:
  created: []
  modified:
    - BlitzText/Settings/SettingsStore.swift (+28 / -9)
    - BlitzText/Settings/SettingsView.swift (+1 / -1)
decisions:
  - apiKey bleibt synchroner String-Getter/Setter (kein async, kein throws) — sonst hätten WhisperAPIClient + OpenAIChatClient angefasst werden müssen
  - Migration im init() nach load(), VOR objectWillChange-Sink — sonst hätte das Entfernen des Legacy-UserDefaults-Eintrags einen unnötigen save() ausgelöst
  - Bei Keychain-Write-Fehler bleibt der Legacy-Eintrag erhalten (Datenverlust > Hygiene)
metrics:
  duration: ~5 min
  completed: 2026-04-30
  commits: 2
  tasks_completed: 2
  files_modified: 2
---

# Phase 1 Plan 01: Keychain-Migration des OpenAI-API-Keys — Zusammenfassung

Verschiebt den einzigen Klartext-geheimen Wert der App (OpenAI-API-Key) von UserDefaults in die macOS-Keychain und migriert vorhandene Werte einmalig + idempotent — ohne Aufrufer-Code anzufassen.

## Was geändert wurde

### `BlitzText/Settings/SettingsStore.swift` (+28 / −9)

- **Doc-Kommentar** über `apiKey` umgeschrieben: erklärt jetzt Keychain-Service/Account und das Sendable-sichere blockierende Read/Write.
- **`apiKey`-Computed-Property** liest jetzt über `Keychain.shared.read(account:)` und schreibt/löscht über `Keychain.shared.write(value:account:)` bzw. `delete(account:)`. Setter ruft weiter `objectWillChange.send()` auf, damit der Debounce-Sink nicht stört (Keychain ist Source of Truth, nicht UserDefaults — kein `save()` nötig).
- **Konstanten umbenannt:** `apiKeyDefaultsKey` → `apiKeyLegacyDefaultsKey` (nur noch Migration). Ergänzt: `apiKeyKeychainAccount = "openai-api-key"`.
- **`migrateAPIKeyFromUserDefaultsIfNeeded()`** neu: liest Legacy-Wert aus UserDefaults, schreibt ihn in die Keychain (nur falls dort noch nichts liegt), entfernt anschließend den UserDefaults-Eintrag. Bei Keychain-Write-Fehler bleibt der Legacy-Eintrag erhalten — `Log.write` protokolliert beide Pfade (Erfolg / Fehlschlag).
- **`init()` Reihenfolge:** `load()` → `migrateAPIKeyFromUserDefaultsIfNeeded()` → Combine-Sink. Reihenfolge bewusst: Migration vor dem Sink verhindert einen sinnlosen Auto-Save-Trigger durch `defaults.removeObject`.

### `BlitzText/Settings/SettingsView.swift` (+1 / −1)

- Hilfetext unter dem API-Key-Eingabefeld (Zeile 245) ersetzt: nennt jetzt den macOS-Schlüsselbund (Service `de.reinholds.blitztext`, Account `openai-api-key`) und weist auf den einmaligen Schlüsselbund-Prompt mit „Immer erlauben“ hin. Kein UserDefaults-Wording mehr.

## Verifikation

### Automatisierte Checks

| Check | Befehl | Ergebnis |
| --- | --- | --- |
| Build (Task 1) | `xcodegen generate && xcodebuild -project BlitzText.xcodeproj -scheme BlitzText -configuration Debug -destination 'platform=macOS' build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` | `** BUILD SUCCEEDED **` |
| Build (nach Task 2) | dito | `** BUILD SUCCEEDED **` |
| Hilfetext-Grep (Task 2) | `grep -c "macOS-Schlüsselbund" BlitzText/Settings/SettingsView.swift` | `1` |
| Alttext entfernt (Task 2) | `grep -q "User-Defaults unter.*plist" …` | `OLD GONE` (Exit ≠ 0) |
| UserDefaults-Aufrufe nur in Migration | `grep -nE "defaults\.(string\|removeObject).*apiKey" SettingsStore.swift` | 2 Treffer, beide in `migrateAPIKeyFromUserDefaultsIfNeeded` (Zeilen 63, 74) |
| Keychain-Aufrufe (Plan-Forderung ≥5) | `grep -nE "Keychain\.shared\.(read\|write\|delete).*apiKeyKeychainAccount" SettingsStore.swift` | 5 Treffer (Getter read; Setter delete + write; Migration read + write) |

### Manueller Sanity-Check (offen — siehe Folge-Todos)

Der Plan listet zusätzlich einen UI-Roundtrip (Settings öffnen, Dummy-Key speichern, Schlüsselbund.app prüfen, `defaults read … apiKey` muss „does not exist“ liefern). Dieser Schritt erfordert eine laufende interaktive macOS-Session und einen Schlüsselbund-Prompt — für die automatisierte Plan-Verifikation nicht durchgeführt. Empfehlung: in der Phase-1-Gesamt-Verifikation oder beim ersten manuellen Smoke-Test der nachfolgenden Plans abhaken.

## Commits

1. `ffeef69` — `feat(stab-01): API-Key in macOS-Keychain umziehen` (SettingsStore.swift)
2. `f0a7a08` — `docs(stab-01): SettingsView-Hilfetext auf Schlüsselbund anpassen` (SettingsView.swift)

## Deviations vom Plan

Keine. Plan wurde 1:1 umgesetzt.

## Bekannte Einschränkungen / Footguns

- **Self-Signed-Rebuild-Prompt:** Beim Wechsel der Code-Signing-Identity (z. B. spontaner `clean build` ohne stabile `BlitzText Local Dev`-Identity) wird die Keychain-ACL ungültig und der Schlüsselbund prompted erneut. Workaround: stabile Self-Signed-Identity via `Scripts/create-signing-cert.sh` einrichten und dort registriert lassen. Nicht-blockierend, dokumentiert in `Keychain.swift`.
- **Migrations-Test im Live-Profil:** Die idempotente Migration ist code-strukturell verifiziert (beide Pfade — read==nil schreibt, read!=nil überspringt — sind exakt dem Plan-Snippet entsprechend), aber nicht durch einen End-to-End-Run mit präpariertem UserDefaults-Plist abgedeckt. Bei Bedarf reproduzierbar durch `defaults write de.reinholds.blitztext de.reinholds.blitztext.apiKey "sk-legacy-123"` vor App-Start.

## Folge-Todos für STATE.md

- STAB-01 als „done“ markieren (Orchestrator).
- Optional: in Phase-1-Gesamt-Verifikation den manuellen Schlüsselbund-Roundtrip-Test einplanen.
- Kein neuer Blocker entstanden.

## Self-Check: PASSED

- [x] `BlitzText/Settings/SettingsStore.swift` existiert und enthält `Keychain.shared.read` (Zeile 30).
- [x] `BlitzText/Settings/SettingsView.swift` existiert und enthält „macOS-Schlüsselbund“ (1 Treffer).
- [x] Commit `ffeef69` vorhanden (`git log --oneline | grep ffeef69`).
- [x] Commit `f0a7a08` vorhanden.
- [x] Build grün nach beiden Commits.
