# BlitzText

Native macOS-App, die Sprache per globalem Hotkey in Text umwandelt — wahlweise als Roh-Transkript, in Schreibstil umformuliert oder von emotional auf sachlich entschärft.

## Modi

| Hotkey         | Modus            | Was es tut                                    |
|----------------|------------------|------------------------------------------------|
| `fn + Shift`   | Blitztext        | Sprache rein, Roh-Text raus.                  |
| `fn + Control` | Blitztext+       | Geschrieben sprechen — Stil wählbar.          |
| `fn + Option`  | Blitztext $%&!   | Frust rein, sachlich-freundliche Nachricht raus. |

Trigger-Verhalten:
- **Halten** (Default): Aufnahme läuft, solange der Hotkey gedrückt ist.
- **Drücken**: einmal drücken startet, erneut drücken stoppt.

Der Output landet in der Zwischenablage. Optional kann er direkt an der aktiven Cursor-Position eingefügt werden (Toggle in den Einstellungen, braucht Bedienungshilfen-Permission).

---

## Setup

### Voraussetzungen

- macOS 26 oder neuer (Apple Silicon)
- Xcode (vollständig, App Store)
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Einen OpenAI-API-Key (https://platform.openai.com/api-keys)

### Bauen

```bash
cd ~/VsCode/BlitzText
./Scripts/build.sh
open build/BlitzText.app
```

Der Build legt das `.xcodeproj` neu an (aus `project.yml`) und signiert ad-hoc, damit die TCC-Permissions zwischen Builds erhalten bleiben.

### Erste Schritte

1. App starten — sie läuft als Menu-Bar-Icon (⚡).
2. Beim ersten Aufnahmeversuch fragt macOS nach **Mikrofon**-Permission → erlauben.
3. Zahnrad → Tab "Zugang" → **Bedienungshilfen: „Erlauben"** (nötig für Hotkey-Erkennung + Auto-Insert). Der Klick trägt BlitzText in die Liste in den Systemeinstellungen ein — den **Schalter dort legst du selbst um** (Passwort/Touch ID). Die Anzeige im Tab springt danach von allein um; ein App-Neustart ist nicht nötig.
4. Optional im selben Tab: **Automatischer Start** → „Aktivieren" legt den Eintrag unter Systemeinstellungen › Allgemein › Anmeldeobjekte an. Auch hier gilt: eintragen macht die App, einschalten der Nutzer. Braucht BlitzText in `/Applications` (`./Scripts/install.sh`).
5. Tab "Zugang" → API-Key einfügen.
6. Tab "Anpassen": Schreibstil, eigene Anweisung, Kontext, Eigennamen-Glossar setzen.

---

## Architektur

Siehe [`ARCHITECTURE.md`](./ARCHITECTURE.md). Kurz:

```
Hotkey → AudioRecorder (.wav, 16 kHz mono) →
  WhisperAPIClient (OpenAI /v1/audio/transcriptions) →
    [Mode == .blitztext]      → Clipboard
    [Mode == .blitztextPlus]  → OpenAIChatClient (gpt-4o-mini, Stil-Prompt)  → Clipboard
    [Mode == .blitztextRant]  → OpenAIChatClient (gpt-4o-mini, Calm-Prompt)  → Clipboard
```

`TranscriptionService`-Protokoll erlaubt späteren Tausch gegen ein **lokales** Whisper-Modell (whisper.cpp / CoreML, vergleichbar mit MacWhisper). Stub liegt unter `LocalWhisperClient.swift`.

---

## Rewrite-Backend: Apple Foundation Models

BlitzText nutzt ab macOS 26 standardmäßig Apples lokale Foundation Models
für den Rewrite-Schritt in Blitztext+ (Stil-Aufpolitur) und Blitztext $%&!
(Deeskalation). Das hat zwei Vorteile: nichts verlässt dein Gerät, und es
kostet keine OpenAI-API-Aufrufe.

**Voraussetzung:** Apple Intelligence muss in den Systemeinstellungen
aktiviert sein (Systemeinstellungen → Apple Intelligence & Siri →
Apple Intelligence). Das Foundation-Modell wird beim ersten Aktivieren
einmalig im Hintergrund geladen (~3 GB).

**Wichtig für Geräte unter MDM-Verwaltung:** „Siri & Diktierfunktion" und
Apple Intelligence sind getrennte Restriction-Pfade. Es reicht, dass
Apple Intelligence aktiv ist — Siri kann von der Organisation deaktiviert
sein, ohne dass BlitzText+ oder BlitzText $%&! beeinträchtigt werden.
Apple Intelligence ist also **unabhängig** vom Siri-Status. Wenn der
Modi-Tab „Apple Intelligence ist nicht aktiviert" zeigt, obwohl das System
scheinbar alles eingeschaltet hat, liegt typischerweise ein MDM-Restrict
auf Apple Intelligence (nicht auf Siri).

**Wenn Apple Intelligence nicht verfügbar ist:** BlitzText schaltet das
Default-Backend automatisch auf OpenAI gpt-4o-mini, sofern ein API-Key
hinterlegt ist. Der Modi-Tab zeigt einen entsprechenden Hinweis-Banner
mit Link zu den Systemeinstellungen.

**Backend pro Mode getrennt wählbar:** Im Modi-Tab kannst du für
Blitztext+ und Blitztext $%&! das Backend unabhängig setzen. Apple
Intelligence ist Default; OpenAI ist als expliziter Override verfügbar
(z. B. wenn die Deeskalations-Qualität von gpt-4o-mini für einen Mode
besser passt).

---

## Permissions

| Permission                       | Wofür                                       |
|----------------------------------|----------------------------------------------|
| Mikrofon                         | Aufnahme                                     |
| Bedienungshilfen (Accessibility) | Globalen `fn`-Hotkey abfangen + Auto-Insert  |
| Netzwerk (out)                   | OpenAI-API                                   |

App läuft **ohne Sandbox** im MVP — vereinfacht TCC-Handling.

Bedienungshilfen und der Anmeldeobjekt-Eintrag werden im Tab "Zugang" angestoßen
(`AXIsProcessTrustedWithOptions` bzw. `SMAppService.mainApp.register()`). Beides legt nur den
Eintrag an; das Aktivieren bleibt eine Nutzeraktion in den Systemeinstellungen. Danach fragt
der `StatusPoller` den Status ~1 Minute im Sekundentakt nach, damit die Badges ohne
Fenster-Neustart umspringen.

---

## Risiken & Edge Cases

Siehe [`RISKS.md`](./RISKS.md).

Wichtigster Stolperstein in der Praxis: **macOS-Diktat ist standardmäßig auch auf `fn` gemappt**. Wenn beides gleichzeitig aktiv ist, kollidieren sie.
→ macOS-Diktat in Systemeinstellungen → Tastatur deaktivieren oder umlegen.

---

## Nächste Ausbau-Schritte (Backlog)

1. **Lokales Whisper-Modell** (whisper.cpp + GGUF-Modelle in den Settings)
2. **Aufnahme-Historie** mit Replay
3. **Onboarding-Wizard** beim ersten Start
4. **Streaming-Whisper** für niedrigere Latenz
5. **Kosten-Tracking** im UI
6. **Distribution**: Developer-ID-Signing + Notarization, Sparkle-Updates
7. **Sandbox aktivieren**, sobald Hotkey-Tap und Accessibility durch UI sauber abgewickelt sind
8. **Apple Foundation Models** als Rewrite-Backend (lokal, ab macOS 26)

---

## Projekt-Layout

```
BlitzText/
├── README.md, ARCHITECTURE.md, RISKS.md
├── project.yml                        ← xcodegen-Quelle
├── BlitzText.xcodeproj                ← generiert (gitignore)
├── BlitzText/
│   ├── App/                           Entry-Point, AppDelegate
│   ├── MenuBar/                       Status-Bar-Icon, Popover-HUD
│   ├── Hotkeys/                       CGEventTap für fn-Modifier
│   ├── Audio/                         AVAudioEngine → 16 kHz Mono WAV
│   ├── Transcription/                 Whisper-API + Local-Stub
│   ├── Rewrite/                       gpt-4o-mini Chat-Client
│   ├── Modes/                         Mode-Enum + Pipeline-Orchestrator
│   ├── Settings/                      SettingsStore + Keychain + SettingsView
│   ├── UI/                            HUDView (SwiftUI)
│   ├── Insertion/                     Clipboard + Auto-Paste
│   ├── Info.plist                     ← generiert aus project.yml
│   └── BlitzText.entitlements         ← generiert aus project.yml
└── Scripts/build.sh                   xcodegen + xcodebuild + codesign
```
