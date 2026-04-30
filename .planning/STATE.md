# Project State: BlitzText

**Last updated:** 2026-04-30

## Project Reference

**Core Value:** Vom gedrückten Hotkey bis zum eingefügten Text wenige Sekunden — Text muss benutzbar sein, ohne nachzubearbeiten.

**Current Focus:** Milestone "Sprecher-Profile + Stabilisierung" — bestehende Tech-Schuld schließen, Test-Fundament legen, persistente lokale Sprecher-Profile auf Basis von FluidAudios `SpeakerManager` einführen.

## Current Position

- **Milestone:** Sprecher-Profile + Stabilisierung
- **Phase:** Phase 1 ✅ abgeschlossen — bereit für Phase 2
- **Plan:** —
- **Status:** Ready for `/gsd-plan-phase 2`
- **Progress:** 1/6 phases complete

```
[███░░░░░░░░░░░░░░░░░] 17% (1/6 phases)
```

## Performance Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Hotkey-Release → Clipboard (5–15 s Audio) | ≤ 3 s | nicht gemessen |
| Diarization-Modell-Download | sichtbar mit Progress | unsichtbar (Phase 3 fix) |
| Test-Coverage Hotkey + Pipeline | ≥ 1 grüner Test pro Pfad | 0 (Phase 2) |

## Accumulated Context

### Decisions

- Sprecher-Erkennung lokal über FluidAudio `SpeakerManager` (kein Cloud-Service) — Datenschutz + bestehende API
- Persistenz als JSON in `~/Library/Application Support/BlitzText/speakers.json` (analog zu `history.json`)
- Sandbox bleibt aus dieser Milestone draußen — separate Initiative
- TEST-03 (Sprecher-Matching-Tests) wandert von Phase 2 zu Phase 4, weil Code dort entsteht
- Hotkey-Debounce: 50 ms Hold / 300 ms Toggle (Phase 1, STAB-02)
- API-Key in Keychain (Service `de.reinholds.blitztext`, Account `openai-api-key`); UserDefaults-Migration einmalig + idempotent (Phase 1, STAB-01)
- Accessibility-Permission Auto-Recovery via 1 Hz `AXIsProcessTrusted`-Watcher (Phase 1, STAB-03)

### Open Todos

- Phase 2 planen (`/gsd-plan-phase 2`) — Test-Fundament
- UAT für Phase 1 (offen, kein Blocker für Phase 2):
  - Schlüsselbund-Roundtrip (Dummy-Key speichern → Schlüsselbund.app prüfen)
  - Legacy-Migration End-to-End (`defaults write … apiKey 'sk-legacy-123'` → App-Start → Migration)
  - TCC-Auto-Recovery (Permission entfernen → App starten → live aktivieren → Tap greift ohne Restart)

### Blockers

Keine.

## Session Continuity

**Letzte Aktion:** Phase 1 abgeschlossen — STAB-01..STAB-04 implementiert, Build grün, VERIFICATION.md PASS (Code) mit 3 offenen UAT-Items. 9 Commits auf main.

**Nächste Aktion:** `/gsd-plan-phase 2` — Test-Fundament (XCTest-Target, Hotkey-State-Machine-Tests, Pipeline-Fehlerpfade).

---
*Phase 1 abgeschlossen: 2026-04-30*
