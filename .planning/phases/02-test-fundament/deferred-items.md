# Deferred Items — Phase 2 Test-Fundament

Items entdeckt waehrend Plan-Ausfuehrung, die nicht zum Plan-Scope gehoeren.

## 02-02 (HotkeyStateMachine-Tests)

- **Pre-existing uncommitted Aenderungen in `BlitzText/App/AppDelegate.swift` und `BlitzText/Settings/SettingsView.swift`** (gefunden bei Plan-Start, 2026-04-30):
  - AppDelegate: Auto-Open der Settings nur noch wenn OpenAI-Key tatsaechlich gebraucht wird (`needsOpenAIKey()` helper). Vorher: Auto-Open immer wenn `apiKey.isEmpty`.
  - SettingsView: API-Key-Label umbenannt auf "OPENAI-API-KEY" + Erklaerungstext, wann der Key gebraucht wird.
  - **Status:** Nicht von 02-02 angefasst — verbleiben uncommitted im Working Tree. Gehoeren in einen eigenen UX-Commit (vermutlich Backlog 999.x oder eine separate Feature-Aenderung). Plan-Executor hat sie absichtlich nicht eingestaged (Scope-Boundary).
