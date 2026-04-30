# Phase 1: Stabilisierung & Doku-Drift — Pattern Map

**Mapped:** 2026-04-30
**Files analyzed:** 6 (4 source + 2 docs)
**Analogs found:** 6 / 6 (all in-repo — modifications, not green-field)

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `BlitzText/Settings/SettingsStore.swift` (STAB-01) | store / settings | request-response (sync getter/setter) | `BlitzText/Settings/Keychain.swift` (already in repo, dormant) | exact — Keychain API was designed for exactly this migration |
| `BlitzText/Settings/Keychain.swift` (STAB-01) | utility / wrapper | request-response | self (no changes needed; already complete) | n/a — reference impl |
| `BlitzText/Hotkeys/HotkeyManager.swift` (STAB-02 + STAB-03) | input adapter / event tap | event-driven (CGEventTap callbacks) | self (debounce constant lives here) + `BlitzText/Settings/PermissionsHelper.swift` for AX-status reads | exact for STAB-02; role-match for STAB-03 (need new permission-watcher pattern) |
| `BlitzText/Settings/PermissionsHelper.swift` (STAB-03) | permissions facade | request-response (status getters) | self — extend with watcher API | exact (extension, not new pattern) |
| `.planning/codebase/ARCHITECTURE.md` (STAB-02 + STAB-04) | docs | n/a | self | exact (in-place edits) |
| `RISKS.md` (STAB-04) — repo root, must verify exists | docs | n/a | `.planning/codebase/CONCERNS.md` style | role-match |

## Pattern Assignments

### `BlitzText/Settings/SettingsStore.swift` (STAB-01: API-Key → Keychain)

**Analog:** `BlitzText/Settings/Keychain.swift` (already in repo, never wired up — exactly the use case it was built for).

**Keychain API to call** (`Keychain.swift:11-65`):

```swift
final class Keychain: @unchecked Sendable {
    static let shared = Keychain(service: "de.reinholds.blitztext")
    let service: String
    init(service: String) { self.service = service }

    @discardableResult
    func write(value: String, account: String) -> Bool { ... }   // delete-then-add, kSecAttrAccessibleWhenUnlocked
    func read(account: String) -> String? { ... }                // returns nil + logs OSStatus on non-notFound errors
    @discardableResult
    func delete(account: String) -> Bool { ... }
}
```

The constants required by STAB-01 (`Service: de.reinholds.blitztext`, `Account: openai-api-key`) align with the existing `Keychain.shared` — only the account string is new.

**Current `apiKey` shape to replace** (`SettingsStore.swift:31-42`):

```swift
var apiKey: String {
    get { UserDefaults.standard.string(forKey: Self.apiKeyDefaultsKey) ?? "" }
    set {
        if newValue.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.apiKeyDefaultsKey)
        } else {
            UserDefaults.standard.set(newValue, forKey: Self.apiKeyDefaultsKey)
        }
        objectWillChange.send()
    }
}
private static let apiKeyDefaultsKey = "de.reinholds.blitztext.apiKey"
```

**Target shape** — keep the same string getter/setter contract (callers in `WhisperAPIClient.swift:16`, `SettingsView.swift:230,240,268` access `settings.apiKey` synchronously, do NOT change them):

```swift
private static let apiKeyKeychainAccount = "openai-api-key"
private static let apiKeyLegacyDefaultsKey = "de.reinholds.blitztext.apiKey"   // kept for migration

var apiKey: String {
    get { Keychain.shared.read(account: Self.apiKeyKeychainAccount) ?? "" }
    set {
        if newValue.isEmpty {
            Keychain.shared.delete(account: Self.apiKeyKeychainAccount)
        } else {
            Keychain.shared.write(value: newValue, account: Self.apiKeyKeychainAccount)
        }
        objectWillChange.send()
    }
}
```

**One-time migration pattern** — `init()` body, runs after `load()`:

```swift
init() {
    load()
    migrateAPIKeyFromUserDefaultsIfNeeded()       // <— new, idempotent
    objectWillChange
        .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.save() }
        .store(in: &cancellables)
}

private func migrateAPIKeyFromUserDefaultsIfNeeded() {
    let defaults = UserDefaults.standard
    guard let legacy = defaults.string(forKey: Self.apiKeyLegacyDefaultsKey),
          !legacy.isEmpty else { return }
    if Keychain.shared.read(account: Self.apiKeyKeychainAccount) == nil {
        if Keychain.shared.write(value: legacy, account: Self.apiKeyKeychainAccount) {
            Log.write("SettingsStore: API-Key von UserDefaults nach Keychain migriert")
        } else {
            Log.write("SettingsStore: API-Key Migration fehlgeschlagen — UserDefaults-Eintrag bleibt erhalten")
            return                                  // do NOT delete legacy if write failed
        }
    }
    defaults.removeObject(forKey: Self.apiKeyLegacyDefaultsKey)
}
```

**Logging pattern** — already used by `Keychain.swift:31`:

```swift
Log.write("Keychain write failed for \(account): OSStatus \(status)")
```

