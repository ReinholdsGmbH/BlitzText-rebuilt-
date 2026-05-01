# Phase 999.7 Discussion Log

**Date:** 2026-05-01
**Workflow:** /gsd-discuss-phase 999.7
**Mode:** default (4 Bereiche, single-question turns)

## Bereichsauswahl

**Frage:** Welche Bereiche möchtest du für Phase 999.7 diskutieren?
**Optionen:** Backend-Strategie · Modell-Capability & Modes · Foundation-API-Auswahl · Verfügbarkeit & UX
**Auswahl:** alle vier

## Bereich 1: Backend-Strategie

**Frage:** Wie soll Foundation Models im Verhältnis zum bestehenden OpenAI-Backend laufen?
- Optionen: Zusätzliche Auswahl · Komplett ersetzen · Auto-Hybrid mit Fallback · Foundation-Default mit User-Override
- **Auswahl:** Foundation-Default mit User-Override (kein automatischer Fallback — Privacy-Markenversprechen kompromisslos)

## Bereich 2: Modell-Capability & Modes

**Frage:** Welche Rewrite-Modes sollen Foundation Models nutzen dürfen?
- Optionen: Beide Modes einheitlich · Pro Mode wählbar · Erstmal nur Plus
- **Auswahl:** Pro Mode wählbar (User kalibriert Foundation vs. OpenAI separat für Plus und Rant)

## Bereich 3: Foundation-API-Auswahl

**Frage:** Welche Foundation-Models-API soll genutzt werden?
- Optionen: Plain LanguageModelSession · Guided Generation · Beides je nach Mode
- **Auswahl:** Beides je nach Mode (Plus = Plain Session, Rant = Guided Generation mit Schema)

## Bereich 4: Verfügbarkeit & UX

**Frage 1:** Wie soll die App mit Verfügbarkeit von Foundation Models umgehen?
- Optionen: Start-Check · Lazy-Check · Beides
- **Auswahl:** Verfügbarkeitscheck beim App-Start (mit Auto-Default-Korrektur auf OpenAI bei unavailable, sofern API-Key vorhanden)

**Frage 2:** Soll der User pro Aufnahme sehen, welches Backend genutzt wurde?
- Optionen: Transparent · Subtiler HUD-Indikator · Nur in History
- **Auswahl:** Subtiler Indikator im HUD (Privacy-Markenversprechen sichtbar machen)

## Deferred Ideas

- Apple Foundation für Meeting-Zusammenfassungen — separate Phase 999.3
- Foundation für Translation (999.4/999.5) — könnte profitieren, Reihenfolge offen
- Latenz-/Telemetry-Vergleich der Backends — passt zu v2-Requirement PERF-02

## Notes

- Phase ist BACKLOG (999.x). Plans existieren noch nicht.
- Researcher hat technische Fragen einzulösen: Swift-6-Concurrency-Kompatibilität von `SystemLanguageModel`/`LanguageModelSession`, deutsche Prompt-Bias-Tests, Cold-Start-Latenz, `@Generable`-Schema-Robustheit, `availability`-API-Granularität (nicht-heruntergeladen vs. endgültig-nicht-verfügbar).
- Wichtig: Live-Doku zu Apple FoundationModels-Framework lesen — Trainingsdaten zu dieser API sind unzuverlässig.
