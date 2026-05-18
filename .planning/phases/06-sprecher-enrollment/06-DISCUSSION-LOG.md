# Phase 6: Sprecher-Enrollment — Discussion Log

**Datum:** 2026-05-18
**Modus:** default (interaktiv)

---

## Besprochene Bereiche

### 1. UI-Einstieg
**Frage:** Wo startet der Enrollment-Flow?
**Optionen:** Sheet aus SprecherTab / Eigenes NSPanel
**Entscheidung:** Sheet aus SprecherTab
**Begründung:** Passt zum bestehenden Tab-Muster, kein zusätzliches Fenster nötig.

### 2. API-Zugriff (EmbeddingExtractor)
**Frage:** Wie kommt der Enrollment-Flow an den EmbeddingExtractor?
**Optionen:** Neue Methode auf ParakeetClient / EnrollmentService als eigene Klasse
**Entscheidung:** Neue Methode auf ParakeetClient (`enrollSpeaker(audioURL:name:)`)
**Begründung:** Nutzt den bereits geladenen DiarizerManager intern, kein doppeltes Laden.

### 3. Name-Timing
**Frage:** Wann wird der Name eingegeben?
**Optionen:** Vor der Aufnahme / Nach der Aufnahme
**Entscheidung:** Vor der Aufnahme
**Begründung:** Einfachere Logik, kein Zwischenstate.

### 4. Kein Diarizer installiert
**Frage:** Was passiert wenn Diarizer fehlt?
**Optionen:** Button disabled / Button klickbar mit Fehler
**Entscheidung:** Button disabled + Hinweistext
**Begründung:** Kein leerer Klick.

### 5. Aufnahme-UX
**Frage:** Countdown oder manuell stoppen?
**Optionen:** Countdown 15s + Auto-Stopp / Manuell
**Entscheidung:** Countdown 15s + Auto-Stopp (Minimum 5s Sprache)
**Begründung:** Klarer Hinweis auf nötige Sprachmenge.

---

## Von Claude entschieden (ohne User-Befragung)

- `EnrollmentViewModel` als @MainActor ObservableObject (analog DiarizerModelManager aus Phase 3)
- `SpeakerProfileViewModel.addEnrolledSpeaker` als Erweiterungs-Methode
- Fehleranzeige inline im Sheet (kein Alert, Sheet bleibt offen für Retry)
- Mindest-Qualitätsschwellen: 5s Dauer, peak ≥ 0.005 (analog AudioRecorder.silenceThreshold)
- AudioRecorder wird wiederverwendet (von AppDelegate weitergereicht), kein eigener Recorder

---

## Deferred Ideas

- Enrollment über mehrere Sessions akkumulieren → zukünftig
- Audio-Segmente abspielen → Phase 16 (Sprecher-Sample-Wiedergabe)
