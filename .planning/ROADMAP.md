# Roadmap: BlitzText — Sprecher-Profile + Stabilisierung

**Created:** 2026-04-30
**Milestone:** Sprecher-Profile + Stabilisierung
**Granularity:** standard
**Coverage:** 18/18 v1 requirements mapped

## Phases

- [x] **Phase 1: Stabilisierung & Doku-Drift** — Keychain-Migration, Hotkey-Debounce, Tap-Auto-Restart, Doku-Aktualisierung
- [x] **Phase 2: Test-Fundament** — XCTest-Target plus Tests für Hotkey-Statemachine und Pipeline-Fehlerpfade
- [x] **Phase 3: Diarization-UX** — Sichtbarer Modell-Download mit Progress und Retry (verification pending)
- [ ] **Phase 4: Sprecher-Profile Core** — Persistenter Store + Integration mit `DiarizerManager.speakerManager`
- [ ] **Phase 5: Sprecher-Profile UI** — Settings-Tab "Sprecher" mit Verwaltung, Threshold und Zuordnung
- [ ] **Phase 6: Sprecher-Enrollment** — Optionaler Erst-Enrollment-Flow für gezielte Profil-Anlage
- [x] **Phase 7: Standard-Hotkeys & eigene Hotkeys** — Default-Hotkey-Set + freie Tastenkombo-Vergabe pro Mode (Hybrid CGEventTap + SPM-Hotkey-Package) (completed 2026-05-19)
- [x] **Phase 8: Apple Foundation Rewrite-Backend** — Foundation Models (macOS 26+) als Default-Backend für Plus/Rant, OpenAI als User-Override (completed 2026-05-04)
- [ ] **Phase 9: Vibe Coding — Variable Recognition** — Post-Processor erkennt camelCase/snake_case/kebab/PascalCase/CONSTANT aus Sprache
- [ ] **Phase 10: Vibe Coding — File Tagging** — Erkennt gesprochene Dateinamen-Token (z. B. "index dot tsx") und formatiert sie korrekt
- [ ] **Phase 11: Auto-Cleanup-Levels + Undo-AI-Edit** — Style-Presets None/Light/Medium/High auf Rewrite-Backend + Original-Diktat aufbewahren mit "Undo AI edit"
- [ ] **Phase 12: Custom Vocabulary** — Eigennamen/Fachbegriffe als Whisper-Initial-Prompt + Post-Processor-Lookup, UI für Verwaltung
- [ ] **Phase 13: Experimental — Voice Commands** — End-of-Dictation-Commands ("neue Zeile", "Enter drücken", "lösche das") via CGEvent-Synthese
- [ ] **Phase 14: Experimental — Bulk Import** — JSON/CSV-Import ins Custom Vocabulary über NSOpenPanel
- [ ] **Phase 15: System-Polish & QoL** — Launch-at-Login, Show-in-Dock, Dictation-/Notification-Sounds, Mute-Music-while-Dictating
- [ ] **Phase 16: Sprecher-Sample-Wiedergabe** — Audio-Fragmente pro Sprecher aus dem letzten Transkript abspielen, damit unbekannte Stimmen nachträglich benannt werden können

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
- [x] 02-02-PLAN.md — Hotkey-State-Machine-Tests (Hold/Toggle, Modifier-Matrix, Debounce) — 17 Tests, 3x consecutive gruen
- [x] 02-03-PLAN.md — Pipeline-Fehlerpfade (Whisper-API-Fehler, Parakeet-Modell, Diarization-Silent-Fallback) — 3 Tests, 3x consecutive gruen, volle Suite 22/22

### Phase 3: Diarization-UX
**Goal**: Diarization-Modell-Download wird sichtbar, fehlerfest und vom Nutzer kontrollierbar
**Depends on**: Phase 1
**Requirements**: DIA-01, DIA-02
**Success Criteria** (what must be TRUE):
  1. Beim ersten Aktivieren von Diarization sieht der Nutzer im Settings-Tab einen Progress-Indikator mit Prozent und ungefährer Restzeit für den ~80 MB-Download
  2. Schlägt der Download fehl, erscheint im Settings-Tab eine deutsche Fehlermeldung mit Retry-Button, der den Download neu anstößt
  3. Solange das Modell nicht vollständig geladen ist, ist der Diarization-Toggle deaktiviert oder klar als "wird geladen" markiert
