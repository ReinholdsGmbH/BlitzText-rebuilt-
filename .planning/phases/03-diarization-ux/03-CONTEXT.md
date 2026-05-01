# Phase 3: Diarization-UX — Context

**Gathered:** 2026-05-01
**Status:** Ready for UI-Phase + Planning
**Source:** `/gsd-discuss-phase 3` (chained mit `/gsd-ui-phase 3` + `/gsd-plan-phase 3 --chain`)

<domain>
## Phase Boundary

Diarization-Modell-Download (`DiarizerModels.downloadIfNeeded()` in FluidAudio, ~80 MB) wird im Settings-Tab **sichtbar**, **fehlerfest** und **vom Nutzer kontrollierbar**. Heute ist der Download opak (siehe `CONCERNS.md` P1, [`ParakeetClient.swift:131-138`](../../../BlitzText/Transcription/ParakeetClient.swift)) und blockiert die nächste Aufnahme stumm.

**In Scope:**
- Progress-UI im Settings-Tab: Prozent + ungefähre Restzeit
- Deutsche Fehlermeldung mit Retry-Button
- Toggle-Zustand reflektiert Lade-Phase ("wird geladen" / "bereit" / "Fehler")
- Pre-Warm beim App-Start, wenn `parakeetDiarization=true` persistiert war
- Eigener Downloader analog `LocalModelManager` (volle Progress-Kontrolle)

**Out of Scope (eigene Phasen / Backlog):**
- Persistente Sprecher-Profile (`SPK-01..03` → Phase 4)
- Sprecher-Verwaltung (Umbenennen, Mergen, Permanent) → Phase 5
- Erst-Enrollment-Flow → Phase 6
- Lösch-Button für Diarizer-Modell (analog WhisperKit-Models) → Backlog
- Andere Diarization-Backends als FluidAudio
</domain>

<decisions>
## Implementation Decisions

### Download-Trigger
- **D-01:** Download startet **sofort bei Toggle-On** (`parakeetDiarization` flippt in `SettingsStore` von `false` → `true`). Nicht lazy bei nächster Aufnahme.
- **D-02:** Wenn das Modell bereits lokal vorhanden ist, ist Toggle-On ein No-Op-Download (Status: bereit) — kein erneutes Herunterladen.

### Toggle- & Block-Verhalten während Download
- **D-03:** Während aktivem Download wird der **Toggle visuell durch ein Status-Label ersetzt** ("Lädt Diarizer-Modell …") inklusive Progress-Bar mit Prozent + ungefährer Restzeit. Toggle erscheint erst wieder nach erfolgreichem Download (oder nach Fehler im Retry-State).
- **D-04:** Kein Cancel während Download in v1. Wenn der User den Download zwingend abbrechen will: App neu starten → State wird beim nächsten Toggle-On neu evaluiert. (Cancel kann in Backlog wandern, wenn das im Test als störend auffällt.)
- **D-05:** Bei `parakeetDiarization=true` aber **fehlendem oder unvollständigem Modell** zeigt der Block den Lade-/Fehler-State, **nicht** den aktiven Toggle.

### Progress-Quelle
- **D-06:** Eigener Downloader analog `LocalModelManager` + `ModelDownloader.swift`. Wir umgehen `DiarizerModels.downloadIfNeeded()` und ziehen die FluidAudio-Modelldateien selbst per `URLSession`. Persistenz unter `~/Library/Application Support/BlitzText/Models/Diarizer/` (analog `Models/<whisperVariant>/`).
- **D-07:** Researcher-Aufgabe: konkrete URLs/Hashes der `DiarizerModels`-Pakete aus FluidAudio extrahieren (Source-Code-Inspektion, nicht raten). Falls die URL-Liste sich zwischen FluidAudio-Versionen ändert, dokumentieren wo das pinned wird.
- **D-08:** Restzeit-Schätzung via gleitendem Durchschnitt der Bytes/Sekunde (analog Standard-Pattern; konkrete Implementierungswahl bleibt Planner überlassen).

