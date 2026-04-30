# BlitzText — Risiken & Edge Cases

## Hard-Risiken (können MVP killen)

| # | Risiko | Wahrscheinlichkeit | Mitigation |
|---|--------|-------------------|------------|
| 1 | **fn-Modifier nicht abfangbar** ohne Accessibility-Permission | hoch | Erstes App-Start: Permissions-Dialog, klare Anleitung. Fallback-Hotkey ohne fn (z.B. ⌃⌥⇧+1/2/3) als Plan B. |
| 2 | **TCC/Accessibility-Reset** nach jedem unsignierten Build | sehr hoch (Dev) | Build-Skript signt mit Ad-hoc-Cert mit stabiler Identity. Sonst muss User nach jedem Build die Permission neu erteilen. |
| 3 | **Mikrofon-Permission verweigert** | mittel | Klarer Prompt + Settings-Deeplink beim ersten Start |
| 4 | **OpenAI-API-Key falsch / Rate-Limit / Netzwerk weg** | mittel | Statusanzeige im HUD ("Fehler: ungültiger Key"), Retry mit Backoff |
| 5 | **Hotkey kollidiert** mit anderen Tools (Raycast, Karabiner, Dictation auf fn) | hoch | macOS-Diktat auf fn ist Default-AN — User muss in Sys-Settings deaktivieren oder anderen Hotkey wählen |
| 6 | **Auto-Paste schießt sich selbst ab**, wenn Cursor in BlitzText-Settings | niedrig | Vor `⌘V` aktiven Frontmost-App-Bundle prüfen; nicht in eigene App pasten |

## Mittlere Risiken

| # | Risiko | Mitigation |
|---|--------|------------|
| 7 | Whisper-Latenz bei langen Aufnahmen (> 30s) | UI-Feedback "Transkribiere…", Streaming-Antwort später |
| 8 | gpt-4o-mini halluziniert bei kurzen Aufnahmen | System-Prompt: "Wenn unklar, gib Roh-Transkript zurück" |
| 9 | Audio in fremder Sprache → Whisper rät | Sprach-Auto-Detect ist Default; Setting "Sprache: Deutsch" als Override |
| 10 | API-Kosten unkontrolliert | UI zeigt geschätzte Kosten / Monat, Limit-Setting (später) |
| 11 | Doppel-Trigger durch Tastendruck-Wiederholung | Debounce 250ms im HotkeyManager |
| 12 | App stürzt während Aufnahme ab → temp-Datei bleibt liegen | Cleanup beim Start: alte BlitzText-temps löschen |

## Bekannt, aber nicht-blockierend

- Ohne Code-Sign mit Developer-ID kann die App nicht weitergegeben werden (Gatekeeper). Für Eigenverwendung ad-hoc-sign reicht.
- Kein Update-Mechanismus im MVP. Sparkle/macOS-eigenes Update später.
- Kein Onboarding-Flow im MVP — der User (du) weiß, was er tut. Nutzer-Flow kommt mit Distribution.
- Lokales Whisper-Modell ist nur ein Stub. Echter Einbau (whisper.cpp) ist eigene Phase.
- Kein Offline-Modus. Ohne Netz: Hinweis im HUD.

## Roadmap (geplant, nicht im MVP)

- **NVIDIA Parakeet TDT v3** als alternatives lokales STT-Backend (via ParakeetKit/argmaxinc) — bringt Sprechererkennung (Diarization), die Whisper nicht hat. Wäre Drop-in als zweite TranscriptionService-Implementierung.
- **Speaker Diarization** (mit Parakeet oder eigener Pipeline)
- **Distil-Modelle multilingual** wenn HuggingFace-Distil-Whisper für non-EN nachzieht

## Was im MVP fehlt (bewusst)

- Keine Aufnahme-Historie / Replay
- Kein Export (geht nur über Clipboard)
- Keine Mehrsprachigkeit der UI (DE only)
- Kein Onboarding-Wizard
- Keine Telemetrie / Analytics
- Keine automatische Update-Prüfung