**Plans**: 2 plans

- [x] 03-01-PLAN.md — Wave 0: DiarizerModelManager-Foundation + ETAEstimator + Loader-Protokoll + Tests (15 Tests)
- [x] 03-02-PLAN.md — Wave 2: Vier-State-UI in SettingsView + SettingsStore-didSet + ParakeetClient-Refactor + AppDelegate-Prewarm (39/39 Tests, 3x grün)

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
**Plans**: 3 plans
- [x] 06-01-PLAN.md — Wave 1: ParakeetClient.enrollSpeaker + EnrollmentError + SpeakerProfileViewModel.addEnrolledSpeaker + ModeProcessor-Sichtbarkeit + Tests
- [x] 06-02-PLAN.md — Wave 2: EnrollmentViewModel @MainActor State-Machine (idle/recording/processing/done/failed) + Countdown + Closure-Injection + Unit-Tests
- [x] 06-03-PLAN.md — Wave 3: EnrollmentSheet UI + SprecherTab ENROLLMENT-Section + AppDelegate/SettingsWindowController DI + Human-Verify-UAT (pending)
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
**Plans**: 5 plans

Plans:
- [x] 07-01-PLAN.md — Wave 0 Spike: keyCode-Äquivalenz A3 (CGEvent ↔ Carbon auf Apple-Silicon verifizieren)
- [x] 07-02-PLAN.md — Wave 1: SPM-Integration (sindresorhus/KeyboardShortcuts 2.4.0) + SettingsStore Toggle-Hotkey-Properties + Snapshot + Accessoren
- [x] 07-03-PLAN.md — Wave 2: HotkeyManager additiver Toggle-Layer (setupToggleHotkeys/teardown/reload + Combine-Sink + Idempotenz-Guard)
- [x] 07-04-PLAN.md — Wave 2: UI HotkeysTab (HoldHotkeyRow + ToggleHotkeyRow 5 States + ConflictWarningBanner) + AnpassenTab-Refactoring
- [x] 07-05-PLAN.md — Wave 3: Tests (ToggleHotkeyTests: Snapshot-Roundtrip, Doppelbelegung, fn-Check, Nur-Modifier, Conflict-Detection)
**UI hint**: yes
**Context**: 07-CONTEXT.md (gathered 2026-04-30 als 999.6, promoted via /gsd-review-backlog)

### Phase 8: Apple Foundation Rewrite-Backend
**Goal**: Apple Foundation Models (macOS 26+) als lokale Default-Alternative zu gpt-4o-mini im Rewrite-Pfad; OpenAI als expliziter User-Override
**Depends on**: keine harten Deps (Rewrite/-Modul ist von Sprecher-Profile- und Hotkey-Phasen unabhängig — kann parallel zu Phase 3–7 laufen)
**Requirements**: keine v1-Mapping (milestone-erweiternd, aus Backlog 999.7 promoted)
**Success Criteria** (what must be TRUE):
  1. Neuer `AppleFoundationRewriteClient` implementiert das `RewriteService`-Protokoll und ist über einen `RewriteBackend`-Enum (analog `TranscriptionBackend`) im `SettingsStore` auswählbar
  2. Pro Rewrite-Mode (Blitztext+ / Blitztext $%&!) kann das Backend unabhängig in den Settings gesetzt werden; Defaults: Foundation wenn verfügbar, sonst OpenAI
  3. Blitztext+ nutzt Plain `LanguageModelSession`; Blitztext $%&! nutzt Guided Generation mit `@Generable`-Schema, das den entschärften Text strukturiert zurückliefert
  4. Beim App-Start prüft die App `SystemLanguageModel.default.availability`; bei `unavailable` wird das Default-Backend automatisch auf OpenAI gestellt (sofern API-Key vorhanden) und der Modi-Tab zeigt eine deutsche Erklärung mit Link zu System-Einstellungen
  5. Recording-HUD bzw. Bestätigungs-Toast zeigt einen subtilen Indikator, welches Backend (Apple-Foundation / OpenAI) für den Rewrite verwendet wurde