### Fehler-Handling & Retry
- **D-09:** Fehlerzustände werden in einem neuen `DiarizerModelManager.lastError: String?` (`@Published`) gehalten — analog `LocalModelManager.lastError`.
- **D-10:** Fehler-Block zeigt: deutsche Fehlermeldung (drei Klassen reichen für v1: Netzwerk / Speicher / unbekannt), Retry-Button. Kein automatischer Retry mit Backoff in v1 — User-getriggert.
- **D-11:** Retry startet denselben Download neu; partielle Dateien werden vorher gelöscht (kein Resume-Versuch in v1).
- **D-12:** Wenn `parakeetDiarization` bei Fehler weiterhin `true` bleibt, zeigt UI klar den Fehlerstand. Der Toggle-State wird **nicht** automatisch auf `false` gesetzt — User-Intent bleibt erhalten.

### Pre-Warm beim App-Start
- **D-13:** In `AppDelegate.bootstrap()`: wenn `settings.parakeetDiarization == true`, prüft die App, ob das Diarizer-Modell vollständig im Models-Verzeichnis liegt.
  - Vorhanden → Hintergrund-Pre-Warm der `DiarizerManager`-Instanz (kein Download, nur CoreML-Init), **nicht blockierend**.
  - Fehlt → Hintergrund-Download mit Progress (UI ist nicht offen, aber Status wird geupdatet, sodass Settings beim Öffnen sofort den richtigen Stand zeigt).
- **D-14:** Pre-Warm ist best-effort: Fehler im Pre-Warm setzen `lastError`, aber der App-Start blockiert nie. Erst-Recording mit fehlendem Modell zeigt weiterhin existierende Fehlermeldung in `ParakeetClient.transcribe`.

### State-Machine (zentrales Diarizer-Lifecycle-Modell)
- **D-15:** Ein neuer Manager — Arbeitstitel `DiarizerModelManager` (`@MainActor`, `ObservableObject`) — kapselt den Diarizer-Lifecycle. Schema:
  - `state: DiarizerModelState` mit Cases `notInstalled`, `downloading(progress: Double, etaSec: Double?)`, `installed`, `failed(message: String)`
  - `@Published downloadProgress: Double?`, `@Published etaSeconds: Double?`, `@Published lastError: String?`
  - Methoden: `start()`, `retry()`, `isInstalled` Sync-Check, `prewarm()` für AppDelegate
- **D-16:** `ParakeetClient.ensureLoaded()` ([Zeile 117](../../../BlitzText/Transcription/ParakeetClient.swift)) konsultiert `DiarizerModelManager.isInstalled` statt selbst `DiarizerModels.downloadIfNeeded()` aufzurufen. Wenn nicht installiert → Diarizer bleibt `nil` und Transcript fällt auf reines ASR zurück (status quo bei Fehler).

### Settings-UI-Struktur
- **D-17:** Diarization-Block bleibt im bestehenden Tab/Bereich, in dem heute der Toggle lebt (laut Code: `SettingsView.swift:382-388`, im Parakeet-Bereich). Block wächst um Progress + Status + Retry — kein eigener Tab.
- **D-18:** Status-Pill / Inline-Indikator zeigt einen von vier Zuständen: (a) Toggle aktiv "Sprechererkennung (Diarization)", (b) "Lädt Diarizer-Modell — 42 % · noch ~30 s", (c) "Modell vorhanden ✓", (d) Fehler-Block mit Retry. Konkrete UI-Form in `/gsd-ui-phase 3` (UI-SPEC).

### Claude's Discretion
- Genauer SF-Symbol für Status (Vorschlag: `arrow.down.circle` während Download, `checkmark.circle.fill` bei installiert, `exclamationmark.triangle.fill` bei Fehler) — UI-Phase entscheidet.
- ETA-Algorithmus (gleitender Durchschnitt vs. instantane Rate) — Planner.
- Genauer Wortlaut der drei Fehler-Klassen — Planner.
- Throttling der Progress-Updates (z.B. max 30 Hz) — Planner.
</decisions>

