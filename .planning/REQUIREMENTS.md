# Requirements: BlitzText

**Defined:** 2026-04-30
**Core Value:** Vom gedrückten Hotkey bis zum eingefügten Text wenige Sekunden — und der Text muss benutzbar sein, ohne nachzubearbeiten.

## v1 Requirements (aktuelle Milestone: Sprecher-Profile + Stabilisierung)

### Sprecher-Profile (Speaker)

- [ ] **SPK-01**: Beim ersten App-Start mit aktivierter Diarization werden bestehende Sprecher-Profile aus persistentem Store geladen und in `DiarizerManager.speakerManager` via `initializeKnownSpeakers` injiziert.
- [ ] **SPK-02**: Nach jeder Aufnahme mit Diarization persistiert die App den aktuellen Profil-Stand (`getSpeakerList()` → JSON in `~/Library/Application Support/BlitzText/speakers.json`) atomar.
- [ ] **SPK-03**: Bekannte Sprecher in Transkript-Output erscheinen mit ihrem zugewiesenen Namen (`Thomas: …`) statt anonym (`Sprecher 1: …`); unbekannte Sprecher fallen auf nummeriert zurück.
- [ ] **SPK-04**: Nutzer:in kann in einem dedizierten Settings-Tab „Sprecher" alle bekannten Profile sehen (Name, Anzahl Erkennungen, letzte Nutzung, `isPermanent`-Flag).
- [ ] **SPK-05**: Nutzer:in kann ein Profil im Settings-Tab umbenennen, löschen, mergen oder als permanent markieren.
- [ ] **SPK-06**: Nutzer:in kann unbenannte Sprecher aus dem letzten Transkript einem Namen zuordnen → das Profil wird permanent und bekommt den Namen.
- [ ] **SPK-07**: Nutzer:in kann den Match-Threshold (0.5–0.9) für die Sprecher-Zuordnung in den Settings setzen.
- [ ] **SPK-08**: Optional — Erst-Enrollment-Flow: kurze Aufnahme (15 s freier Text) → `extractSpeakerEmbedding` → Profil mit Namen anlegen.

### Diarization-UX

- [ ] **DIA-01**: Beim ersten Aktivieren von Diarization wird der ~80 MB-Modell-Download mit Progress-Indikator (Prozent + ungefähre Restzeit) im Settings-Tab angezeigt.
- [ ] **DIA-02**: Schlägt der Download fehl, sieht der Nutzer einen klaren Fehlermeldungs-Hinweis mit Retry-Button im Settings-Tab.

### Stabilität & Doku-Drift

- [ ] **STAB-01**: API-Key wird in Keychain gespeichert (`Service: de.reinholds.blitztext`, `Account: openai-api-key`); UserDefaults-Pfad wird einmalig migriert und entfernt.
- [ ] **STAB-02**: Hotkey-Debounce ist konsistent zwischen Code und Doku (`ARCHITECTURE.md` und `HotkeyManager.swift` einigen sich auf einen Wert mit dokumentierter Begründung).
- [ ] **STAB-03**: Nach Erteilung der Accessibility-Permission startet `CGEventTap` automatisch neu, ohne App-Relaunch.
- [ ] **STAB-04**: Doku in `ARCHITECTURE.md` und `RISKS.md` zu `LocalWhisperClient` reflektiert die echte WhisperKit-Implementierung (kein Stub mehr).

### Test-Fundament

- [ ] **TEST-01**: `project.yml` enthält ein XCTest-Target `BlitzTextTests` mit funktionierender Build-Pipeline.
- [ ] **TEST-02**: Tests existieren für die Hotkey-State-Machine (Halten/Drücken-Modus, Modifier-Kombinationen, Edge-Cases wie schnelles Loslassen).
- [ ] **TEST-03**: Tests existieren für Sprecher-Profil-Matching (cosine-similarity-Threshold, EMA-Update, Persistierung Round-Trip).
- [ ] **TEST-04**: Tests existieren für die Pipeline-Fehlerpfade (Whisper-API-Fail, Parakeet-Modell fehlt, Diarization-Fail bei aktiviertem Setting).

## v2 Requirements

Nicht für aktuelle Milestone, aber bereits identifiziert:

### Privacy & History

- **PRIV-01**: History-Datei (`~/Library/Application Support/BlitzText/history.json`) bekommt Auto-Purge-Option (X Tage) und Opt-Out-Toggle.
- **PRIV-02**: Sprecher-Embeddings at-rest verschlüsselt (über DataProtection-Klasse oder eigene symmetrische Verschlüsselung mit Schlüssel im Keychain).

### Performance & Latenz

- **PERF-01**: Cold-Start des Parakeet-Modells im Hintergrund warm-laufen (vor erster Aufnahme), wenn lokales Backend gewählt ist.
- **PERF-02**: End-to-end-Latenz-Telemetrie (lokal) für Hotkey-Release → Clipboard, sichtbar im Settings-Tab.

### Distribution

- **DIST-01**: Developer-ID-Signing + Notarization in `Scripts/build.sh`.
- **DIST-02**: Sparkle-basierte Auto-Updates.

## Backlog (separate Milestones, nicht v1/v2)

Werden als 999.x-Backlog-Phasen in ROADMAP.md registriert:

- **BL-IOS**: iOS-/iPadOS-Port mit angepasstem Trigger-Modell, gleiche Transkriptions-/Rewrite-Pipeline.
- **BL-MEET-T**: Meeting-Transkription — längere Aufnahmen, dedizierte UI/Workflow, profitiert direkt von SPK-Profilen.
- **BL-MEET-S**: Meeting-Zusammenfassungen — Action-Items aus Meeting-Transkripten via gpt-4o-mini oder Apple Foundation Models. Hängt an BL-MEET-T.

## Out of Scope (permanent oder bis auf Weiteres)

| Feature | Reason |
|---------|--------|
| Cloud-basierte Speaker-ID (AssemblyAI, Deepgram, Speechmatics) | Datenschutz biometrischer Daten + laufende Kosten; FluidAudio liefert lokale API. *Permanent.* |
| Sandbox-Aktivierung | TCC-Handling für Hotkey + Auto-Insert ohne Sandbox erst hart stabilisieren. *Späteres Milestone.* |
| Streaming-Whisper / Echtzeit-Transkription | Eigene Architektur-Initiative; nicht Teil der Sprecher-Profile-Milestone. |
| Mehrsprachige UI | UI bleibt vorerst Deutsch; Code-Identifier Englisch. |
| Apple Foundation Models als Rewrite-Backend | Ab macOS 26 möglich, aber nicht Teil dieser Milestone — separater Track. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SPK-01 | Phase 4 | Pending |
| SPK-02 | Phase 4 | Pending |
| SPK-03 | Phase 4 | Pending |
| SPK-04 | Phase 5 | Pending |
| SPK-05 | Phase 5 | Pending |
| SPK-06 | Phase 5 | Pending |
| SPK-07 | Phase 5 | Pending |
| SPK-08 | Phase 6 | Pending |
| DIA-01 | Phase 3 | Pending |
| DIA-02 | Phase 3 | Pending |
| STAB-01 | Phase 1 | Pending |
| STAB-02 | Phase 1 | Pending |
| STAB-03 | Phase 1 | Pending |
| STAB-04 | Phase 1 | Pending |
| TEST-01 | Phase 2 | Pending |
| TEST-02 | Phase 2 | Pending |
| TEST-03 | Phase 4 | Pending |
| TEST-04 | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0

---
*Requirements defined: 2026-04-30*
*Last updated: 2026-04-30 — traceability table populated by roadmapper*