**Plans**: 5 plans
- [x] 08-01-PLAN.md — Wave 0 Spike: Live-Verifikation A1/A2/A6 (LanguageModelSession Concurrency, GenerationError Cases, prewarm-Signature) — A1 verified, A2 + A6 corrected, Wave 1 unblocked (2026-05-04)
- [x] 08-02-PLAN.md — Wave 0 Foundation: Protocols (FoundationAvailabilityProviding, LanguageModelInferring) + DeescalatedOutput @Generable + AppleFoundationError + SettingsStore-Erweiterung (RewriteBackend, refreshFoundationAvailability, applyAutoFallbackIfNeeded self-idempotent) + Fakes + 7 AC-AVAIL-1/2 Tests, volle Suite 46/46 grün (2026-05-04)
- [x] 08-03-PLAN.md — Wave 1 Client + Dispatch: AppleFoundationRewriteClient (Plain + Guided) + ModeProcessor Backend-Lookup + 11 Tests in 2 Files (6 Client AC-AVAIL-1 + 5 Dispatch-Matrix inkl. Production-Pfad mit echtem Client) (2026-05-04)
- [x] 08-04-PLAN.md — Wave 2 UI: FoundationAvailabilityBanner (4 Varianten A/B/C + Auto-Fallback-Overlay D) + SettingsView Backend-Picker x 2 + APPLE INTELLIGENCE-Section + RecordingHUD BackendBadge (apple.logo / cloud) + Window-Width 268 + Show-while-Transcribing/Rewriting + AppDelegate Bootstrap-Refresh + Task.detached Pre-Warm (sync session.prewarm() per PIN(A6)) + didBecomeActiveNotification-Observer (AC-AVAIL-2); volle Suite 57/57 grün (2026-05-04)
- [x] 08-05-PLAN.md — Wave 3 Polish: README AC-AVAIL-3 Sektion (Apple Intelligence ≠ Siri + MDM-Realitätscheck) + volle Suite 3x consecutive grün ohne Flake (57/57; Run 1: 23s cold, Run 2: 8s, Run 3: 6s) + 08-VERIFICATION.md mit Phase-Gate-Sign-Off-Checkliste angelegt; Visual-UAT auf realer Apple-Intelligence-Hardware bleibt als 11-Item-Checkliste pending für User-Eintrag via /gsd-verify-phase 8 (2026-05-04)
**UI hint**: yes
**Context**: 08-CONTEXT.md (gathered 2026-05-01 als 999.7, promoted via /gsd-review-backlog)

### Phase 9: Vibe Coding — Variable Recognition
**Goal**: Beim Diktat in Code-Editoren wird gesprochene Coding-Convention automatisch in echtes Casing umgesetzt — User sagt "camel case foo bar" und bekommt `fooBar` eingefügt
**Depends on**: keine harten Deps (eigener Post-Processor-Slot zwischen Transkription und Rewrite — orthogonal zu Phase 8)
**Requirements**: keine v1-Mapping (milestone-erweiternd, neu)
**Success Criteria** (what must be TRUE):
  1. Neuer `TranscriptPostProcessor`-Step ("VariableCaseFormatter") liegt zwischen `TranscriptionService.Output` und `RewriteService.Input`; ein/auschaltbar via SettingsStore-Flag `vibeCoding.variableRecognition`
  2. Erkennt mindestens fünf Coding-Forms (camelCase, snake_case, kebab-case, PascalCase, CONSTANT_CASE) aus deutschen UND englischen Trigger-Wörtern ("camel case", "schlangen schreibweise", "snake case", "konstanten schreibweise", …)
  3. Ein neuer Settings-Tab/Section "Vibe Coding" zeigt den Toggle mit kurzer deutscher Erklärung und Beispiel-Mapping
  4. Heuristik ist durch Unit-Tests abgedeckt (mindestens je 3 Cases pro Coding-Form, inkl. mehrwortiger Identifier wie "fooBarBaz")
**Plans**: TBD
**UI hint**: yes

