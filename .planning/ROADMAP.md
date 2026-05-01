# Roadmap: BlitzText — Sprecher-Profile + Stabilisierung

**Created:** 2026-04-30
**Milestone:** Sprecher-Profile + Stabilisierung
**Granularity:** standard
**Coverage:** 18/18 v1 requirements mapped

## Phases

- [x] **Phase 1: Stabilisierung & Doku-Drift** — Keychain-Migration, Hotkey-Debounce, Tap-Auto-Restart, Doku-Aktualisierung
- [ ] **Phase 2: Test-Fundament** — XCTest-Target plus Tests für Hotkey-Statemachine und Pipeline-Fehlerpfade
- [ ] **Phase 3: Diarization-UX** — Sichtbarer Modell-Download mit Progress und Retry
- [ ] **Phase 4: Sprecher-Profile Core** — Persistenter Store + Integration mit `DiarizerManager.speakerManager`
- [ ] **Phase 5: Sprecher-Profile UI** — Settings-Tab "Sprecher" mit Verwaltung, Threshold und Zuordnung
- [ ] **Phase 6: Sprecher-Enrollment** — Optionaler Erst-Enrollment-Flow für gezielte Profil-Anlage
- [ ] **Phase 7: Standard-Hotkeys & eigene Hotkeys** — Default-Hotkey-Set + freie Tastenkombo-Vergabe pro Mode (Hybrid CGEventTap + SPM-Hotkey-Package)

## Phase Details

### Phase 1: Stabilisierung & Doku-Drift
**Goal**: Bestehende Risiken und Doku-Drift schließen, bevor neue Features draufgesetzt werden
**Depends on**: Nothing (first phase)
**Requirements**: STAB-01, STAB-02, STAB-03, STAB-04
**Success Criteria** (what must be TRUE):
  1. OpenAI-API-Key liegt in der Keychain (`Service: de.reinholds.blitztext`, `Account: openai-api-key`); ein bestehender UserDefaults-Wert wird beim ersten Start migriert und entfernt
  2. Hotkey-Debounce-Wert ist in `HotkeyManager.swift` und `ARCHITECTURE.md` identisch und mit kurzer Begründung dokumentiert
  3. Nach Erteilen der Accessibility-Permission funktionieren Hotkeys ohne App-Relaunch (Tap startet automatisch neu)
  4. `ARCHITECTURE.md` und `RISKS.md` beschreiben `LocalWhisperClient` als echte WhisperKit-Implementierung (kein Stub-Wording mehr)
**Plans**: 4 plans
- [x] 01-01-PLAN.md — STAB-01: API-Key in Keychain + UserDefaults-Migration
- [x] 01-02-PLAN.md — STAB-02: Hotkey-Debounce-Konstanten extrahieren + Doku-Sync
- [x] 01-03-PLAN.md — STAB-03: CGEventTap Auto-Restart nach Permission-Grant
- [x] 01-04-PLAN.md — STAB-04: RISKS.md + ARCHITECTURE.md LocalWhisper-Drift entfernen

### Phase 2: Test-Fundament
**Goal**: Automatisierte Test-Pipeline existiert und deckt die fragilsten Codepfade ab
**Depends on**: Phase 1
**Requirements**: TEST-01, TEST-02, TEST-04
**Success Criteria** (what must be TRUE):
  1. `BlitzTextTests`-Target existiert in `project.yml` und lässt sich via `xcodebuild test` grün ausführen
  2. Hotkey-State-Machine (Halten-/Drücken-Modus, Modifier-Kombinationen, schnelles Loslassen) ist durch Unit-Tests abgedeckt
  3. Pipeline-Fehlerpfade (Whisper-API-Fehler, fehlendes Parakeet-Modell, Diarization-Fehlschlag) sind durch Tests abgedeckt
  4. Test-Suite läuft lokal in unter 30 Sekunden und produziert keine Flakes über drei Durchläufe
**Plans**: 3 plans

- [x] 02-01-PLAN.md — Wave 0: BlitzTextTests-Target + Hotkey/ModeProcessor/Recorder-Test-Seams + Fakes + SmokeTests
- [ ] 02-02-PLAN.md — Hotkey-State-Machine-Tests (Hold/Toggle, Modifier-Matrix, Debounce)
- [ ] 02-03-PLAN.md — Pipeline-Fehlerpfade (Whisper-API-Fehler, Parakeet-Modell, Diarization-Fehlschlag)

