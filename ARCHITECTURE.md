# BlitzText — Architektur

Native macOS-App (macOS 26+), Swift 6, SwiftUI + AppKit. Läuft als **Menu-Bar-App** ohne Dock-Icon. Globaler Hotkey startet Aufnahme, transkribiert und (je nach Modus) formt den Text um, dann Clipboard und optional Auto-Insert.

---

## Datenfluss (eine Aufnahme)

```
Hotkey gedrückt              Audio aufnehmen           Whisper-API           Rewrite-API           Output
(fn+Shift/Ctrl/Opt)    →     (AVAudioEngine,      →   (whisper-1,      →   (gpt-4o-mini,    →    Clipboard
                              16 kHz mono .wav)        OpenAI)              je nach Modus         (+ optional
                                                                                                  ⌘V autopaste)
                                                       ↑
                                                  prompt-Feld bekommt
                                                  Eigennamen-Glossar
                                                  (verbessert Diktion)
```

Drei Modi entscheiden, was nach Whisper passiert:

| Modus            | Hotkey       | Whisper | Rewrite                                |
|------------------|--------------|---------|----------------------------------------|
| Blitztext        | fn+Shift     | ja      | nein (Roh-Transkript)                  |
| Blitztext+       | fn+Control   | ja      | gpt-4o-mini, Stil-Prompt (Formell/Neutral/Locker) + Kontext |
| Blitztext $%&!   | fn+Option    | ja      | gpt-4o-mini, Deeskalations-Prompt      |

---

## Module (high-level)

| Modul              | Verantwortung                                                     | Kritische APIs |
|--------------------|-------------------------------------------------------------------|----------------|
| `MenuBarController`| `NSStatusItem`, Popover-HUD wie im Mock ("● Bereit" / Modi-Liste) | AppKit |
| `HotkeyManager`    | Globale fn+Modifier-Erkennung via `CGEventTap`                    | CoreGraphics |
| `AudioRecorder`    | Aufnahme in temp .wav (16 kHz, mono, 16-bit PCM)                  | AVAudioEngine |
| `WhisperAPIClient` | Multipart-Upload an `/v1/audio/transcriptions`                    | URLSession |
| `RewriteService`   | Chat-Completion mit Modus-spezifischem Prompt                     | URLSession |
| `ModeProcessor`    | Orchestriert: Aufnahme → Whisper → (Rewrite) → Output             | – |
| `SettingsStore`    | UserDefaults (Prefs) + Keychain (API-Key)                         | Foundation, Security |
| `TextInserter`     | Schreibt Clipboard, optional simuliert ⌘V                         | NSPasteboard, CGEvent |
| `LocalWhisperClient` | (Stub) Platzhalter für lokales Modell wie MacWhisper            | – |

---

## Permissions (Entitlements + Info.plist)

| Permission                   | Zweck                           | Wo deklariert |
|------------------------------|---------------------------------|---------------|
| Mikrofon                     | Aufnahme                        | `NSMicrophoneUsageDescription` |
| Speech Recognition (optional)| nur falls Apple-Speech-Fallback | `NSSpeechRecognitionUsageDescription` |
| Accessibility (TCC)          | nur für Auto-Paste              | wird zur Laufzeit geprüft, kein Eintrag in Info.plist (TCC-Prompt) |
| Network Outgoing             | OpenAI-API                      | App Sandbox (falls Sandbox aktiv) |
| Apple Events                 | Falls `osascript`-Fallback nötig| `NSAppleEventsUsageDescription` (nicht im MVP) |

App startet **ohne Sandbox** im MVP — das vereinfacht Hotkey + Accessibility erheblich. Mit Sandbox später nachziehbar (Hotkey funktioniert, Accessibility bleibt out-of-sandbox).

---

## Hotkey-Strategie (kritisch, hier scheitern viele)

`fn` ist **kein normaler Modifier** für Carbon `RegisterEventHotKey`. Lösung:

1. `CGEventTap` auf `kCGEventFlagsChanged` registrieren (braucht Accessibility-Permission)
2. `CGEventFlags.maskSecondaryFn` für fn-Erkennung
3. Klassische Modifier (`.maskShift`, `.maskControl`, `.maskAlternate`) parallel prüfen
4. State-Machine: fn+Mod down → start; release → stop (Halten-Modus); double-press → toggle (Drücken-Modus)

Ohne Accessibility-Permission gibt es **keinen** zuverlässigen Weg, fn zu fangen — der erste App-Start prompted dafür.

---

## Settings-Persistenz

- **API-Key**: Keychain (`Service: de.reinholds.blitztext`, `Account: openai-api-key`)
- **Alles andere**: `UserDefaults` als JSON unter `de.reinholds.blitztext.settings`
  - Hotkey-Bindings (Default: fn+Shift, fn+Control, fn+Option)
  - Modus (Halten/Drücken)
  - Schreibstil pro Modus (Formell/Neutral/Locker)
  - Eigene Anweisung pro Modus (Custom Prompt)
  - Kontext-Text
  - Eigennamen-Glossar (`[String]`)
  - Auto-Insert ein/aus

---

## Transkriptions-Backend (austauschbar)

```swift
protocol TranscriptionService {
    func transcribe(audioURL: URL, prompt: String?) async throws -> String
}
```

Implementierungen:
- `WhisperAPIClient` — MVP, OpenAI Whisper-API (`whisper-1`)
- `LocalWhisperClient` — Stub für späteren Ausbau (z.B. via [whisper.cpp](https://github.com/ggerganov/whisper.cpp) bzw. CoreML-Modelle wie bei MacWhisper)

Switch im Settings-Tab "Zugang" → "Backend: OpenAI / Lokal".

---

## Edge Cases (die wir kennen)

Siehe `RISKS.md`.
