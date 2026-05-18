---
phase: 06
name: Sprecher-Enrollment
status: context-gathered
date: "2026-05-18"
---

# Phase 6: Sprecher-Enrollment — Kontext

## Domain

Nutzer:in kann aus dem Sprecher-Tab heraus ein gezieltes Sprecher-Profil anlegen,
indem sie ~15 Sekunden frei spricht. Kein Diktier-Durchlauf nötig — reines Enrollment.

---

## Decisions

### UI-Einstieg
- **Sheet aus SprecherTab** — Button "Neues Profil aufnehmen" im `SprecherTab` öffnet
  ein SwiftUI-`.sheet(...)`. Kein eigenes Fenster, kein Panel.
- Button ist **disabled** wenn Diarizer nicht installiert ist;
  darunter Caption: *"Diarizer-Modell nicht installiert. Aktiviere Sprechererkennung im Backend-Tab."*
- Der Sheet-State liegt in `SprecherTab` als `@State private var showEnrollmentSheet = false`.

### API-Zugriff (EmbeddingExtractor)
- `ParakeetClient` bekommt eine neue public-async-throws-Methode:
  ```swift
  func enrollSpeaker(audioURL: URL, name: String) async throws -> Speaker
  ```
- Die Methode nutzt den **bereits geladenen** internen `diarizer` (DiarizerManager).
  Ist er nil oder `embeddingExtractor` nil → wirft `EnrollmentError.diarizerNotReady`.
- Kein zweites Modell-Laden. Wenn der Diarizer noch nicht geladen ist, ruft die Methode
  intern `ensureLoaded()` auf (wie `warmUp()`). Ist er danach immer noch nil, Fehler.
- Nach erfolgreichem `extractSpeakerEmbedding`: neuer `Speaker` wird über
  `SpeakerManager.upsertSpeaker(...)` oder direkt via `SpeakerProfileStore.saveSpeakers`
  mit `isPermanent = true` persistiert.

### Name-Timing
- **Vor der Aufnahme**: User gibt den Namen ins Textfeld ein, dann Klick auf "Aufnehmen".
- Leerer oder nur-Whitespace-Name blockiert den "Aufnehmen"-Button.

### Aufnahme-UX
- **Countdown 15 Sekunden + Auto-Stopp**.
- Live-Pegel-Balken (renutzt `AudioRecorder.currentLevel`) während der Aufnahme.
- Restzeit-Anzeige: zählt von 15 auf 0, stoppt dann automatisch.
- User kann auch **vorher manuell stoppen** (Stopp-Button ersetzt "Aufnehmen").
- **Mindest-Qualitätsschwellen** (kein Profil bei Fehler, stattdessen deutsche Fehlermeldung):
  - Zu kurz: < 5 s Sprache (gemessen an Audio-Länge nach `stop()`)
  - Zu leise: `peakAmplitude < 0.005` (selbe Schwelle wie `AudioRecorder.silenceThreshold`)
- Nach Auto- oder Manuell-Stopp → Embedding-Extraktion → Profil-Anlage → Sheet schließt.

### EnrollmentViewModel
- `@MainActor final class EnrollmentViewModel: ObservableObject` (neues File)
- State: `.idle | .recording(remainingSeconds: Int) | .processing | .done | .failed(String)`
- Hält eine Referenz auf `AudioRecorder` (von AppDelegate übergeben, kein eigener Recorder).
- Ruft `parakeetClient.enrollSpeaker(audioURL:name:)` nach `recorder.stop()` auf.
- Nach Erfolg: `speakerVM.addEnrolledSpeaker(speaker:)` (neue Methode in SpeakerProfileViewModel).

### SpeakerProfileViewModel-Erweiterung
- Neue Methode `addEnrolledSpeaker(_ speaker: Speaker)`:
  appended zur lokalen `speakers`-Liste, setzt `isPermanent = true`, ruft `store.saveSpeakers`.

### Fehlerbehandlung im Sheet
- Fehlermeldung erscheint inline im Sheet (kein Alert), z. B. in roter Caption unter dem Pegel.
- Nach Fehler: Sheet bleibt offen, Name-Feld ist vorausgefüllt, User kann nochmal versuchen.
- Fehler-Strings auf Deutsch.

### Diarizer-Voraussetzung im Sprecher-Tab
- `SprecherTab` prüft via `diarizerManager.isInstalled` (bereits verfügbar als `@EnvironmentObject`
  oder per Zugriff auf `DiarizerModelManager`).
- Wenn nicht installiert → Button disabled, Caption sichtbar.
- Wenn installiert aber noch nicht warm → Button aktiv, Enrollment-Start triggert `warmUp()`.

---

## Canonical Refs

- [BlitzText/Transcription/ParakeetClient.swift](BlitzText/Transcription/ParakeetClient.swift) — hier wird `enrollSpeaker` hinzugefügt
- [BlitzText/Transcription/SpeakerProfileStore.swift](BlitzText/Transcription/SpeakerProfileStore.swift) — Persistenz-Layer
- [BlitzText/Transcription/SpeakerProfileViewModel.swift](BlitzText/Transcription/SpeakerProfileViewModel.swift) — erhält `addEnrolledSpeaker`
- [BlitzText/Settings/SettingsView.swift](BlitzText/Settings/SettingsView.swift) — SprecherTab (Sheet-Mount)
- [BlitzText/Audio/AudioRecorder.swift](BlitzText/Audio/AudioRecorder.swift) — wird im Enrollment-Flow wiederverwendet
- [BlitzText/App/AppDelegate.swift](BlitzText/App/AppDelegate.swift) — Dependency-Wiring (AudioRecorder + EnrollmentViewModel)
- [.planning/phases/06-sprecher-enrollment/06-CONTEXT.md](.planning/phases/06-sprecher-enrollment/06-CONTEXT.md)

**FluidAudio 0.14.3 API-Fakten (verifiziert via swiftmodule strings):**
- `DiarizerManager.embeddingExtractor: EmbeddingExtractor?` — Property
- `EmbeddingExtractor.extractSpeakerEmbedding(...)` — Methode für Enrollment
- `SpeakerManager.upsertSpeaker(id:name:currentEmbedding:duration:rawEmbeddings:updateCount:createdAt:updatedAt:isPermanent:)` — direktes Upsert

---

## Code Context

### Wiederverwendbare Assets
- `AudioRecorder.currentLevel: Float` (@Published) — Live-Pegel für Sheet-UI
- `AudioRecorder.start() throws -> URL` + `stop() -> URL?` — exakt die Enrollment-Aufnahme-API
- `DiarizerModelManager.isInstalled: Bool` (@Published) — für Button-Disabled-Logik
- `SpeakerProfileStore.saveSpeakers([Speaker])` — direkte Persistenz
- `SpeakerProfileViewModel` als @EnvironmentObject in SettingsView — Sheet erbt es

### Muster aus Phase 3/5
- `DiarizerModelManager` als `@MainActor ObservableObject` — gleiches Muster für `EnrollmentViewModel`
- Sheet-Pattern aus Phase 5 (`confirmationDialog`) zeigt den Stil für modalen Content in SprecherTab

---

## Out of Scope (Deferred)

- Enrollment über mehrere Sessions akkumulieren (künftiger Multi-Session-Enrollment)
- Audio-Segmente abspielen nach Enrollment (→ Phase 16: Sprecher-Sample-Wiedergabe)
- Import von Embeddings aus Datei (→ Phase 14 / Backlog)