**Sync-getter constraint:** Callers like `WhisperAPIClient.transcribe` (`WhisperAPIClient.swift:16`) read `settings.apiKey` from a non-MainActor `@unchecked Sendable` class. `Keychain.read` is synchronous and Sendable-safe (the class is `@unchecked Sendable`), so the existing call-site shape works unchanged.

**SettingsView UI string update** — `SettingsView.swift:245-246` currently reads:

```swift
Text("Der Schlüssel liegt in den User-Defaults unter `~/Library/Preferences/de.reinholds.blitztext.plist` (geschützt durch dein User-Login). Bei späterer Distribution mit Apple-Developer-ID wechseln wir zur macOS-Keychain.")
```

After migration this string becomes a lie — replace with a Keychain-accurate German version (e.g. "Der Schlüssel liegt in deinem macOS-Schlüsselbund (Service: `de.reinholds.blitztext`).").

---

### `BlitzText/Hotkeys/HotkeyManager.swift` (STAB-02: Debounce konsistent)

**Current shape** (`HotkeyManager.swift:108-132`):

```swift
private func handleHoldTransition(newMode: Mode?) {
    if newMode == currentMode { return }
    // Debounce
    if Date().timeIntervalSince(lastTriggerAt) < 0.05 { return }   // 50 ms — disagrees with ARCHITECTURE.md (which claims 250 ms)
    lastTriggerAt = Date()
    ...
}

private func handleToggleTransition(newMode: Mode?) {
    guard let next = newMode else { return }
    if Date().timeIntervalSince(lastTriggerAt) < 0.3 { return }    // 300 ms — also disagrees with ARCHITECTURE.md (line 208: "50 ms hold, 300 ms toggle")
    ...
}
```

ARCHITECTURE.md is internally inconsistent: the **anti-pattern table comments at line 208** already say "50 ms hold, 300 ms toggle" matching code, but elsewhere "250 ms" is referenced (per scope brief — confirm during execution by grepping the doc). Decision: **keep code as-is (50 / 300 ms), fix doc to match, document rationale**.

**Target shape** — extract magic numbers to named constants and keep current values:

```swift
/// Mindestabstand zwischen zwei Hold-Mode-Übergängen. 50 ms reicht, um
/// CGEvent-Doppelfeuer beim Tasten-Loslassen zu schlucken, ist aber kurz genug,
/// dass man fn+Shift „antippen" kann, ohne die Aufnahme zu verlieren.
private static let holdDebounce: TimeInterval = 0.05

/// Toggle braucht mehr Zeit, weil ein Tipp = ein State-Change. Unter 300 ms
/// würden Doppeltipps ungewollt 2× togglen (start → stop sofort).
private static let toggleDebounce: TimeInterval = 0.30

private func handleHoldTransition(newMode: Mode?) {
    if newMode == currentMode { return }
    if Date().timeIntervalSince(lastTriggerAt) < Self.holdDebounce { return }
    lastTriggerAt = Date()
    ...
}

private func handleToggleTransition(newMode: Mode?) {
    guard let next = newMode else { return }
    if Date().timeIntervalSince(lastTriggerAt) < Self.toggleDebounce { return }
    ...
}
```

**Doc fix** — `.planning/codebase/ARCHITECTURE.md:208` already says "50 ms hold, 300 ms toggle" — confirm by reading the file end-to-end and remove any stray "250 ms" mention. Add the rationale paragraph to the same section.

---

### `BlitzText/Hotkeys/HotkeyManager.swift` + `BlitzText/Settings/PermissionsHelper.swift` (STAB-03: Auto-Restart nach Permission-Grant)

**Current behavior** (`HotkeyManager.swift:29-68`): On `start()`, calls `ensureAccessibilityPermission()` once. If `false`, logs and returns — the tap is never created. There is **no observation of TCC-state changes**, so granting permission later requires app relaunch (already documented as a footgun in `SettingsView.swift:209-210`: "Nach dem Erteilen … BlitzText einmal beenden und neu starten").

**Lifecycle pattern to mirror** — `start()` and `stop()` already exist and are idempotent enough to call repeatedly (`stop()` nils out `eventTap` and `runLoopSource`):

```swift
func start() {
    let trusted = ensureAccessibilityPermission()
    Log.write("HotkeyManager.start() — AXIsProcessTrusted = \(trusted)")
    guard trusted else { return }
    ...
    self.eventTap = tap
    self.runLoopSource = src
}

func stop() {
    if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
    eventTap = nil
    runLoopSource = nil
}
```

**Target pattern** — add a poll-based watcher (no public TCC change-notification API exists on macOS; polling is the documented workaround used by every menu-bar app):

```swift
// in HotkeyManager
private var permissionTimer: DispatchSourceTimer?

func start() {
    let trusted = ensureAccessibilityPermission()
    Log.write("HotkeyManager.start() — AXIsProcessTrusted = \(trusted)")
    if trusted {
        installEventTap()
    } else {
        Log.write("Accessibility fehlt — Hotkeys aus, beobachte TCC-Status.")
        startPermissionWatcher()
    }
}

private func startPermissionWatcher() {
    guard permissionTimer == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
    timer.setEventHandler { [weak self] in
        guard let self else { return }
        if AXIsProcessTrusted() {
            Log.write("HotkeyManager: Accessibility erteilt — Tap wird gestartet.")
            self.permissionTimer?.cancel()
            self.permissionTimer = nil
            self.installEventTap()
        }
    }
    timer.resume()
    permissionTimer = timer
}

func stop() {
    permissionTimer?.cancel(); permissionTimer = nil
    // existing teardown
}
```