<specifics>
## Spezifische Referenzen

- **`LocalModelManager` ist die Vorlage** ([Zeile 50-60](../../../BlitzText/Transcription/LocalModelManager.swift), [Zeile 138-168](../../../BlitzText/Transcription/LocalModelManager.swift)): `@Published downloadProgress`, `@Published lastError`, `download(_)` mit URLSession-Progress-Callback, `cancelDownload(_)`, dedizierter Folder pro Modell. Diarizer-Manager soll **strukturell** dasselbe Muster fahren — gleiche API-Form, eigene Datenstruktur (es gibt nur ein Diarizer-Modell, nicht eine Liste).
- **Schmerzpunkt zitiert wörtlich** aus `CONCERNS.md`: "Diarization model download is ~80 MB and silent (P1, UX)" — Phase 3 schließt diesen Punkt.
- "Sofortiger Download bei Toggle-On" wurde gewählt, weil das User-Mental-Modell konsistent mit "Toggle = Aktion" ist und das aktuelle "stumm bei nächster Aufnahme"-Verhalten genau der dokumentierte Schmerzpunkt ist.
- **Status-Label statt disabletem Toggle** wurde gewählt: maximale Klarheit über den Lade-Zustand. Trade-off: Mehr UI-Code, aber kein "Toggle ist on, aber nichts passiert"-Missverständnis.
</specifics>

<canonical_refs>
## Canonical References

**Downstream-Agents (Researcher, UI-Researcher, Planner) MÜSSEN diese Dateien lesen.**

### Projekt-Kontrakte
- [.planning/ROADMAP.md](../../ROADMAP.md) — Phase 3 Eintrag: Goal + Success Criteria + DIA-01/DIA-02 Mapping
- [.planning/REQUIREMENTS.md](../../REQUIREMENTS.md) — DIA-01 (Progress + Restzeit, ~80 MB) und DIA-02 (deutsche Fehlermeldung + Retry)
- [.planning/PROJECT.md](../../PROJECT.md) — Privacy-Markenversprechen (lokal, kein Cloud-Service), Performance-Constraint (≤ 3 s end-to-end)

### Codebase-Kartierung
- [.planning/codebase/ARCHITECTURE.md](../../codebase/ARCHITECTURE.md) §"Component Responsibilities" und §"Settings / Model-Activation Flow" — `LocalModelManager`-Pattern als Vorlage
- [.planning/codebase/CONCERNS.md](../../codebase/CONCERNS.md) §"Diarization model download is ~80 MB and silent (P1, UX)" — Schmerzpunkt, den diese Phase schließt
- [.planning/codebase/CONVENTIONS.md](../../codebase/CONVENTIONS.md) — Naming + SwiftUI-Patterns
- [.planning/codebase/STACK.md](../../codebase/STACK.md) — Swift 6 strict-concurrency: minimal

### Code-Dateien (must read)
- [BlitzText/Transcription/ParakeetClient.swift](../../../BlitzText/Transcription/ParakeetClient.swift) — heutiger opaker Aufruf von `DiarizerModels.downloadIfNeeded()` in `ensureLoaded()` (Zeile 117-147); `parakeetDiarization`-Setting wird hier gelesen
- [BlitzText/Transcription/LocalModelManager.swift](../../../BlitzText/Transcription/LocalModelManager.swift) — **Strukturelle Vorlage** für `DiarizerModelManager`: `@Published downloadProgress`, `lastError`, Download-Lifecycle
- [BlitzText/Transcription/ModelDownloader.swift](../../../BlitzText/Transcription/ModelDownloader.swift) — bestehender HTTP-Download-Helper mit Progress-Callback; ggf. erweitern oder analog für Diarizer-URL-Set
- [BlitzText/Settings/SettingsStore.swift](../../../BlitzText/Settings/SettingsStore.swift) — `parakeetDiarization: Bool` (Zeile 22, 90, 110, 127); Snapshot-Pattern; Toggle-Flip löst Download-Trigger aus
- [BlitzText/Settings/SettingsView.swift](../../../BlitzText/Settings/SettingsView.swift) — Diarization-Toggle aktuell bei Zeile 385; UI-Erweiterung dort
- [BlitzText/App/AppDelegate.swift](../../../BlitzText/App/AppDelegate.swift) — `bootstrap()`; `preloadLocalModelIfActive`-Pattern als Vorlage für `prewarmDiarizerIfActive`
- [BlitzText/App/Log.swift](../../../BlitzText/App/Log.swift) — Logger; Diarizer-Manager nutzt denselben