### Phase 10: Vibe Coding — File Tagging
**Goal**: Gesprochene Dateinamen wie "index dot tsx" oder "Audio Engine dot swift" werden zu `index.tsx` / `AudioEngine.swift`, damit das Diktat in Cursor-/Windsurf-/IDE-Chats direkt brauchbar ist
**Depends on**: Phase 9 (nutzt denselben Post-Processor-Slot und Casing-Heuristik)
**Requirements**: keine v1-Mapping (milestone-erweiternd, neu)
**Success Criteria** (what must be TRUE):
  1. Zweite Heuristik im Post-Processor erkennt Token-Sequenzen mit "dot/punkt + bekannte Datei-Endung" (.swift, .ts, .tsx, .js, .py, .md, .json, …) und kollabiert sie zu einem zusammenhängenden Filename-Token ohne Leerzeichen
  2. Mehrwort-Filenames erben Casing aus dem Variable-Recognition-Schritt (z. B. "audio engine dot swift" → `AudioEngine.swift` falls PascalCase getriggert wurde, sonst `audioengine.swift`)
  3. Toggle `vibeCoding.fileTagging` erscheint in derselben Settings-Section wie Phase 9 und ist unabhängig schaltbar
  4. Endungs-Whitelist ist in einer einzelnen Konstante zentral wartbar; keine ML-Komponente, rein deterministisch
**Plans**: TBD
**UI hint**: yes

### Phase 11: Auto-Cleanup-Levels + Undo-AI-Edit
**Goal**: User wählt für alle Diktate ein generelles Cleanup-Niveau (None / Light / Medium / High) auf Basis des bestehenden Rewrite-Backends; AI-Bearbeitungen sind reversibel, weil das Original-Transkript erhalten bleibt
**Depends on**: Phase 8 (nutzt Foundation/OpenAI-Backend-Auswahl als Engine)
**Requirements**: keine v1-Mapping (milestone-erweiternd, neu — entspricht Whispr-Flow "Auto Cleanup" mit Beta-Hinweis)
**Success Criteria** (what must be TRUE):
  1. Neuer Settings-Tab "Stil" enthält vier Auto-Cleanup-Karten (None/Light/Medium/High) mit deutschen Beschreibungen und je einem Mini-Beispiel-Vorher/Nachher
  2. Bei Pegel ≠ None wird nach jedem Standard-Diktat (kein Plus/Rant-Mode) automatisch ein Rewrite über das in Phase 8 ausgewählte Backend mit einem level-spezifischen Prompt-Preset ausgeführt, bevor in die Zwischenablage geschrieben wird
  3. Pro Diktat wird sowohl das Original-Transkript als auch der bearbeitete Text in einer In-Memory-History gespeichert (mind. letzte 20 Einträge); ein Status-Item-Menüpunkt "Letzte AI-Bearbeitung rückgängig" ersetzt den Clipboard-Inhalt durch das Original
  4. Cleanup-Level + Backend-Wahl werden im Recording-HUD-Toast subtil angezeigt (z. B. "Light · Foundation"), damit der User weiß, was passiert ist
  5. Bei Pegel "None" passiert garantiert kein Rewrite-Call und keine zusätzliche Latenz — Pfad ist explizit getestet
**Plans**: TBD
**UI hint**: yes

### Phase 12: Custom Vocabulary
**Goal**: User kann Eigennamen, Fachbegriffe und Abkürzungen pflegen, die Whisper/Parakeet zuverlässig korrekt transkribiert (z. B. "Parakeet", "DSGVO", "BlitzText")
**Depends on**: keine harten Deps (orthogonal zu allen anderen Phasen, aber baut idealerweise auf Phase 9 Post-Processor-Pipeline auf)
**Requirements**: keine v1-Mapping (milestone-erweiternd, neu)
**Success Criteria** (what must be TRUE):
  1. Neuer Settings-Tab "Wortschatz" zeigt eine Tabelle aller Custom-Vocabulary-Einträge (Original/Korrektur/Sprache); CRUD per UI; persistiert in `~/Library/Application Support/BlitzText/vocabulary.json`
  2. Beim Start jeder Whisper-/Parakeet-Aufnahme werden bis zu N (~30, modell-limit-aware) Einträge als initial-prompt mitgegeben; Längenlimit wird respektiert, ältester/seltenster Eintrag fliegt zuerst raus
  3. Post-Processor-Step "VocabularyCorrector" mappt häufige Whisper-Misshears (z. B. "Para Kit" → "Parakeet"); konfigurierbar pro Eintrag
  4. CRUD-Pfad und Initial-Prompt-Trimming sind durch Unit-Tests abgedeckt
**Plans**: TBD
**UI hint**: yes