`installEventTap()` is the body of the current `start()` from `mask = ...` (line 36) down to `Log.write("CGEventTap aktiv …")` (line 67) — extract verbatim.

**Permission read pattern** — already in `PermissionsHelper.swift:15-17`:

```swift
static func accessibilityStatus() -> Status {
    AXIsProcessTrusted() ? .granted : .denied
}
```

`HotkeyManager` currently calls `AXIsProcessTrustedWithOptions` directly (`HotkeyManager.swift:140`); the watcher should use the prompt-free `AXIsProcessTrusted()` (no prompt on every tick) — same call PermissionsHelper uses.

**SettingsView side-effect** — once auto-restart works, the warning at `SettingsView.swift:209-210` becomes false. Either remove or reword to "Bedienungshilfen nach Erteilung sofort aktiv — kein Neustart nötig."

---

### `.planning/codebase/ARCHITECTURE.md` (STAB-02 + STAB-04)

**STAB-02 doc fix:** Confirm and align debounce numbers throughout (line 208 currently says `50 ms hold, 300 ms toggle` — matches code; if any line says `250 ms` in the file body, that's the drift to remove).

**STAB-04 doc fix:** ARCHITECTURE.md currently describes `LocalWhisperClient` correctly at lines 33-34, 61, but the scope brief flags it as drifted — re-read against `LocalWhisperClient.swift` (which is a real WhisperKit implementation with `warmUp`, `ensureLoaded`, `transcribe`). Remove any "stub" wording. Likely candidates:

- Anywhere the doc says "stub", "placeholder", "TODO", "future" about `LocalWhisperClient` → rewrite to reflect the real impl.
- `RISKS.md` (verify file exists at repo root) — same treatment.

**Doc style to mirror** — `.planning/codebase/CONCERNS.md` and existing `ARCHITECTURE.md`:
- Section headers as `## Title` / `### Sub`.
- Cross-references with file path + line number: `` `BlitzText/Hotkeys/HotkeyManager.swift:108` ``.
- Refresh marker at top: `<!-- refreshed: 2026-04-30 -->`.

---

## Shared Patterns

### Logging (apply to all four STAB-* tasks)

**Source:** `BlitzText/App/Log.swift`
**Pattern:**

```swift
Log.write("HotkeyManager.start() — AXIsProcessTrusted = \(trusted)")
Log.write("Keychain write failed for \(account): OSStatus \(status)")
```

- One-line, German or English (match the file's existing style — HotkeyManager mostly German, Keychain mostly English).
- Include identifier of subsystem at start (`HotkeyManager: …`, `SettingsStore: …`).
- For state transitions and recoverable errors only — never in hot loops.

### `@unchecked Sendable` + `final class` (HotkeyManager, Keychain)

**Pattern source:** `Keychain.swift:11`, `HotkeyManager.swift:7`

```swift
final class HotkeyManager: @unchecked Sendable { ... }
final class Keychain: @unchecked Sendable { ... }
```

When extending these classes, keep `final` and the `@unchecked Sendable` annotation. Document new mutation surface with a comment if a new var crosses actor boundaries.

### MainActor bridging from CGEvent / Timer callbacks

**Source:** `HotkeyManager.swift:117,121,131`

```swift
DispatchQueue.main.async { trigger(active, .stop) }
```

For STAB-03's `DispatchSource.makeTimerSource(queue: .main)`, the handler already runs on main — no extra hop needed. But anything called from the C-style CGEventTap callback must hop via `DispatchQueue.main.async`.

### TCC-status reads

**Source:** `PermissionsHelper.swift:15-17`

```swift
static func accessibilityStatus() -> Status {
    AXIsProcessTrusted() ? .granted : .denied
}
```

Use `AXIsProcessTrusted()` (no prompt) for polling/watching. Reserve `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` for explicit user-initiated requests (Settings → "Aktivieren" button).

### Idempotent migration pattern

**Inspiration:** `SettingsStore.load()` (`SettingsStore.swift:74-92`) reads optional fields with `?? default`, never throws, never warns on missing keys. The STAB-01 migration must be equally silent on already-migrated launches: read legacy → if absent, return; if present and Keychain has a value, just delete legacy; if present and Keychain empty, write then delete. Never block app start, never throw.

---

## No Analog Found

None — every change in Phase 1 has a strong in-repo precedent. STAB-03's permission watcher is the only genuinely new pattern, but it builds directly on the existing `start()`/`stop()` lifecycle and the `AXIsProcessTrusted()` helper.

## Metadata

**Analog search scope:** `BlitzText/Settings/`, `BlitzText/Hotkeys/`, `BlitzText/Transcription/`, `BlitzText/App/`, `.planning/codebase/`
**Files scanned:** 11
**Pattern extraction date:** 2026-04-30