### Externe Doku (Researcher liest live)
- **FluidAudio Source / Repo** — konkrete URL-Liste und SHA der `DiarizerModels`-Dateien; ohne Live-Inspektion keine zuverlässige Pin-Liste
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`LocalModelManager.download(_)`-Pattern** ([Zeile 138-168](../../../BlitzText/Transcription/LocalModelManager.swift)): identische Mechanik (Task, Progress-Callback im 0…1-Bereich, Error-State, Cleanup) — neuer `DiarizerModelManager` kopiert diese Struktur fast 1:1, mit angepasster Datenform (single model statt Map).
- **`ModelDownloader.downloadWhisperKitModel`**: existierender HTTP-Downloader mit Progress-Callback. Researcher prüft, ob er für Diarizer-URLs adaptierbar ist oder ob ein zweiter Helper sinnvoller ist (Diarizer ist evtl. mehrere Dateien, nicht ein Package).
- **`SettingsStore.Snapshot`-Pattern**: keine Schema-Änderung nötig — `parakeetDiarization` existiert bereits. Nur Side-Effect (Toggle-Flip → Download) ist neu.
- **`AppDelegate.preloadLocalModelIfActive`**: Vorlage für `prewarmDiarizerIfActive`; `onActivate`-Callback-Idee aus `LocalModelManager` ist auch übertragbar.
- **`Log.write(_)`**: alle Subsysteme nutzen denselben File-Logger — Diarizer-Manager loggt `Parakeet/Diarizer:`-prefixed Lines analog `ParakeetClient`.

### Established Patterns
- **`@MainActor` `ObservableObject`** für Modell-Lifecycle-Manager (`LocalModelManager` ist die Referenz). `DiarizerModelManager` muss `@MainActor` sein, damit `@Published` nahtlos in SwiftUI funktioniert.
- **Snapshot-Save mit Debounce 150 ms**: schon vorhanden in `SettingsStore` — keine Änderung.
- **`@unchecked Sendable` für Service-Klassen mit C-Callbacks**: nicht für Manager nötig (kein C-Boundary), aber `URLSessionDelegate` kann es erfordern.
- **Lazy-Init der Backends in `ModeProcessor`**: `DiarizerModelManager` wird **früh in `AppDelegate.bootstrap`** instanziiert (für Pre-Warm), nicht lazy in `ParakeetClient`. `ParakeetClient` bekommt eine Referenz injiziert (DI-Style, analog `RecorderProtocol`-Seam aus Phase 2).

### Integration Points
- **`AppDelegate.bootstrap`**: `DiarizerModelManager` instanziieren; wenn `settings.parakeetDiarization` → `prewarm()`. Manager wird in `ParakeetClient` und `SettingsView` injiziert.
- **`SettingsStore.parakeetDiarization` setter**: Side-Effect-Hook für Toggle-Flip (`false → true` startet Download via Manager). Achtung: Snapshot-Save ist debounced — Side-Effect direkt am `didSet` der `@Published`-Property hängen, nicht am Snapshot.
- **`ParakeetClient.ensureLoaded` (Zeile 117)**: ersetzt `try await DiarizerModels.downloadIfNeeded()` durch ein `await diarizerModelManager.ensureInstalled()`. Wenn nicht installiert/fehlerhaft → `self.diarizer = nil`, ASR läuft trotzdem weiter.
- **`SettingsView.swift:380-388`**: bestehender Diarization-Toggle-Block. UI-Phase 3 konkretisiert hier den neuen Block: Toggle-or-Status-Label + Progress + Status-Pill + Fehler-Block + Retry-Button.

