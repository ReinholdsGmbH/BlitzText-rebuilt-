---
status: testing
phase: 04-sprecher-profile-core
started: 2026-05-19T00:00:00Z
updated: 2026-05-19T00:00:00Z
---

## Current Test

number: 4
name: SC-4 — Unbekannte Sprecher erhalten nummerierte Fallback-Bezeichnung
expected: |
  speakers.json leeren ([] speichern) oder umbenennen.
  App neu starten. Aufnahme mit 2 erkennbaren Stimmen (z.B. Podcast) starten.
  Clipboard: "Sprecher 1: …" und "Sprecher 2: …" erscheinen (deutsch, stabil geordnet).
  Nicht erwartet: "Speaker 1:" (englisch), kein Präfix, oder beide "Sprecher 1:".
fix_applied: |
  isWordBoundary-Bug in ParakeetClient.applyDiarization behoben.
  FluidAudio normalisiert ▁ (U+2581) vor Speicherung in TokenTiming.token zu " " (U+0020).
  Der Wortgrenz-Check prüfte fälschlicherweise auf ▁ statt auf führendes Leerzeichen →
  isWordBoundary war immer false → Sprecherwechsel wurden nie erkannt.
  Fix: hasPrefix("\u{2581}") → hasPrefix(" ").
awaiting: retest after fix


# Phase 4: Sprecher-Profile Core — UAT

> **Hinweis:** Diese Tests werden **gemeinsam mit Phase 5 (Sprecher-Profile UI)** durchgeführt.
> Grund: Phase 4 legt die Datenbasis an (Persistenz, Matching, Namensauflösung), aber
> das manuelle Benennen von Sprechern setzt die Phase-5-UI voraus.
> Datei [05-UAT.md](../05-sprecher-profile-ui/05-UAT.md) enthält alle Phase-4- und Phase-5-Tests.

## Automatisierte Tests (bereits grün ✅)

64/64 Tests, 3× consecutive ohne Flake (2026-05-15):

| Test-Klasse | Tests | Abdeckung |
|---|---|---|
| `SpeakerProfileStoreTests` | 10 | Persistenz Round-Trip, atomic write, Korrupt-Fallback, Namenslogik |
| `SpeakerMatchingTests` | 7 | Cosine-Threshold, EMA-Richtungstest, applyDiarization-Format, Round-Trip |

## Manuelle UAT-Szenarien (Phase-4-Teil)

Diese Szenarien werden in `05-UAT.md` als Block "Phase 4: Core-Verhalten" aufgenommen.

### SC-1: Sprecher-Profile beim App-Start laden (SPK-01)

**Vorbedingung:** Diarization ist in Settings aktiviert.

1. `~/Library/Application Support/BlitzText/speakers.json` manuell anlegen:
   ```json
   [
     {
       "id": "1",
       "name": "Thomas",
       "currentEmbedding": [/* 256 Werte */],
       "duration": 10.0,
       "isPermanent": true,
       "updateCount": 1,
       "rawEmbeddings": [],
       "createdAt": "2026-05-15T00:00:00Z",
       "updatedAt": "2026-05-15T00:00:00Z"
     }
   ]
   ```
2. App starten.
3. BlitzText-Log prüfen (Console.app oder Terminal mit `log stream`):
   - **Erwartet:** `Parakeet: 1 Sprecher-Profile geladen`

### SC-2: Profile nach Aufnahme persistieren (SPK-02)

**Vorbedingung:** Parakeet-Backend + Diarization aktiv, Diarizer-Modell installiert.

1. `speakers.json` löschen oder umbenennen.
2. Aufnahme starten (mind. 10 s, möglichst 2 Sprecher).
3. `speakers.json` nach der Aufnahme öffnen.
   - **Erwartet:** Datei existiert, enthält mind. 1 Sprecher-Objekt mit `id`, `currentEmbedding`, `duration > 0`.
4. Zweite Aufnahme — `speakers.json` erneut öffnen.
   - **Erwartet:** `updateCount` des gematchten Sprechers ist gestiegen ODER ein zweiter Sprecher erscheint.

### SC-3: Bekannte Sprecher im Transkript mit Namen (SPK-03)

**Vorbedingung:** `speakers.json` enthält Sprecher mit angepasstem Namen (≠ `"Speaker N"`).

1. `speakers.json` anlegen wie in SC-1 (Name `"Thomas"`, ID wie vom Diarizer vergeben).
2. Aufnahme mit Diarization starten, Thomas spricht.
3. Clipboard-Inhalt prüfen.
   - **Erwartet:** `Thomas: <gesprochener Text>`
   - **Nicht erwartet:** `Sprecher 1: <Text>`

### SC-4: Unbekannte Sprecher erhalten nummerierte Fallback-Bezeichnung (SPK-03)

**Vorbedingung:** `speakers.json` ist leer oder enthält keine passenden Profile.

1. `speakers.json` leeren (`[]`).
2. Aufnahme mit 2 erkennbaren Sprechern starten.
3. Clipboard-Inhalt prüfen.
   - **Erwartet:** `Sprecher 1: …` und `Sprecher 2: …` (stabiler Reihenfolge)
   - **Nicht erwartet:** `Speaker 1:` (Englisch) oder leeres Präfix
