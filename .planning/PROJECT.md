# BlitzText

## What This Is

Native macOS-Menu-Bar-App, die per globalem Hotkey (`fn`+Modifier) Sprache aufnimmt, transkribiert und das Ergebnis in die Zwischenablage legt — wahlweise als Roh-Transkript, in einem gewählten Schreibstil umformuliert oder von emotional auf sachlich entschärft. Zielgruppe: Wissensarbeiter:innen auf macOS, die schneller schreiben wollen als sie tippen können, und sensible Texte (Frust-Mails, Tickets, Slack) nicht ungefiltert raussenden möchten.

## Core Value

**Vom gedrückten Hotkey bis zum eingefügten Text dürfen nicht mehr als ein paar Sekunden vergehen — und der Text muss benutzbar sein, ohne nachzubearbeiten.** Wenn Latenz, Hotkey-Erkennung oder Transkriptionsqualität versagen, ist die App wertlos.

## Requirements

### Validated

<!-- Aus existierender Codebasis abgeleitet (siehe `.planning/codebase/`) — bereits ausgeliefert und in Nutzung. -->

- ✓ Globaler `fn`+Modifier-Hotkey via CGEventTap mit Halten/Drücken-Modus — existing
- ✓ Aufnahme als 16 kHz-Mono-WAV via AVAudioEngine — existing
- ✓ Transkription über austauschbares `TranscriptionService`-Protokoll: OpenAI Whisper-API + lokal Parakeet TDT v3 (FluidAudio) + WhisperKit — existing
- ✓ Drei Modi: Blitztext (Roh), Blitztext+ (Stil-Rewrite), Blitztext $%&! (Deeskalation) via gpt-4o-mini — existing
- ✓ Output in Zwischenablage, optional Auto-Insert via simuliertem ⌘V (Accessibility) — existing
- ✓ Settings-Persistierung (UserDefaults JSON) inkl. Modus, Schreibstil, Custom-Prompt, Kontext, Eigennamen-Glossar — existing
- ✓ Aufnahme-Historie (`~/Library/Application Support/BlitzText/history.json`) mit Replay/Re-Rewrite — existing
- ✓ Optionale Speaker-Diarization via FluidAudio (anonyme `Sprecher 1: …`-Annotationen) — existing
- ✓ Menu-Bar-UI mit Popover-HUD (SwiftUI + AppKit) — existing
- ✓ Build-Pipeline: XcodeGen + ad-hoc-Signing für stabile TCC-Permissions — existing

### Active

<!-- Aktuelle Hypothesen — Build-Reihenfolge wird in ROADMAP.md festgelegt. -->

- [ ] **Persistente Sprecher-Profile**: bekannte Stimmen lokal als Embedding-Profil speichern und in künftigen Aufnahmen automatisch zuordnen (`Sprecher 1` → echte Namen). Rein on-device, kein externer Dienstleister.
- [ ] **Sprecher-Verwaltung in Settings**: neuer Tab zum Anzeigen, Umbenennen, Mergen und Löschen von Profilen; Threshold-Slider; Erst-Enrollment-Flow.
- [ ] **Doku-Drift schließen**: API-Key tatsächlich in Keychain ablegen (aktuell UserDefaults), Hotkey-Debounce harmonisieren (50 ms vs. dokumentierte 250 ms), `LocalWhisperClient`-Stub-Doku korrigieren.
- [ ] **Diarization-UX**: Modell-Download mit Progress-UI sichtbar machen (~80 MB silent download).
- [ ] **Test-Fundament**: minimales XCTest-Target mit Fokus auf Hotkey-State-Machine, Pipeline-Fehlerpfade, Sprecher-Profil-Matching.

### Out of Scope (für aktuelle Milestone)

- **Cloud-basierte Speaker-ID** (AssemblyAI, Deepgram, Speechmatics) — Datenschutz und Kosten; lokal ist machbar (FluidAudio liefert Embedding-API frei Haus). *Permanent ausgeschlossen.*
- **Sandbox-Aktivierung** in dieser Phase — TCC-Handling für Hotkey + Auto-Insert ohne Sandbox stabilisieren, erst danach ziehen. *Späteres Milestone.*
- **Streaming-Whisper / Echtzeit-Transkription** — separates Backlog-Item, nicht Teil der Sprecher-Profil-Initiative.
- **Mehrsprachige UI** — UI bleibt vorerst Deutsch; Code-Identifier Englisch.

### Backlog (vorgemerkt für künftige Roadmap)

<!-- Werden als 999.x-Backlog-Phasen registriert, sobald ROADMAP.md existiert. -->