### Risks / Landmines
- **FluidAudio-Versionspinning**: Wir umgehen `DiarizerModels.downloadIfNeeded()` und sind dadurch von der internen URL-Liste der FluidAudio-Version abhängig. Researcher dokumentiert SemVer-Lock + welche FluidAudio-Variable die URLs hält. Bei FluidAudio-Update kann sich das ändern.
- **Speicherort-Konflikt**: Wenn FluidAudio das Modell selbst irgendwohin lädt (Cache-Verzeichnis), könnten zwei Kopien existieren. Researcher prüft, ob unsere Kopie nach `~/Library/Application Support/BlitzText/Models/Diarizer/` von FluidAudios `DiarizerModels(localPath:)`-API gelesen werden kann.
- **Swift-6-Concurrency**: `DiarizerModelManager` ist `@MainActor`. `URLSessionDelegate`-Callbacks landen auf einem `URLSession`-Thread → `Task { @MainActor in … }`-Hop für Progress-Update (Pattern in `LocalModelManager:151-154`).
- **Pre-Warm bei Offline-Start**: Wenn App offline startet und Modell fehlt, soll Pre-Warm **nicht** störend retryen. Einmal-Versuch, Fehler in `lastError`, Settings-UI zeigt es beim Öffnen.
- **Race: Toggle-Off während Download**: Wenn User Toggle-Off klickt während Download läuft (technisch möglich, weil Toggle wird zu Status-Label — aber falls Block doch interaktiv): Download muss sauber abgebrochen + partielle Dateien gelöscht werden. Da v1 keinen Cancel hat, ist Toggle wirklich nur ein read-only-Status-Label während Download.
- **Disk-Space-Check**: ~80 MB Download — kein expliziter Pre-Check in v1, aber Fehlermeldung muss "Speicher voll"-Variante abdecken (kommt aus URLSession-Error-Domain).
</code_context>

<deferred>
## Deferred Ideas

Während der Diskussion erwähnt oder implizit gestreift, aber außerhalb der Phase-Boundary:

- **Lösch-Button für Diarizer-Modell** — analog WhisperKit-Modelle (`LocalModelManager.delete`). Nicht Teil von Phase 3. Backlog: separate Phase oder Erweiterung zusammen mit "Settings-Hygiene".
- **Cancel-Button während Download** — bewusst aus v1 ausgeschlossen (D-04). Wenn UAT zeigt, dass es störend fehlt: in Backlog promoten.
- **Auto-Retry mit Backoff** — bewusst aus v1 ausgeschlossen (D-10). User-getriggertes Retry reicht für Stabilisierungs-Phase.
- **Download-Resume nach Abbruch** — partielle Dateien werden bei Retry gelöscht (D-11). Resume wäre Komfort, nicht Stabilisierung.
- **Modell-Version-Anzeige in UI** — "Diarizer-Modell v3.2.1, 80,4 MB" wäre nice-to-have, ist aber Verwaltung, nicht UX-Stabilisierung. Backlog.
- **Sandbox-kompatibler Download-Pfad** — wenn Sandbox später aktiviert wird, muss der Download-Pfad ggf. ins Sandbox-Container. Out of Scope dieser Milestone.
</deferred>

---

*Phase: 03-diarization-ux*
*Context gathered: 2026-05-01 via /gsd-discuss-phase 3 (chained mit /gsd-ui-phase + /gsd-plan-phase)*
