# Phase 3: Diarization-UX — Discussion Log

**Date:** 2026-05-01
**Mode:** discuss (chained mit `/gsd-ui-phase 3` + `/gsd-plan-phase 3 --chain`)
**Loaded prior context:** PROJECT.md, REQUIREMENTS.md, STATE.md, ROADMAP.md, codebase/{ARCHITECTURE,CONCERNS}.md, Phase 7 + Phase 8 CONTEXT.md (für Stil-Konsistenz)
**No SPEC.md** für Phase 3 (Phase ist Direkt-Planning ohne Spec-Refinement)

## Phase Boundary

Diarizer-Modell-Download (~80 MB FluidAudio `DiarizerModels`) im Settings-Tab sichtbar machen, fehlerfest gestalten und kontrollierbar — ohne neuen Diarization-Algorithmus, ohne Sprecher-Profile (Phase 4), ohne Verwaltungsoberfläche (Phase 5).

## Gray Areas presented

Vier domain-spezifische Gray Areas wurden gemeinsam in einer AskUserQuestion-Runde gestellt (Batch wegen klarer, voneinander unabhängiger Fragen):

### 1. Download-Trigger (Header: "Trigger")

**Frage:** Wann soll der Diarizer-Download tatsächlich starten?

| Option | Beschreibung |
|---|---|
| ✅ **Sofort bei Toggle-On** *(Recommended)* | Toggle-On in Settings ist die klarste Intent-Aktion → Download startet sofort, sichtbar im Settings-Tab. Heute-Verhalten (lazy bei Aufnahme) ist genau der Schmerzpunkt aus CONCERNS.md. |
| Erst bei nächster Aufnahme (status quo) | Heute-Verhalten beibehalten, aber jetzt mit Progress-UI. Risiko: Recording-HUD zeigt Wartepause beim Erst-Use. |
| Dedizierter Lade-Button vor Toggle | Toggle disabled bis User „Modell laden"-Button klickt. Mehr Friktion, maximal klar. |

**User-Entscheidung:** **Sofort bei Toggle-On (Recommended)** — gewählt.

### 2. Toggle-State während Download (Header: "Toggle-State")

**Frage:** Wie verhält sich der Toggle und der Diarization-Block, solange das Modell lädt?

| Option | Beschreibung |
|---|---|
| Toggle disabled + inline Progress *(Recommended)* | Toggle bleibt visuell on aber disabled (grayed out), darunter Progress-Bar. Konsistent mit anderen Settings-UIs, kein Cancel in v1. |
| Toggle bleibt aktiv + Cancel-Button | User kann während Download abbrechen. Mehr Kontrolle, komplexere State-Machine. |
| ✅ **Toggle wird zu „Lädt …"-Status-Label** | Toggle visuell ersetzt durch Progress + Status — Toggle erscheint erst wieder nach erfolgreichem Download. Klarste Optik, aber inkonsistent mit Rest der Settings-UI. |

**User-Entscheidung:** **Toggle wird zu „Lädt …"-Status-Label** — bewusst NICHT die Recommended-Option. Begründung implizit: maximale Klarheit über den Lade-Zustand, kein "Toggle ist on, aber nichts passiert"-Missverständnis. Trade-off: mehr UI-Code, aber State ist absolut eindeutig sichtbar.

**Folgerung für Plan:** UI-Block hat zwei sichtbare Hauptzustände — (a) Toggle-Modus, (b) Status-Label-Modus. Übergang ist conditionally-gerendert in `SettingsView`.

### 3. Progress-Quelle (Header: "Progress-API")

**Frage:** Woher kommen die Progress-Werte (Prozent + Restzeit)?

| Option | Beschreibung |
|---|---|
| ✅ **Eigener Downloader analog `LocalModelManager`** *(Recommended)* | Wir laden die DiarizerModels-Dateien selbst per ModelDownloader, bekommen echten URLSession-Progress, persistieren unter `~/Library/Application Support/BlitzText/Models/Diarizer/`. Konsistent mit Whisper-Pfad. |
| FluidAudio-API nutzen, falls Progress-Callback existiert | `DiarizerModels.downloadIfNeeded()` ist heute opak — vielleicht progressive Variante. Researcher klärt. |
| Indeterminate Spinner als Fallback | Nur Spinner + Erklär-Text. Verletzt aber DIA-01 explizit (Prozent + Restzeit gefordert). |

**User-Entscheidung:** **Eigener Downloader analog `LocalModelManager` (Recommended)** — gewählt.

**Researcher-Folge-Aufgabe:** Konkrete URLs/Hashes der `DiarizerModels`-Pakete aus FluidAudio-Source extrahieren. Pin-Strategie dokumentieren (welche FluidAudio-Variable hält die URL-Liste).

### 4. Modell-Verwaltung (Header: "Verwaltung")

**Frage:** Wie weit soll die Modell-Verwaltung gehen?

| Option | Beschreibung |
|---|---|
| Nur Download + Retry + Status *(Recommended)* | Phase-Boundary streng: Toggle, Progress, Fehler, Retry, Status „Modell vorhanden ✓". Kein Lösch-Button. |
| Auch Lösch-Button + Speicherort-Anzeige | Analog WhisperKit-Modelle. Konsistenz, aber Scope wächst. |
| ✅ **Plus Pre-Warm beim App-Start** | Wenn `parakeetDiarization=on` persistiert war, lädt App beim Start im Hintergrund (analog `preloadLocalModelIfActive`). Erstes Recording fühlt sich schneller an. |

**User-Entscheidung:** **Plus Pre-Warm beim App-Start** — gewählt. Lösch-Button bleibt deferred (in `<deferred>` festgehalten).

**Folgerung für Plan:** `AppDelegate.bootstrap()` bekommt einen `prewarmDiarizerIfActive`-Pfad analog `preloadLocalModelIfActive`. `DiarizerModelManager` wird früh instanziiert.

## Scope creep redirected

Während der Discussion **kein** Scope-Creep aufgetreten — alle Optionen blieben innerhalb der Domain-Boundary "Modell-Download-UX". Lösch-Button und Cancel-Button wurden in `<deferred>` gehalten, falls UAT sie als störend fehlend identifiziert.

## Claude's Discretion

Folgende Detailentscheidungen wurden ausdrücklich nicht gefragt und sind Planner-Domäne:

- SF-Symbol-Wahl für Status-Indikator
- Konkreter ETA-Algorithmus (gleitender Durchschnitt vs. instantane Rate)
- Wortlaut der drei Fehlerklassen (Netzwerk / Speicher / unbekannt)
- Throttling der Progress-Updates (Hz)
- Folder-Layout innerhalb `Models/Diarizer/` (eine Datei vs. Ordner-Bundle)

## Outcome

CONTEXT.md erfasst 18 Implementation Decisions (D-01..D-18) gegliedert in 7 Bereiche. Phase ist bereit für `/gsd-ui-phase 3` (UI-SPEC) gefolgt von `/gsd-plan-phase 3` (PLAN.md).

---
*Discussion log: 2026-05-01*
