---
status: pending
phase: 06-sprecher-enrollment
updated: 2026-05-19
---

# Phase 6: Sprecher-Enrollment — Manual UAT

**Objective:** End-to-End-Verifikation des Enrollment-Flows von SprecherTab → Sheet → Aufnahme → Profil-Anlage → Persistenz + Fehlerpfade.

**Vorbedingung:**
- Parakeet-Backend in Settings ausgewählt
- Diarization aktiviert, Modell installiert
- App frisch gestartet

---

## Checkliste

| # | Schritt | Erwartung | Status |
|---|---------|-----------|--------|
| 1 | Settings öffnen → "Sprecher"-Tab | Section "ENROLLMENT" mit Button "Neues Profil aufnehmen" sichtbar | ☐ |
| 2 | Diarizer-Modell **nicht** installiert | Button ausgegraut + Caption "Diarizer-Modell nicht installiert. Aktiviere Sprechererkennung im Backend-Tab." sichtbar | ☐ |
| 3 | Diarizer installieren (Backend-Tab) | Button "Neues Profil aufnehmen" wird aktiv | ☐ |
| 4 | Button klicken | Sheet öffnet sich mit Titel "Sprecher-Profil aufnehmen" | ☐ |
| 5 | Name eingeben (z.B. "Thomas Test") | "Aufnahme starten" wird blau (.borderedProminent) | ☐ |
| 6 | "Aufnahme starten" klicken | Pegel-Balken erscheint (glatte Animation, .accentColor), Restzeit zählt von 15 runter (.monospacedDigit, kein Layout-Springen) | ☐ |
| 7 | 15 Sekunden frei sprechen | Aufnahme stoppt automatisch bei 0 | ☐ |
| 8 | Nach Aufnahme | Spinner + "Profil wird erstellt …" erscheint für ~1–2s | ☐ |
| 9 | Sheet-Auto-Dismiss | Sheet schließt sich nach ≈0.3s ohne weiteren Klick | ☐ |
| 10 | allSpeakersSection prüfen | "Thomas Test" mit PERMANENT-Badge in der Sprecher-Liste | ☐ |
| 11 | Persistenz-Check | App schließen → neu starten → "Thomas Test" noch vorhanden; `cat ~/Library/Application\ Support/BlitzText/speakers.json \| python3 -m json.tool` zeigt Eintrag | ☐ |
| 12 | Fehler-Pfad zu kurz | Neues Enrollment → Name eingeben → "Aufnahme starten" → sofort "Stopp" (< 5s) → Inline-Fehlermeldung, Sheet bleibt offen, Name erhalten | ☐ |
| 13 | Fehler-Pfad zu leise | Name eingeben → "Aufnahme starten" → 6 Sekunden still (Mikrofon zuhalten) → "Aufnahme zu leise — bitte lauter sprechen oder näher ans Mikrofon." | ☐ |
| 14 | Abbrechen-Pfad | "Enrollment abbrechen" → Sheet schließt sich, kein Profil angelegt | ☐ |
| 15 | DSGVO-Check | Keine WAV-Datei in `$TMPDIR` (NSTemporaryDirectory) nach Enrollment | ☐ |

---

## Ergebnis

| Szenarien | Bestanden | Datum |
|-----------|-----------|-------|
| 15 Schritte | ☐/15 | |

**Sign-Off:** ☐ Phase 6 UAT bestanden