### Phase 13: Experimental — Voice Commands
**Goal**: Am Ende eines Diktats erkannte Sprach-Kommandos ("neue Zeile", "Enter drücken", "lösche das letzte Wort") werden ausgeführt statt eingefügt — opt-in mit klarem Beta-Hinweis
**Depends on**: Phase 9 (Post-Processor-Pipeline existiert) — nutzt aber eigenen, nachgelagerten Slot vor Clipboard-Insert
**Requirements**: keine v1-Mapping (milestone-erweiternd, neu — entspricht Whispr-Flow "Experimental → Command Mode" + "Press Enter Command")
**Success Criteria** (what must be TRUE):
  1. Neuer Settings-Tab "Experimental" mit deutschem Warnhinweis ("kann sich ändern oder brechen"); enthält separate Toggles `commandMode` und `pressEnterCommand`
  2. Bei aktivem `commandMode` werden definierte Trigger-Phrasen am Ende des Transkripts erkannt und in Aktionen übersetzt: "neue Zeile" → `\n`, "lösche das" → Backspace x N, "Tab drücken" → `\t`
  3. Bei aktivem `pressEnterCommand` erkennt der Pipeline-Schritt isoliert das End-Token "Enter drücken" / "press enter" und löst nach Clipboard-Insert eine CGEvent-Enter-Synthese aus
  4. Conservative Match: Trigger-Phrase muss am exakten Ende des Transkripts stehen UND von einem kurzen Pausen-Marker (>200ms Stille im Audio-Buffer oder Satzzeichen) abgegrenzt sein, sonst kein Trigger
  5. Erkannte Commands erscheinen im HUD als kurze Bestätigung ("↵ Enter") bevor ausgeführt wird, damit Fehl-Trigger sichtbar sind
**Plans**: TBD
**UI hint**: yes

### Phase 14: Experimental — Bulk Import
**Goal**: User kann Custom-Vocabulary-Listen aus JSON/CSV importieren, statt Einträge einzeln in der UI anzulegen — gedacht für Onboarding und Team-Sharing
**Depends on**: Phase 12 (Vocabulary-Datenmodell muss existieren)
**Requirements**: keine v1-Mapping (milestone-erweiternd, neu — entspricht Whispr-Flow "Experimental → Bulk Import")
**Success Criteria** (what must be TRUE):
  1. Settings-Tab "Experimental" zeigt einen "Wortschatz importieren…"-Button (sichtbar nur wenn Phase 12 Vocabulary-Tab existiert)
  2. NSOpenPanel öffnet einen Datei-Picker für `.json` und `.csv`; Schema ist in der App-Hilfe / README dokumentiert (Spalten: original, replacement, language)
  3. Import zeigt eine Vorschau (X Einträge gefunden, Y Duplikate, Z Konflikte) und erlaubt "Nur neue importieren" / "Alle überschreiben" / "Abbrechen"
  4. Fehlerhafte Zeilen werden zeilenweise mit deutschem Fehler-Hinweis aufgelistet, kein All-or-Nothing-Abbruch
**Plans**: TBD
**UI hint**: yes

### Phase 15: System-Polish & QoL
**Goal**: BlitzText verhält sich als gut integrierte macOS-Menu-Bar-App — Login-Item-Integration, optionale Dock-Sichtbarkeit, abschaltbare Sounds, Audio-Ducking während Aufnahme
**Depends on**: keine harten Deps
**Requirements**: keine v1-Mapping (milestone-erweiternd, neu)
**Success Criteria** (what must be TRUE):
  1. Settings-Tab "System" enthält die Toggles `launchAtLogin`, `showInDock`, `dictationSounds`, `muteMusicWhileDictating`
  2. `launchAtLogin` registriert/entfernt das Login-Item via `SMAppService` (macOS 13+) und persistiert den Soll-Zustand in SettingsStore
  3. `showInDock`-Toggle wechselt zur Laufzeit zwischen `LSUIElement` und Dock-App-Verhalten (Activation-Policy-Switch); Status-Item bleibt in beiden Fällen sichtbar
  4. `dictationSounds` schaltet Start-/Stop-/Confirm-Sounds zentral ein/aus (Default an); Sounds liegen als bundelte Ressourcen vor
  5. `muteMusicWhileDictating` duckt während aktiver Aufnahme Audio anderer Apps via `AVAudioSession`/CoreAudio-Approach (oder via Media-Keys-Pause als Fallback) und stellt nach Aufnahme den vorherigen Zustand wieder her
**Plans**: TBD
**UI hint**: yes

### Phase 16: Sprecher-Sample-Wiedergabe

