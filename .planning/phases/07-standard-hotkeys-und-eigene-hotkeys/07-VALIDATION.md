---
phase: 7
slug: standard-hotkeys-und-eigene-hotkeys
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-19
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode 26.5) |
| **Config file** | `project.yml` (BlitzTextTests-Target bereits vorhanden) |
| **Quick run command** | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/HotkeyStateMachineTests -only-testing:BlitzTextTests/ToggleHotkeyTests 2>&1 \| grep -E "(passed|failed|error)"` |
| **Full suite command** | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' 2>&1 \| tail -20` |
| **Estimated runtime** | ~15 seconds (quick) / ~30 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run Quick-Run-Command (HotkeyStateMachineTests + ToggleHotkeyTests)
- **After every plan wave:** Run Full Suite
- **Before `/gsd:verify-work`:** Full suite grün (Ausnahme: bestehender `SpeakerMatchingTests`-Fehler ist Phase-4-Scope, nicht Phase-7)
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 07-01 | 0 | SC-2 (A3) | — | N/A | spike/grep | `grep -n "A3 verified\|A3 korrigiert" .planning/phases/07-standard-hotkeys-und-eigene-hotkeys/07-RESEARCH.md` | ✅ | ⬜ pending |
| 07-02-01 | 07-02 | 1 | SC-2 | — | N/A | build | `grep -c "KeyboardShortcuts" BlitzText.xcodeproj/project.pbxproj \|\| grep -c "KeyboardShortcuts" project.yml` | ✅ | ⬜ pending |
| 07-02-02 | 07-02 | 1 | SC-2 | T-07-02: UserDefaults-Injection | Snapshot-Decode mit nil-Fallback bei ungültigem HotkeyBinding | unit | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/ToggleHotkeyTests 2>&1 \| grep -E "(passed\|failed)"` | ❌ W0 | ⬜ pending |
| 07-03-01 | 07-03 | 2 | SC-1, SC-2 | T-07-03: Doppelfeuer durch Re-Registrierung | Idempotenz-Guard verhindert Doppelregistrierung | unit | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/HotkeyStateMachineTests -only-testing:BlitzTextTests/ToggleHotkeyTests 2>&1 \| grep -E "(passed\|failed)"` | ❌ W0 | ⬜ pending |
| 07-03-02 | 07-03 | 2 | SC-1, SC-2 | T-07-03: Doppelfeuer | teardown/reload-Zyklus korrekt | unit | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/ToggleHotkeyTests 2>&1 \| grep -E "(passed\|failed)"` | ❌ W0 | ⬜ pending |
| 07-04-01 | 07-04 | 2 | SC-3 | — | N/A | build | `xcodebuild build -scheme BlitzText -destination 'platform=macOS' 2>&1 \| grep -E "(error:\|BUILD SUCCEEDED)"` | ✅ | ⬜ pending |
| 07-04-02 | 07-04 | 2 | SC-3, SC-4 | T-07-05: fn-Modifier in Toggle-Binding | fn-Modifier-Validierung vor SettingsStore-Write | unit | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/ToggleHotkeyTests 2>&1 \| grep -E "(passed\|failed)"` | ❌ W0 | ⬜ pending |
| 07-05-01 | 07-05 | 3 | SC-1–SC-4 | alle | alle Phase-7-Sicherheitsverhaltensweisen | unit | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' -only-testing:BlitzTextTests/HotkeyStateMachineTests -only-testing:BlitzTextTests/ToggleHotkeyTests 2>&1 \| grep -E "Test Suite.*passed"` | ❌ W0 | ⬜ pending |
| 07-05-02 | 07-05 | 3 | SC-1–SC-4 | — | N/A | integration | `xcodebuild test -scheme BlitzText -destination 'platform=macOS' 2>&1 \| grep -E "Test Suite.*passed\|error:"` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `BlitzTextTests/Hotkeys/ToggleHotkeyTests.swift` — deckt SC-2 (Doppelbelegung, fn-Check, nur-Modifier-Check, SettingsStore-Roundtrip) und SC-4 (ConflictWarningBanner-Visibility-Logik)

*Keine neuen Fixtures oder Test-Framework-Installation nötig — bestehende `SettingsStore()`-Initialisierung reicht. Datei wird in Plan 07-05 angelegt.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Toggle-Hotkey ⌘⇧B löst Blitztext-Toggle aus | SC-2 | Carbon `RegisterEventHotKey` nicht unit-testbar ohne laufende App | 1. App starten. 2. In Hotkeys-Tab ⌘⇧B für Blitztext-Toggle belegen. 3. ⌘⇧B drücken → HUD erscheint (Toggle-Recording startet). |
| Hold-Pfad fn+Shift funktioniert nach Phase-7-Änderungen unverändert | SC-1 | CGEventTap-Verhalten braucht laufende App | 1. App starten. 2. fn+Shift gedrückt halten → HUD erscheint. 3. Loslassen → Aufnahme stoppt. Kein Double-Fire. |
| ConflictWarningBanner erscheint bei ⌘Space | SC-4 | UI-Zustand nicht unit-testbar | 1. In Hotkeys-Tab ⌘Space als Toggle-Hotkey für einen Mode setzen. 2. Banner mit "Möglicher Konflikt mit einem System-Hotkey" und "Spotlight" erscheint unterhalb der Toggle-Section. |
| Binding überlebt App-Restart | SC-2 | Persistenz-Verhalten braucht laufenden App-Lifecycle | 1. Toggle-Hotkey setzen. 2. App beenden und neu starten. 3. Hotkeys-Tab öffnen → Binding weiterhin eingetragen. Hotkey funktioniert. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (ToggleHotkeyTests.swift — angelegt in Plan 07-05)
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter (nach Phase-Abschluss)

**Approval:** pending
