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
3. Beim ersten Hotkey-Druck fragt macOS nach **Bedienungshilfen** (für die Hotkey-Erkennung) → erlauben. **Wichtig**: nach Aktivierung Permission die App **einmal beenden und neu starten**.
4. Im Menubar-Icon klicken → Zahnrad → Tab "Zugang" → API-Key einfügen.
5. Tab "Anpassen": Schreibstil, eigene Anweisung, Kontext, Eigennamen-Glossar setzen.

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

## Permissions

| Permission                       | Wofür                                       |
|----------------------------------|----------------------------------------------|
| Mikrofon                         | Aufnahme                                     |
| Bedienungshilfen (Accessibility) | Globalen `fn`-Hotkey abfangen + Auto-Insert  |
| Netzwerk (out)                   | OpenAI-API                                   |

App läuft **ohne Sandbox** im MVP — vereinfacht TCC-Handling.

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