### Phase 3: Diarization-UX
**Goal**: Diarization-Modell-Download wird sichtbar, fehlerfest und vom Nutzer kontrollierbar
**Depends on**: Phase 1
**Requirements**: DIA-01, DIA-02
**Success Criteria** (what must be TRUE):
  1. Beim ersten Aktivieren von Diarization sieht der Nutzer im Settings-Tab einen Progress-Indikator mit Prozent und ungefährer Restzeit für den ~80 MB-Download
  2. Schlägt der Download fehl, erscheint im Settings-Tab eine deutsche Fehlermeldung mit Retry-Button, der den Download neu anstößt
  3. Solange das Modell nicht vollständig geladen ist, ist der Diarization-Toggle deaktiviert oder klar als "wird geladen" markiert
**Plans**: TBD
**UI hint**: yes

### Phase 4: Sprecher-Profile Core
**Goal**: Bekannte Stimmen werden lokal persistiert und in laufenden Aufnahmen automatisch wiedererkannt
**Depends on**: Phase 2
**Requirements**: SPK-01, SPK-02, SPK-03, TEST-03
**Success Criteria** (what must be TRUE):
  1. Beim App-Start mit aktivierter Diarization werden gespeicherte Sprecher-Profile aus `~/Library/Application Support/BlitzText/speakers.json` geladen und via `initializeKnownSpeakers` in `DiarizerManager.speakerManager` injiziert
  2. Nach jeder Aufnahme mit Diarization wird der aktuelle Profil-Stand (`getSpeakerList()`) atomar als JSON in `speakers.json` persistiert
  3. Im Transkript-Output erscheinen bekannte Sprecher mit ihrem Namen (`Thomas: …`); unbekannte fallen auf nummerierte `Sprecher N: …`-Form zurück
  4. Sprecher-Profil-Matching (Cosine-Similarity-Threshold, EMA-Update, Persistierungs-Round-Trip) ist durch Unit-Tests abgedeckt
**Plans**: TBD

### Phase 5: Sprecher-Profile UI
**Goal**: Nutzer:in kann Sprecher-Profile vollständig im Settings-Fenster verwalten
**Depends on**: Phase 4
**Requirements**: SPK-04, SPK-05, SPK-06, SPK-07
**Success Criteria** (what must be TRUE):
  1. Ein neuer Settings-Tab "Sprecher" listet alle bekannten Profile mit Name, Anzahl Erkennungen, letzter Nutzung und `isPermanent`-Flag
  2. Nutzer:in kann ein Profil im Tab umbenennen, löschen, mit einem anderen mergen und als permanent markieren; Änderungen landen sofort in `speakers.json`
  3. Aus dem letzten Transkript kann eine unbenannte Sprecher-ID per UI einem Namen zugewiesen werden — das Profil wird permanent und trägt anschließend den Namen
  4. Der Match-Threshold (0.5–0.9) ist als Slider im Settings-Tab einstellbar und wirkt sich auf die nächste Aufnahme aus
**Plans**: TBD
**UI hint**: yes

### Phase 6: Sprecher-Enrollment
**Goal**: Nutzer:in kann ein Sprecher-Profil gezielt durch eine kurze Aufnahme anlegen
**Depends on**: Phase 5
**Requirements**: SPK-08
**Success Criteria** (what must be TRUE):
  1. Aus dem Sprecher-Tab startet ein Enrollment-Flow eine ~15-Sekunden-Aufnahme freier Sprache mit Live-Pegel und Restzeit-Anzeige
  2. Nach der Aufnahme wird via `extractSpeakerEmbedding` ein neues, permanentes Profil mit dem vom Nutzer eingegebenen Namen angelegt und in `speakers.json` gespeichert
  3. Bricht die Aufnahme ab oder ist sie zu kurz/zu leise, wird kein Profil angelegt und der Nutzer sieht eine klare Fehlermeldung
**Plans**: TBD
**UI hint**: yes

### Phase 7: Standard-Hotkeys & eigene Hotkeys
**Goal**: Sinnvolle Default-Hotkeys ausliefern und Nutzer:innen erlauben, eigene Hotkeys frei zu vergeben
**Depends on**: Phase 1 (Hotkey-Debounce / Tap-Auto-Restart sollten vorher konsolidiert sein)
**Requirements**: keine v1-Mapping (milestone-erweiternd, aus Backlog 999.6 promoted)
**Success Criteria** (what must be TRUE):
  1. Hold-Pfad behält die existierenden fn+Shift / fn+Ctrl / fn+Option-Defaults und funktioniert unverändert für Bestandsnutzer
  2. Pro Mode kann optional eine freie Tastenkombo (z.B. ⌘⇧B) für den Toggle-Pfad gesetzt werden — registriert via SPM-Hotkey-Package, persistiert im `SettingsStore`-Snapshot
  3. Neuer Settings-Tab "Hotkeys" zeigt eine Tabelle mit Hold-/Toggle-Bindings, Recorder-Widget, "Auf Standard zurücksetzen"-Button pro Zeile
  4. Bei Verdacht auf System-Konflikt erscheint ein dezentes Warn-Banner; In-App-Doppelbelegungen werden im Recorder vorab verhindert
