---
phase: 01-stabilisierung-doku-drift
plan: 04
subsystem: docs
tags: [doc-drift, whisperkit, local-whisper, risks, architecture]
requires:
  - 01-02
provides:
  - "RISKS.md ohne Stub/whisper.cpp-Wording für lokales Whisper"
  - "ARCHITECTURE.md drift-frei im LocalWhisperClient-Kontext"
affects:
  - RISKS.md
  - .planning/codebase/ARCHITECTURE.md
tech-stack:
  added: []
  patterns: []
key-files:
  created: []
  modified:
    - RISKS.md
decisions:
  - "ARCHITECTURE.md unverändert gelassen — kein Drift-Treffer, Refresh-Marker bereits auf 2026-04-30 (durch Plan 02 gesetzt)."
  - "Cold-Start (1–3 min CoreML-Compile) als verbleibendes echtes Risiko in RISKS.md festgehalten — ersetzt das fälschliche 'Stub'-Risiko."
metrics:
  duration: ~5 min
  completed: 2026-04-30
requirements: [STAB-04]
---

# Phase 1 Plan 04: Doku-Drift LocalWhisperClient Summary

Doku-Drift in `RISKS.md` und `.planning/codebase/ARCHITECTURE.md` zum Thema `LocalWhisperClient` geschlossen — Beschreibung spiegelt jetzt die echte WhisperKit/CoreML-Implementierung.

## What Was Built

### Task 1: RISKS.md — Stub-Wording entfernt

**Initialer Grep-Treffer (`Stub|stub|whisper\.cpp|Placeholder|placeholder|TODO LocalWhisper|TODO.*Whisper`):**

```
30:- Lokales Whisper-Modell ist nur ein Stub. Echter Einbau (whisper.cpp) ist eigene Phase.
```

Genau ein Treffer, gleich doppelt falsch:
1. Code (`BlitzText/Transcription/LocalWhisperClient.swift`) ist eine vollständige WhisperKit-Implementierung mit `warmUp`, `ensureLoaded`, `transcribe` — kein Stub.
2. Backend ist WhisperKit/CoreML, **nicht** whisper.cpp.

**Diff:**

```diff
-- Lokales Whisper-Modell ist nur ein Stub. Echter Einbau (whisper.cpp) ist eigene Phase.
+- Lokales Whisper läuft über WhisperKit/CoreML (siehe `BlitzText/Transcription/LocalWhisperClient.swift`).
+  Modelle werden beim ersten Aktivieren aus HuggingFace heruntergeladen und unter
+  `~/Library/Application Support/BlitzText/Models/<variant>/` abgelegt. Risiko: Cold-Start
+  des CoreML-Compile-Schritts beim ersten Lauf liegt bei 1–3 Minuten — daher Warm-Up via
+  `LocalModelManager.onActivate` beim Modellwechsel und in `AppDelegate.bootstrap`.
```

**Commit:** `1f32cd2` — `docs(01-04): replace Whisper-Stub wording in RISKS.md`

### Task 2: ARCHITECTURE.md — finale Drift-Prüfung

**Greps:**
- `grep -nEi "stub|placeholder|TODO" .planning/codebase/ARCHITECTURE.md` → **kein Treffer**
- `grep -nEi "fake|mock|dummy" … | grep -i whisper` → **kein Treffer**
- Safety-Greps `Local.*Whisper.*(stub|…)` und Inverse → **kein Treffer**

ARCHITECTURE.md beschreibt `LocalWhisperClient` bereits korrekt:
- Zeile 33–34: ASCII-Diagramm `LocalWhisperClient (WhisperKit / CoreML)`
- Zeile 61: `LocalWhisperClient | WhisperKit/CoreML on-device transcription`
- Zeile 179: `Implementations: WhisperAPIClient, LocalWhisperClient, ParakeetClient.`

Refresh-Marker `<!-- refreshed: 2026-04-30 -->` (Zeile 1) bereits auf heutiges Datum (von Plan 01-02 gesetzt). **Keine Änderung nötig** — daher kein Commit für Task 2.

## Verification

- `grep -rEi "Local.*Whisper.*(stub|placeholder|TODO|whisper\.cpp|fake|mock|dummy)" RISKS.md .planning/codebase/ARCHITECTURE.md` → **leer (exit 1)**
- `grep -i "cold-start" RISKS.md` → benannt
- Beide Done-Kriterien erfüllt.

## Deviations from Plan

None — plan executed exactly as written. Task 2 erforderte (wie im Plan vorgesehen) keine Änderung, da der Drift-Scan leer und der Refresh-Marker aktuell ist.

## Self-Check: PASSED

- RISKS.md modifiziert: FOUND
- Commit `1f32cd2`: FOUND in `git log`
- Final-Verification grün
