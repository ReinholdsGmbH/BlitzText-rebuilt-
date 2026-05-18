---
phase: 06-sprecher-enrollment
plan: "02"
subsystem: enrollment-viewmodel
tags:
  - speaker-enrollment
  - viewmodel
  - state-machine
  - tdd
dependency_graph:
  requires:
    - "06-01: ParakeetClient.enrollSpeaker + EnrollmentError + SpeakerProfileViewModel.addEnrolledSpeaker"
    - "AudioRecorder.start/stop/currentLevel (vorhanden)"
  provides:
    - "EnrollmentViewModel @MainActor ObservableObject mit State-Enum (idle/recording/processing/done/failed)"
    - "Designated-Init mit Closure-Injection (recorderStart/recorderStop/levelPublisher/enroll)"
    - "Convenience-Init wrappt AudioRecorder + ParakeetClient für Production-Wiring"
    - "EnrollmentViewModelTests — 12 State-Machine-Tests via Closure-Fakes"
  affects:
    - "06-03: UI-Sheet bindet auf EnrollmentViewModel.state + currentLevel"
tech_stack:
  added: []
  patterns:
    - "@MainActor ObservableObject mit Closure-Injection (kein Protocol, kein XCTSkip)"
    - "Designated-Init + Convenience-Init Muster (analog DiarizerModelManager)"
    - "Task-basierter Countdown mit Task.isCancelled-Guard und defer-DSGVO-Cleanup"
    - "XCTestExpectation + Combine-Subscription für async State-Transitions in Tests"
key_files:
  created:
    - path: BlitzText/Enrollment/EnrollmentViewModel.swift
      purpose: "@MainActor State-Machine — Countdown, Recorder-Steuerung, Fehler-Mapping, DSGVO-Cleanup"
      loc: 188
    - path: BlitzTextTests/Enrollment/EnrollmentViewModelTests.swift
      purpose: "12 State-Machine-Tests via Closure-Fakes — alle Übergänge gepinnt"
      loc: 262
decisions:
  - "Closure-Injection ist Pflicht-API des Designated-Init — kein Protocol, kein XCTSkip (Architektur-Entscheidung aus 06-02-PLAN.md)"
  - "startCountdown als privater Task mit stride(from:through:by:) — eindeutigerer Countdown ohne off-by-one"
  - "enrollInternal nutzt defer-Block für DSGVO-Cleanup (Erfolg + Fehler) — konsistenter als finally-Muster"
  - "project.yml Globbing erfasst BlitzText/Enrollment/ + BlitzTextTests/Enrollment/ automatisch — kein Eingriff nötig"
metrics:
  duration: "~20 Minuten"
  completed: "2026-05-18"
  tasks_completed: 2
  tests_added: 12
  tests_total_after: 105
---

# Phase 06 Plan 02: EnrollmentViewModel State-Machine — Summary

**One-liner:** @MainActor EnrollmentViewModel mit Closure-Injection, sekundengenauem Countdown, 7 deutschen Pflicht-Fehlerstrings und DSGVO-Cleanup — gepinnt durch 12 grüne Unit-Tests.

## Was wurde gebaut

### Task 1: EnrollmentViewModel.swift (188 LOC)

**Neue Datei:** `BlitzText/Enrollment/EnrollmentViewModel.swift`

- `@MainActor final class EnrollmentViewModel: ObservableObject`
- **State-Enum:** `.idle | .recording(remainingSeconds: Int) | .processing | .done | .failed(String)` — `Equatable` für SwiftUI `.onChange(of:)`
- **Designated-Init** mit Closure-Injection (Pflicht-API für Testbarkeit):
  `init(recorderStart:recorderStop:levelPublisher:enroll:speakerVM:totalSeconds:)`
- **Convenience-Init** für Production-Wiring:
  `init(audioRecorder:parakeetClient:speakerVM:totalSeconds:)` delegiert an Designated-Init
- **Methoden:** `startRecording(name:)`, `stopAndEnroll(name:)`, `reset()`
- **Countdown:** `startCountdown(name:)` via `Task + stride + Task.sleep(nanoseconds:)` — auto-stopp nach `totalSeconds`
- **Enrollment:** `enrollInternal(audioURL:name:)` mit `defer { try? FileManager.default.removeItem(at: audioURL) }` (DSGVO)
- **7 Pflicht-Fehlerstrings** aus 06-UI-SPEC §"Copywriting Contract" — wortwörtlich als `private static let` Konstanten

### Task 2: EnrollmentViewModelTests.swift (262 LOC)

**Neue Datei:** `BlitzTextTests/Enrollment/EnrollmentViewModelTests.swift`

12 Tests, alle grün, kein XCTSkip:

| Test | Verifiziert |
|------|-------------|
| `testInitialState` | VM.state == .idle direkt nach init |
| `testStartRecording_setsRecordingState` | state == .recording(remainingSeconds: 15) nach startRecording |
| `testStartRecording_emptyName_setsFailed` | Leer-/Whitespace-Name → .failed("Bitte einen Namen eingeben.") |
| `testStopAndEnroll_nilURL_setsFailed` | recorderStop nil → .failed("Aufnahme zu kurz oder zu leise …") |
| `testEnrollSuccess_setsDoneAndCallsAddEnrolledSpeaker` | .done + speakerVM.speakers enthält Speaker |
| `testEnrollFails_diarizerNotReady_setsFailedWithGermanString` | EnrollmentError.diarizerNotReady → Pflicht-String |
| `testEnrollFails_tooShort_setsFailedWithGermanString` | EnrollmentError.tooShort → Pflicht-String |
| `testEnrollFails_tooQuiet_setsFailedWithGermanString` | EnrollmentError.tooQuiet → Pflicht-String |
| `testReset_returnsToIdleAndCancelsCountdown` | reset() → .idle, kein .processing nach 1.5 s |
| `testDSGVO_tempFileRemovedAfterEnroll` | Temp-WAV nach .done nicht mehr auf Disk |
| `testStartRecording_fromNonIdleState_isNoop` | Zweiter startRecording ignoriert |
| `testCurrentLevel_updatesFromPublisher` | levelPublisher-Subscription aktualisiert currentLevel |

## Architektur-Notizen

### Closure-Injection ist Pflicht-API — kein Protocol, kein XCTSkip

Die einzige testbare Form ist der Designated-Init mit Closure-Injection. Ein Protocol würde Protocol-Witnesses und zusätzliche Mock-Klassen erzwingen. Die Closure-Variante ist schlanker, typsicher und Swift 6-konform. Diese Entscheidung ist in den plan-`must_haves` festgeschrieben.

### DSGVO: defer-Block statt finally-Äquivalent

```swift
defer {
    try? FileManager.default.removeItem(at: audioURL)
}
```

Der `defer`-Block läuft sowohl bei Erfolg als auch bei jedem Fehler-Pfad — konsistenter als ein manueller `try/catch`-finally-Ersatz. `try?` unterdrückt Fehler bei nicht-existierender Datei (kein zweifaches Löschen-Problem).

### Countdown: stride statt manuelle Variable

```swift
for remaining in stride(from: totalSeconds - 1, through: 0, by: -1) {
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    if Task.isCancelled { return }
    self.state = .recording(remainingSeconds: remaining)
}
```

`stride(from: totalSeconds-1, through: 0, by: -1)` vermeidet off-by-one und ist lesbar. Initial-State `.recording(remainingSeconds: totalSeconds)` wird von `startRecording` gesetzt — der Countdown beginnt bei `totalSeconds-1`.

### project.yml Globbing

`project.yml` nutzt `path: BlitzText` (Zeile 30) und `path: BlitzTextTests` (Zeile 71) — beide als Verzeichnis-Pfade ohne explizite Unterverzeichnisse. XcodeGen globbt automatisch alle `**/*.swift` darunter. Neue Unterverzeichnisse (`Enrollment/`) werden nach `xcodegen generate` korrekt erfasst. Kein manueller Eingriff in `project.yml` nötig.

## Test-Run-Output

```
Test Suite 'EnrollmentViewModelTests' passed at 2026-05-18 13:50:32
   Executed 12 tests, with 0 failures in 3.446 seconds

Test Suite 'BlitzTextTests.xctest' passed at 2026-05-18 13:50:38
   Executed 105 tests, with 0 failures in 11.702 seconds

** TEST SUCCEEDED **
```

Volle Suite: 105 Tests (93 vorher + 12 neue), keine Regression.

## Deviations from Plan

Keine. Plan wurde exakt wie spezifiziert ausgeführt.

Einzige Abweichung vom Wortlaut: `convenience init(audioRecorder:` steht in der Datei als `convenience init(` mit dem Parameter auf der nächsten Zeile (Swift-Formatierungskonvention) — funktional identisch.

## Commits

| Hash | Beschreibung |
|------|-------------|
| ecd4424 | feat(06-02): EnrollmentViewModel — Closure-Injection State-Machine + DSGVO-Cleanup |
| 17b0ddd | test(06-02): EnrollmentViewModelTests — 12 State-Machine-Tests via Closure-Fakes |

## Known Stubs

Keine. EnrollmentViewModel ist vollständig implementiert. Alle State-Übergänge sind durch Tests gepinnt.

## Threat Flags

Keine neuen Angriffsflächen außerhalb des dokumentierten Threat Models:
- T-06-05 (Tampering): `guard case .idle = state else { return }` in `startRecording` — mitigiert
- T-06-06 (Info Disclosure): `defer { try? FileManager.default.removeItem(at: audioURL) }` — mitigiert, test-gepinnt
- T-06-07 (DoS): `countdownTask?.cancel()` in `reset()` — mitigiert, test-gepinnt
- T-06-08 (Tampering): `name.trimmingCharacters + guard !trimmed.isEmpty` — mitigiert, test-gepinnt

## Self-Check: PASSED

| Check | Status |
|-------|--------|
| BlitzText/Enrollment/EnrollmentViewModel.swift | FOUND |
| BlitzTextTests/Enrollment/EnrollmentViewModelTests.swift | FOUND |
| commit ecd4424 | FOUND |
| commit 17b0ddd | FOUND |
| 105 Tests grün | VERIFIED |