**Plans**: TBD
**UI hint**: yes
**Context**: 07-CONTEXT.md (gathered 2026-04-30 als 999.6, promoted via /gsd-review-backlog)

## Backlog

Eingeplante Initiativen für künftige Milestones — werden bei Bedarf via `/gsd-insert-phase` oder neuem Milestone aktiviert.

### Phase 999.1: iOS-/iPadOS-Port
**Goal**: BlitzText als mobile App mit angepassten Trigger-Modellen, gleiche Transkriptions-/Rewrite-Pipeline
**Depends on**: macOS-Version stabil; FluidAudio iOS-Support geprüft
**Requirements**: BL-IOS
**Notes**: Andere Hotkey-/Trigger-Modelle (Keyboard-Shortcut, Action-Button, Share-Sheet); shared core mit macOS prüfen

### Phase 999.2: Meeting-Transkription
**Goal**: Längere Aufnahmen mit Diarization, dedizierte UI/Workflow (kein Auto-Paste, Speichern + Anzeigen mit Sprecher-Annotationen)
**Depends on**: Phase 4 (Sprecher-Profile Core), Phase 5 (UI)
**Requirements**: BL-MEET-T
**Notes**: Profitiert direkt von den persistenten Sprecher-Profilen aus dieser Milestone

### Phase 999.3: Meeting-Zusammenfassungen
**Goal**: Action-Items, Entscheidungen und offene Fragen aus Meeting-Transkripten via gpt-4o-mini oder Apple Foundation Models
**Depends on**: Phase 999.2
**Requirements**: BL-MEET-S
**Notes**: Apple Foundation Models ab macOS 26 als lokale Alternative prüfen

### Phase 999.4: Übersetzung einer Transkription (BACKLOG)
**Goal**: [Captured for future planning] Transkriptionsergebnis optional in eine Zielsprache übersetzen
**Requirements**: TBD
**Plans**: 0 plans

Plans:
- [ ] TBD (promote with /gsd-review-backlog when ready)

### Phase 999.5: Übersetzung einer Meeting-Zusammenfassung (BACKLOG)
**Goal**: [Captured for future planning] Meeting-Zusammenfassung optional in eine Zielsprache übersetzen
**Requirements**: TBD
**Plans**: 0 plans

Plans:
- [ ] TBD (promote with /gsd-review-backlog when ready)

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Stabilisierung & Doku-Drift | 0/0 | Not started | - |
| 2. Test-Fundament | 0/0 | Not started | - |
| 3. Diarization-UX | 0/0 | Not started | - |
| 4. Sprecher-Profile Core | 0/0 | Not started | - |
| 5. Sprecher-Profile UI | 0/0 | Not started | - |
| 6. Sprecher-Enrollment | 0/0 | Not started | - |
| 7. Standard-Hotkeys & eigene Hotkeys | 0/0 | Not started | - |
| 999.1. iOS-/iPadOS-Port | 0/0 | Backlog | - |
| 999.2. Meeting-Transkription | 0/0 | Backlog | - |
| 999.3. Meeting-Zusammenfassungen | 0/0 | Backlog | - |
| 999.4. Übersetzung einer Transkription | 0/0 | Backlog | - |
| 999.5. Übersetzung einer Meeting-Zusammenfassung | 0/0 | Backlog | - |

## Coverage

All 18 v1 requirements mapped to exactly one phase. No orphans.

| Phase | Requirements |
|-------|--------------|
| Phase 1 | STAB-01, STAB-02, STAB-03, STAB-04 |
| Phase 2 | TEST-01, TEST-02, TEST-04 |
| Phase 3 | DIA-01, DIA-02 |
| Phase 4 | SPK-01, SPK-02, SPK-03, TEST-03 |
| Phase 5 | SPK-04, SPK-05, SPK-06, SPK-07 |
| Phase 6 | SPK-08 |
| Phase 7 | — (milestone-erweiternd, kein v1-Requirement; promoted aus Backlog 999.6) |

**Note on TEST-03 placement:** TEST-03 (Sprecher-Profil-Matching-Tests) lebt in Phase 4 statt Phase 2, weil die zu testenden Komponenten (Persistenz, EMA-Update, Threshold-Matching) erst in Phase 4 entstehen. Phase 2 etabliert das Test-Target und deckt Hotkey + Pipeline-Fehlerpfade ab; Phase 4 erweitert die Suite parallel zur Implementierung.

---
*Roadmap erstellt: 2026-04-30*