- **iOS-/iPadOS-Port** — Vision: BlitzText als mobile App. Andere Hotkey-/Trigger-Modelle (Keyboard-Shortcut, Action-Button, Share-Sheet), aber dieselbe Transkriptions-/Rewrite-Pipeline. Erst sinnvoll, wenn macOS-Version stabil und FluidAudio iOS-Support geprüft.
- **Meeting-Transkription** — längere Aufnahmen mit aktivierter Diarization, eigene UI/Workflow (kein Auto-Paste, sondern Speichern + Anzeigen mit Sprecher-Annotationen). Profitiert direkt von den persistenten Sprecher-Profilen aus der aktuellen Milestone.
- **Meeting-Zusammenfassungen** — auf Meeting-Transkripten aufgesetzt: gpt-4o-mini (oder lokal Apple Foundation Models ab macOS 26) erstellt Action-Items, Entscheidungen, offene Fragen. Hängt am Meeting-Transkriptions-Backlog-Item.

## Context

**Technisches Umfeld:**
- macOS 26+ (Apple Silicon), Swift 6 mit `SWIFT_STRICT_CONCURRENCY: minimal`, SwiftUI + AppKit, kein Sandbox im MVP.
- Bestehende Codebasis ~30 Swift-Dateien (~3-4k LOC), klare Modul-Trennung unter `BlitzText/{App,Audio,Hotkeys,Insertion,MenuBar,Modes,ProperNouns,Rewrite,Settings,Transcription,History,Permissions}`.
- Backend-Abstraktion über `TranscriptionService`-Protokoll erlaubt parallele Backends (OpenAI/Parakeet/WhisperKit).
- FluidAudio liefert für Diarization bereits `SpeakerManager`, `Speaker` (Codable, mit Embedding und EMA-Update), `initializeKnownSpeakers`, `extractSpeakerEmbedding`, `findSpeaker`, `mergeSpeaker` — die meisten Bausteine für persistente Profile sind also schon verfügbar.

**Bekannte Schmerzpunkte (aus `.planning/codebase/CONCERNS.md`):**
- API-Key liegt in UserDefaults plain (`Keychain.swift` existiert, ist aber ungenutzt) → Doku in `ARCHITECTURE.md` stimmt nicht.
- Null automatisierte Tests; kein Test-Target im `project.yml`.
- Hotkey-Debounce 50 ms vs. dokumentierte 250 ms.
- `CGEventTap` startet nach Accessibility-Grant nicht automatisch neu (App-Relaunch nötig).
- History speichert Klartext, kein Opt-Out und keine Auto-Purge.
- Diarization-Modell wird ohne Progress-UI heruntergeladen.

**Daten-Sensitivität:**
- Audio-Aufnahmen werden in temp-WAVs gehalten und nach Transkription gelöscht.
- Sprecher-Embeddings sind biometrisch-relevant (DSGVO Art. 9) — müssen lokal bleiben, idealerweise verschlüsselt at rest.

## Constraints

- **Tech-Stack**: Swift 6, SwiftUI + AppKit, FluidAudio (Parakeet + Diarizer), keine zusätzlichen Cloud-Dienste — Lock-in vermeiden, lokale Verarbeitung als Markenversprechen.
- **Sicherheit/Privacy**: Sprecher-Embeddings dürfen das Gerät nicht verlassen; sensible Daten (Embeddings, History) gehören in geschützte Stores (Keychain für Schlüssel, geschützte App-Support-Dateien für Profile).
- **Performance**: End-to-end-Latenz vom Hotkey-Release bis Clipboard ≤ 3 s für typische 5–15 s-Aufnahmen; Diarization darf den Pfad nicht spürbar verlangsamen, wenn deaktiviert.
- **Kompatibilität**: macOS 26+ ist gesetzt (FluidAudio/CoreML-Anforderung); Apple Silicon-only.
- **TCC-Permissions**: Mikrofon + Bedienungshilfen nötig; App muss ohne Sandbox laufen, bis Hotkey/Auto-Insert sandbox-kompatibel sind.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Sprecher-Erkennung lokal lösen statt Managed-Service | Datenschutz (biometrische Daten), keine laufenden Kosten, FluidAudio liefert die nötige API; Trade-off: Profil-Verwaltung selbst bauen | — Pending |
| FluidAudio `SpeakerManager` als Persistenz-Backbone nutzen | Speaker ist bereits Codable, EMA-Update built-in, `initializeKnownSpeakers` existiert; Eigenbau wäre redundant | — Pending |
| Eigenständiges BlitzText-Repo (nicht Teil eines Sammel-Repos) | Sauberer Release-/PR-Flow, klare Versionsstände | ✓ Good (initial commit angelegt 2026-04-30) |
| Sandbox-Aktivierung verschoben | TCC + Hotkey + Auto-Insert ohne Sandbox erst hart stabilisieren, dann Sandbox aufsetzen | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-30 after initialization*
