# Project State: BlitzText

**Last updated:** 2026-04-30

## Project Reference

**Core Value:** Vom gedrückten Hotkey bis zum eingefügten Text wenige Sekunden — Text muss benutzbar sein, ohne nachzubearbeiten.

**Current Focus:** Milestone "Sprecher-Profile + Stabilisierung" — bestehende Tech-Schuld schließen, Test-Fundament legen, persistente lokale Sprecher-Profile auf Basis von FluidAudios `SpeakerManager` einführen.

## Current Position

- **Milestone:** Sprecher-Profile + Stabilisierung
- **Phase:** Pre-Phase 1 (Roadmap erstellt, noch nicht geplant)
- **Plan:** —
- **Status:** Ready for `/gsd-plan-phase 1`
- **Progress:** 0/6 phases complete

```
[░░░░░░░░░░░░░░░░░░░░] 0% (0/6 phases)
```

## Performance Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Hotkey-Release → Clipboard (5–15 s Audio) | ≤ 3 s | nicht gemessen |
| Diarization-Modell-Download | sichtbar mit Progress | unsichtbar (Phase 3 fix) |
| Test-Coverage Hotkey + Pipeline | ≥ 1 grüner Test pro Pfad | 0 (kein Test-Target) |

## Accumulated Context

### Decisions

- Sprecher-Erkennung lokal über FluidAudio `SpeakerManager` (kein Cloud-Service) — Datenschutz + bestehende API
- Persistenz als JSON in `~/Library/Application Support/BlitzText/speakers.json` (analog zu `history.json`)
- Sandbox bleibt aus dieser Milestone draußen — separate Initiative
- TEST-03 (Sprecher-Matching-Tests) wandert von Phase 2 zu Phase 4, weil Code dort entsteht

### Open Todos

- Phase 1 planen (`/gsd-plan-phase 1`)
- Klären, ob Keychain-Migration `#if DEBUG`-Gate für selbstsignierte Builds braucht (Phase 1)
- Hotkey-Debounce-Zielwert festlegen: 250 ms (Doku-Stand) vs. anderer differenzierter Ansatz (Phase 1)

### Blockers

Keine.

## Session Continuity

**Letzte Aktion:** Roadmap erstellt mit 6 v1-Phasen + 3 Backlog-Phasen (999.x). Alle 18 v1-Requirements sind genau einer Phase zugeordnet.

**Nächste Aktion:** `/gsd-plan-phase 1` — Stabilisierung & Doku-Drift in Plans zerlegen.

---
*State initialisiert: 2026-04-30*