**Goal**: Unbekannte Sprecher aus dem letzten Transkript lassen sich durch Anhören ihrer Audio-Fragmente identifizieren und direkt benennen

**Depends on**: Phase 6 (Enrollment — Profil-Anlage muss existieren), Phase 5 (Sprecher-Tab als UI-Anker)

**Requirements**: keine v1-Mapping (milestone-erweiternd, neu)

**Success Criteria** (what must be TRUE):

  1. Nach jeder Aufnahme mit Diarization werden die Audio-Segmente pro Sprecher-ID (WAV/PCM-Slices) temporär in einem In-Memory-Buffer oder einer kurzlebigen Temp-Datei behalten — spätestens bis zur nächsten Aufnahme
  2. Im Sprecher-Tab erscheint für Sprecher aus dem letzten Transkript ein Play-Button (▶) — ein Klick spielt die gespeicherten Segmente dieses Sprechers nacheinander ab (AVAudioPlayer oder AVAudioEngine)
  3. Direkt neben dem Play-Button liegt das bestehende Name-zuweisen-Widget (SPK-06), sodass der User nach dem Anhören sofort benennen kann — kein Fokuswechsel nötig
  4. Sind keine Audio-Segmente mehr verfügbar (neue Aufnahme gestartet, App-Neustart), ist der Play-Button deaktiviert mit Tooltip "Nur für letzte Aufnahme verfügbar"
  5. Kein Audio-Segment wird je auf Disk persistiert (DSGVO Art. 9 — Stimme ist biometrisches Datum); In-Memory-only, Freigabe nach Aufnahme-Wechsel

**Plans**: TBD
**UI hint**: yes

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
| 1. Stabilisierung & Doku-Drift | 4/4 | Complete | 2026-04-30 |
| 2. Test-Fundament | 3/3 | Complete | 2026-05-01 |
| 3. Diarization-UX | 0/0 | Not started | - |
| 4. Sprecher-Profile Core | 0/0 | Not started | - |
| 5. Sprecher-Profile UI | 0/0 | Not started | - |
| 6. Sprecher-Enrollment | 3/3 | Executed (UAT pending) | 2026-05-18 |
| 7. Standard-Hotkeys & eigene Hotkeys | 5/5 | Complete   | 2026-05-19 |
| 8. Apple Foundation Rewrite-Backend | 9/9 | Complete   | 2026-05-04 |
| 9. Vibe Coding — Variable Recognition | 0/0 | Not started | - |
| 10. Vibe Coding — File Tagging | 0/0 | Not started | - |
| 11. Auto-Cleanup-Levels + Undo-AI-Edit | 0/0 | Not started | - |
| 12. Custom Vocabulary | 0/0 | Not started | - |
| 13. Experimental — Voice Commands | 0/0 | Not started | - |
| 14. Experimental — Bulk Import | 0/0 | Not started | - |
| 15. System-Polish & QoL | 0/0 | Not started | - |
| 16. Sprecher-Sample-Wiedergabe | 0/0 | Not started | - |
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
| Phase 8 | — (milestone-erweiternd, kein v1-Requirement; promoted aus Backlog 999.7) |
| Phase 9 | — (milestone-erweiternd, neu — Vibe Coding inspiriert von Whispr Flow) |
| Phase 10 | — (milestone-erweiternd, neu — Vibe Coding inspiriert von Whispr Flow) |
| Phase 11 | — (milestone-erweiternd, neu — Auto-Cleanup-Style-Presets baut auf Phase 8) |
| Phase 12 | — (milestone-erweiternd, neu — Custom Vocabulary) |
| Phase 13 | — (milestone-erweiternd, neu — Experimental Voice Commands) |
| Phase 14 | — (milestone-erweiternd, neu — Experimental Bulk Import, baut auf Phase 12) |
| Phase 15 | — (milestone-erweiternd, neu — System-Polish & QoL) |

**Note on TEST-03 placement:** TEST-03 (Sprecher-Profil-Matching-Tests) lebt in Phase 4 statt Phase 2, weil die zu testenden Komponenten (Persistenz, EMA-Update, Threshold-Matching) erst in Phase 4 entstehen. Phase 2 etabliert das Test-Target und deckt Hotkey + Pipeline-Fehlerpfade ab; Phase 4 erweitert die Suite parallel zur Implementierung.

---
*Roadmap erstellt: 2026-04-30*
