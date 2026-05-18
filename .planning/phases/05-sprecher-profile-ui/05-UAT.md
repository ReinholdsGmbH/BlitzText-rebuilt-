---
status: passed
phase: 05-sprecher-profile-ui
covers_phases: [04-sprecher-profile-core, 05-sprecher-profile-ui]
updated: 2026-05-18
implemented: 2026-05-15
commit: 22eabb3
---

# Phase 4 + 5: Sprecher-Profile — Kombinierter UAT

> Dieses Dokument ist der **einzige UAT-Test-Tag** für Sprecher-Profile.
> Er deckt Phase 4 (Core-Persistenz + Matching) und Phase 5 (Settings-UI) gemeinsam ab.
> Erst nach Phase 5 durchführen.

## Vorbedingungen

- [ ] Parakeet-Backend in Settings ausgewählt
- [ ] Diarization-Toggle ist ON, Modell installiert
- [ ] App ist neu gestartet (kein warmer Zustand)
- [ ] `~/Library/Application Support/BlitzText/speakers.json` existiert nicht (Sauberzustand)

---

## Block A: Phase-4-Core — Persistenz & Matching

### A-1: Erster Durchlauf — Sprecher werden angelegt (SPK-01, SPK-02)

1. Aufnahme starten (mind. 10 s, möglichst 2 erkennbare Sprecher).
2. `speakers.json` nach der Aufnahme öffnen.
   - **Erwartet:** Datei existiert, ≥ 1 Sprecher-Objekt mit `id`, `currentEmbedding` (256 Werte), `duration > 0`
3. Clipboard-Inhalt prüfen.
   - **Erwartet:** `Sprecher 1: …` (und ggf. `Sprecher 2: …`) — kein Englisch, kein leeres Präfix

| Szenario | Erwartet | Status |
|---|---|---|
| `speakers.json` existiert nach Aufnahme | Datei vorhanden, gültiges JSON | ☐ |
| Clipboard enthält `Sprecher N:` Präfixe | ≥ 1 Sprecher im Output | ☐ |

### A-2: Zweiter Durchlauf — Sprecher wird wiedererkannt (SPK-01)

1. App **nicht** neu starten. Zweite Aufnahme (gleicher Sprecher, gleiche Bedingungen).
2. `speakers.json` öffnen — `updateCount` des ersten Sprechers prüfen.
   - **Erwartet:** `updateCount` > 1 (Sprecher wurde gematcht und aktualisiert, kein doppelter Eintrag)

| Szenario | Erwartet | Status |
|---|---|---|
| Gleicher Sprecher → `updateCount` steigt | updateCount ≥ 2 nach 2 Aufnahmen | ☐ |
| Keine Duplikat-Profile für gleiche Stimme | `speakers.json` enthält ≤ N Einträge | ☐ |

### A-3: App-Neustart — Profile werden geladen (SPK-01)

1. App komplett beenden.
2. App neu starten.
3. Aufnahme mit denselben Sprechern wie in A-1.
   - **Erwartet:** Sprecher-IDs in `speakers.json` sind die gleichen wie nach A-1 (kein Reset)
   - Log prüfen: `Parakeet: N Sprecher-Profile geladen`

| Szenario | Erwartet | Status |
|---|---|---|
| Log zeigt Profil-Ladung | `Parakeet: N Sprecher-Profile geladen` | ☐ |
| Profile bleiben über Restart erhalten | IDs in JSON identisch | ☐ |

### A-4: Fallback bei leerer Profile-Datei (SPK-03)

1. `speakers.json` auf `[]` setzen, App neu starten.
2. Aufnahme starten.
   - **Erwartet:** Transcript zeigt `Sprecher 1: …` (kein Crash, kein leeres Label)

| Szenario | Erwartet | Status |
|---|---|---|
| Leere JSON → kein Crash | App läuft normal | ☐ |
| Output-Format korrekt | `Sprecher 1:` auf Deutsch | ☐ |

---

## Block B: Phase-5-UI — Sprecher-Tab

