---
phase: 06-sprecher-enrollment
plan: "03"
subsystem: enrollment-ui
tags:
  - speaker-enrollment
  - ui
  - swiftui
  - sheet
  - di-wiring
dependency_graph:
  requires:
    - 06-01  # ParakeetClient.enrollSpeaker, EnrollmentError
    - 06-02  # EnrollmentViewModel, addEnrolledSpeaker
  provides:
    - EnrollmentSheet SwiftUI-View (SPK-08 UI-Schicht)
    - AppDelegate enrollmentViewModel DI
    - SettingsWindowController enrollmentViewModel-Injection
    - SprecherTab ENROLLMENT-Section + Sheet-Mount
  affects:
    - BlitzText/App/AppDelegate.swift
    - BlitzText/Settings/SettingsWindowController.swift
    - BlitzText/Settings/SettingsView.swift
    - BlitzText/Enrollment/EnrollmentSheet.swift
tech_stack:
  added: []
  patterns:
    - SwiftUI .sheet(isPresented:) aus SprecherTab
    - @EnvironmentObject DI-Kette via SettingsWindowController
    - State-Switch in @ViewBuilder
    - LevelMeterBar als private nested struct
key_files:
  created:
    - BlitzText/Enrollment/EnrollmentSheet.swift
  modified:
    - BlitzText/App/AppDelegate.swift
    - BlitzText/Settings/SettingsWindowController.swift
    - BlitzText/Settings/SettingsView.swift
    - BlitzText.xcodeproj/project.pbxproj
decisions:
  - "EnrollmentSheet.swift manuell zur pbxproj-Datei hinzugefügt (war nicht im Projekt registriert)"
  - "diarizerManager-EnvironmentObject war laut PATTERNS.md bereits in SettingsWindowController — bestätigt, kein Fallback nötig"
metrics:
  duration: "~20 Minuten"
  completed: "2026-05-18"
  tasks_completed: 3
  tasks_total: 4
  files_changed: 5
---

# Phase 06 Plan 03: UI-Schicht Enrollment-Wiring Summary

**One-liner:** EnrollmentSheet (SwiftUI) vollständig mit State-Switch, LevelMeterBar und Auto-Dismiss verkabelt; DI-Kette AppDelegate → SettingsWindowController → SprecherTab komplett.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | AppDelegate + SettingsWindowController DI-Wiring | d26cdb1 | AppDelegate.swift, SettingsWindowController.swift |
| 2 | EnrollmentSheet SwiftUI-View nach 06-UI-SPEC | 5a3f590 | EnrollmentSheet.swift (NEU) |
| 3 | SprecherTab ENROLLMENT-Section + Sheet-Mount | 6e5504a | SettingsView.swift, project.pbxproj |

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] EnrollmentSheet.swift nicht im Xcode-Projekt registriert**
- **Found during:** Task 3 (Build-Fehler: "cannot find 'EnrollmentSheet' in scope")
- **Issue:** Die neue Datei `BlitzText/Enrollment/EnrollmentSheet.swift` war nicht in `project.pbxproj` eingetragen. Xcode kompiliert nur registrierte Dateien.
- **Fix:** Zwei neue UUIDs generiert, PBXBuildFile + PBXFileReference + Gruppen-Eintrag + Sources-Build-Phase-Eintrag in `project.pbxproj` hinzugefügt.
- **Files modified:** `BlitzText.xcodeproj/project.pbxproj`
- **Commit:** 6e5504a

---

## Build Output

```
** BUILD SUCCEEDED **
```

---

## Test Suite Output

```
Test Suite 'All tests' passed at 2026-05-18 13:56:16.461.
	 Executed 105 tests, with 0 failures (0 unexpected) in 10.061 (10.127) seconds
** TEST SUCCEEDED **
```

---

## UAT-Checkpoint-Status

**Status:** Awaiting Human-Verify (Task 4 — checkpoint:human-verify gate="blocking")

Human-Verify-Checkliste mit 15 UAT-Schritten ausstehennd. End-to-End-Test (Sprecher-Tab → Sheet → Aufnahme → Profil → Persistenz → Fehler-Pfade) muss manuell durchgeführt werden.

---

## Known Stubs

Keine. Alle UI-Komponenten sind mit echten Dependencies verkabelt:
- `enrollmentVM` kommt aus `AppDelegate.enrollmentViewModel` (echte AudioRecorder + ParakeetClient + SpeakerProfileViewModel)
- `diarizerManager.isInstalled` ist ein echter @Published-Wert
- EnrollmentSheet rendert State-getrieben auf Basis von `EnrollmentViewModel.state`

---

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: concurrent-recorder | BlitzText/Settings/SettingsView.swift | T-06-09: "Neues Profil aufnehmen"-Button ist nur an `!diarizerManager.isInstalled` disabled, nicht an `modeProcessor.state != .idle`. 06-UI-SPEC §"Vertrag 5" empfiehlt zusätzliches Disable wenn Diktat läuft. modeProcessor ist kein @EnvironmentObject in SprecherTab — als Deferred-Hardening dokumentiert. |

---

## Self-Check

### Created files:
- [x] `BlitzText/Enrollment/EnrollmentSheet.swift` — FOUND

### Commits:
- [x] d26cdb1 — feat(06-03): AppDelegate + SettingsWindowController DI-Wiring
- [x] 5a3f590 — feat(06-03): EnrollmentSheet SwiftUI-View nach 06-UI-SPEC
- [x] 6e5504a — feat(06-03): SprecherTab ENROLLMENT-Section + Sheet-Mount

## Self-Check: PASSED