> Dieser Block setzt Phase 5 voraus. Items werden beim Phase-5-Execution ausgefüllt.

### B-1: Sprecher-Tab zeigt alle bekannten Profile (SPK-04)

1. Settings öffnen → Tab "Sprecher".
   - **Erwartet:** Liste aller Sprecher aus `speakers.json` mit Name, Erkennungen, letzter Nutzung

| Szenario | Erwartet | Status |
|---|---|---|
| Tab "Sprecher" existiert | Sichtbar in Settings-Leiste | ☐ |
| Liste zeigt Sprecher aus A-1/A-2 | ≥ 1 Eintrag mit korrekten Daten | ☐ |
| `isPermanent`-Flag sichtbar | Permanent-Marker erkennbar | ☐ |

### B-2: Sprecher umbenennen (SPK-05, SPK-03-Nachweistest)

1. Sprecher 1 in Settings umbenennen auf `"Thomas"`.
2. Settings schließen.
3. Neue Aufnahme starten (Thomas spricht).
   - **Erwartet:** Clipboard enthält `Thomas: …` statt `Sprecher 1: …`

| Szenario | Erwartet | Status |
|---|---|---|
| Name in UI änderbar | Inline-Edit funktioniert | ☐ |
| Name in `speakers.json` gespeichert | `"name": "Thomas"` im JSON | ☐ |
| Nächste Aufnahme nutzt Namen | `Thomas: …` im Clipboard | ☐ |

### B-3: Sprecher löschen (SPK-05)

1. Sprecher in Settings löschen.
2. `speakers.json` prüfen — Sprecher ist entfernt.
3. Neue Aufnahme — Sprecher erscheint wieder als `Sprecher 1:` (neues unbekanntes Profil).

| Szenario | Erwartet | Status |
|---|---|---|
| Löschen entfernt Eintrag aus JSON | `speakers.json` enthält den Sprecher nicht mehr | ☐ |
| Löschen von permanentem Sprecher | Bestätigung erforderlich (SPK-07) | ☐ |

### B-4: Threshold-Slider (SPK-07)

1. Threshold-Slider auf Maximum (0.9) stellen.
2. Aufnahme starten — Sprecher sollten schwerer gematchte werden → mehr neue Profile.
3. Slider auf Minimum (0.5) → Sprecher werden aggressiver zusammengeführt.

| Szenario | Erwartet | Status |
|---|---|---|
| Slider in Settings sichtbar (0.5–0.9) | Slider vorhanden | ☐ |
| Wert wird in `SettingsStore` gespeichert | Nach Neustart erhalten | ☐ |
| Wert wirkt auf nächste Aufnahme | Threshold-Änderung sichtbar im Profil-Output | ☐ |

### B-5: Letztes Transkript — Sprecher-ID zuweisen (SPK-06)

1. Aufnahme mit unbekanntem Sprecher → erscheint als `Sprecher 1:`.
2. Settings → Sprecher-Tab → `Sprecher 1` aus letztem Transkript einem Namen zuordnen.
3. `speakers.json` prüfen: Sprecher ist jetzt permanent, trägt den Namen.
4. Neue Aufnahme → `<Name>: …` im Output.

| Szenario | Erwartet | Status |
|---|---|---|
| Zuordnung aus letztem Transkript möglich | UI bietet Zuweisung an | ☐ |
| Profil wird permanent | `"isPermanent": true` im JSON | ☐ |
| Nächste Aufnahme nutzt Namen | Korrekte Ausgabe | ☐ |

---

## Zusammenfassung

| Block | Tests | Bestanden | Datum |
|---|---|---|---|
| A: Phase-4-Core | 4 Szenarien (10 Checks) | ☐/10 | |
| B: Phase-5-UI | 5 Szenarien (15 Checks) | ☐/15 | |
| **Gesamt** | **25 Checks** | **☐/25** | |

**Sign-Off:** ☐ Phase 4+5 UAT bestanden — bereit für Phase 6 (Enrollment)
