import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import KeyboardShortcuts

/// Globaler Hotkey-Watcher für konfigurierbare Tastenkombinationen.
/// Nutzt CGEventTap auf .flagsChanged/.keyDown/.keyUp, weil fn nicht via Carbon RegisterEventHotKey
/// abfangbar ist. Braucht Accessibility-Permission (TCC). Ohne diese Permission liefert
/// `eventTapCreate` `nil` — wir pollen `AXIsProcessTrusted()` mit 1 Hz und installieren den Tap
/// automatisch nach, sobald der User die Permission erteilt.
final class HotkeyManager: @unchecked Sendable {

    enum Action: Sendable {
        case start
        case stop
        case toggle
    }

    /// Wert-Input fuer die pure Uebergangsfunktion `decideTransition` —
    /// haelt die fuer die Hotkey-Logik relevanten CGEvent-Modifier-Flags als
    /// reine Booleans. Wird in den Tests direkt instanziiert (kein CGEvent noetig).
    struct FlagsInput: Equatable, Sendable {
        var fn: Bool
        var shift: Bool
        var control: Bool
        var option: Bool
        var command: Bool = false
    }

    /// Standard-Bindungen (fn+Shift/Control/Option) — werden von Tests als Default genutzt.
    static let defaultBindings: [Mode: HotkeyBinding] = [
        .blitztext:     .defaultBlitztext,
        .blitztextPlus: .defaultBlitztextPlus,
        .blitztextRant: .defaultBlitztextRant,
    ]

    /// Ergebnis einer State-Machine-Entscheidung. Eine `decideTransition`-Auswertung
    /// kann mehrere Outcomes liefern (z. B. erst stop des alten Mode, dann start des neuen).
    enum Outcome: Equatable, Sendable {
        case none
        case start(Mode)
        case stop(Mode)
        case toggle(Mode)
    }

    private let settings: SettingsStore
    private let onTrigger: @Sendable (Mode, Action) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: DispatchSourceTimer?

    private var currentMode: Mode?
    private var lastTriggerAt: Date = .distantPast
    private var activeKeyMode: (mode: Mode, keyCode: UInt16)?

    init(settings: SettingsStore, onTrigger: @escaping @Sendable (Mode, Action) -> Void) {
        self.settings = settings
        self.onTrigger = onTrigger
    }

    func start() {
        let trusted = ensureAccessibilityPermission()
        Log.write("HotkeyManager.start() — AXIsProcessTrusted = \(trusted)")
        if trusted {
            installEventTap()
        } else {
            Log.write("Accessibility fehlt — Hotkeys aus, beobachte TCC-Status (1 Hz Polling).")
            startPermissionWatcher()
        }
    }

    func stop() {
        permissionTimer?.cancel()
        permissionTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func installEventTap() {
        guard eventTap == nil else { return }   // idempotent — kein doppelter Tap
        let mask = (1 << CGEventType.flagsChanged.rawValue)
                 | (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
        let unmanagedSelf = Unmanaged.passUnretained(self)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if type == .flagsChanged {
                manager.handleFlagsChanged(event: event)
            } else if type == .keyDown {
                manager.handleKeyDown(event: event)
            } else if type == .keyUp {
                manager.handleKeyUp(event: event)
            } else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Log.write("Tap disabled by system (\(type.rawValue)) — re-enable")
                if let tap = manager.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: unmanagedSelf.toOpaque()
        ) else {
            Log.write("CGEvent.tapCreate FAILED — Accessibility evtl. doch nicht erteilt.")
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
        self.runLoopSource = src
        Log.write("CGEventTap aktiv — fn-Modifier wird beobachtet.")
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

    // MARK: - Debounce

    /// Mindestabstand zwischen zwei Hold-Mode-Übergängen.
    /// 50 ms reicht, um CGEvent-Doppelfeuer beim Tasten-Loslassen zu schlucken,
    /// ist aber kurz genug, dass man fn+Shift „antippen" kann, ohne die Aufnahme
    /// zu verlieren. Quelle: empirisch ermittelt am M1, siehe ARCHITECTURE.md.
    private static let holdDebounce: TimeInterval = 0.05

    /// Mindestabstand zwischen zwei Toggle-Edges. 300 ms verhindert, dass ein
    /// Doppeltipp ungewollt zweimal toggelt (start → stop sofort danach).
    private static let toggleDebounce: TimeInterval = 0.30

    // MARK: - Detection

    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags
        let input = FlagsInput(
            fn: flags.contains(.maskSecondaryFn),
            shift: flags.contains(.maskShift),
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            command: flags.contains(.maskCommand)
        )
        Log.write("flagsChanged raw=0x\(String(flags.rawValue, radix: 16)) fn=\(input.fn) shift=\(input.shift) ctrl=\(input.control) opt=\(input.option) cmd=\(input.command)")

        // Wenn ein Key-Binding aktiv ist: prüfen ob die Modifier noch stimmen.
        if let active = activeKeyMode {
            let binding = settings.hotkeyBinding(for: active.mode)
            if !binding.matchesModifiers(input) && settings.triggerMode == .hold {
                activeKeyMode = nil
                currentMode = nil
                let trigger = self.onTrigger
                let mode = active.mode
                DispatchQueue.main.async { trigger(mode, .stop) }
            }
            return
        }

        let bindings: [Mode: HotkeyBinding] = [
            .blitztext:     settings.hotkeyForBlitztext,
            .blitztextPlus: settings.hotkeyForBlitztextPlus,
            .blitztextRant: settings.hotkeyForBlitztextRant,
        ]
        let outcomes = decideTransition(flags: input, triggerMode: settings.triggerMode, bindings: bindings, now: Date())
        let trigger = self.onTrigger
        for outcome in outcomes {
            switch outcome {
            case .none:
                continue
            case .start(let m):
                DispatchQueue.main.async { trigger(m, .start) }
            case .stop(let m):
                DispatchQueue.main.async { trigger(m, .stop) }
            case .toggle(let m):
                DispatchQueue.main.async { trigger(m, .toggle) }
            }
        }
    }

    private func handleKeyDown(event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let input = FlagsInput(
            fn: flags.contains(.maskSecondaryFn),
            shift: flags.contains(.maskShift),
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            command: flags.contains(.maskCommand)
        )
        for mode in Mode.allCases {
            let binding = settings.hotkeyBinding(for: mode)
            guard let bindingKey = binding.keyCode, bindingKey == keyCode else { continue }
            guard binding.matchesModifiers(input) else { continue }
            let now = Date()
            switch settings.triggerMode {
            case .hold:
                guard now.timeIntervalSince(lastTriggerAt) >= Self.holdDebounce else { return }
                lastTriggerAt = now
                activeKeyMode = (mode: mode, keyCode: keyCode)
                currentMode = mode
                let trigger = self.onTrigger
                DispatchQueue.main.async { trigger(mode, .start) }
            case .toggle:
                guard now.timeIntervalSince(lastTriggerAt) >= Self.toggleDebounce else { return }
                lastTriggerAt = now
                let trigger = self.onTrigger
                DispatchQueue.main.async { trigger(mode, .toggle) }
            }
            return
        }
    }

    private func handleKeyUp(event: CGEvent) {
        guard settings.triggerMode == .hold, let active = activeKeyMode else { return }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == active.keyCode else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) >= Self.holdDebounce else { return }
        lastTriggerAt = now
        activeKeyMode = nil
        currentMode = nil
        let trigger = self.onTrigger
        let mode = active.mode
        DispatchQueue.main.async { trigger(mode, .stop) }
    }

    /// Pure Uebergangsfunktion (Test-Seam) — kein I/O, kein CGEvent, kein DispatchQueue.
    /// Mode-/Timestamp-State auf `self` wird deterministisch auf Basis von `now` aktualisiert,
    /// damit Tests Sequenzen mit kontrollierter Wallclock fahren koennen.
    /// Produktionsverhalten ist byte-identisch zur vorherigen handleHold/Toggle-Implementierung
    /// (gleiche Debounce-Konstanten, gleiche Mode-Mapping-Reihenfolge, gleiche Edge-Semantik).
    /// `bindings` default = `HotkeyManager.defaultBindings` damit bestehende Tests unverändert bleiben.
    internal func decideTransition(
        flags: FlagsInput,
        triggerMode: TriggerMode,
        bindings: [Mode: HotkeyBinding] = HotkeyManager.defaultBindings,
        now: Date
    ) -> [Outcome] {
        let newMode = Mode.allCases.first { mode in
            guard let binding = bindings[mode], binding.isModifierOnly else { return false }
            return binding.matches(flags: flags)
        }

        switch triggerMode {
        case .hold:
            return holdOutcomes(newMode: newMode, now: now)
        case .toggle:
            return toggleOutcomes(newMode: newMode, now: now)
        }
    }

    private func holdOutcomes(newMode: Mode?, now: Date) -> [Outcome] {
        if newMode == currentMode { return [] }
        if now.timeIntervalSince(lastTriggerAt) < Self.holdDebounce { return [] }
        lastTriggerAt = now

        var result: [Outcome] = []
        if let active = currentMode, newMode != active {
            currentMode = nil
            result.append(.stop(active))
        }
        if let next = newMode, currentMode == nil {
            currentMode = next
            result.append(.start(next))
        }
        return result
    }

    private func toggleOutcomes(newMode: Mode?, now: Date) -> [Outcome] {
        // Nur die "Drücken"-Edge zählt: Übergang von kein Mode → ein Mode.
        guard let next = newMode else { return [] }
        if now.timeIntervalSince(lastTriggerAt) < Self.toggleDebounce { return [] }
        lastTriggerAt = now
        return [.toggle(next)]
    }

    // MARK: - Permission

    @discardableResult
    private func ensureAccessibilityPermission() -> Bool {
        // String-Wert von kAXTrustedCheckOptionPrompt — als CFString-Konstante in Swift 6
        // nicht concurrency-safe, deshalb hartkodiert.
        let opts: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(opts)
    }
}

// MARK: - HotkeyModifier

enum HotkeyModifier: Int, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case fn, command, control, option, shift

    var cgFlag: CGEventFlags {
        switch self {
        case .fn:      return .maskSecondaryFn
        case .command: return .maskCommand
        case .control: return .maskControl
        case .option:  return .maskAlternate
        case .shift:   return .maskShift
        }
    }

    var nsFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn:      return .function
        case .command: return .command
        case .control: return .control
        case .option:  return .option
        case .shift:   return .shift
        }
    }

    var symbol: String {
        switch self {
        case .fn:      return "fn"
        case .command: return "⌘"
        case .control: return "⌃"
        case .option:  return "⌥"
        case .shift:   return "⇧"
        }
    }
}

// MARK: - HotkeyBinding

struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
    var modifiers: Set<HotkeyModifier>
    var keyCode: UInt16?
    var keyLabel: String?

    init(modifiers: Set<HotkeyModifier> = [], keyCode: UInt16? = nil, keyLabel: String? = nil) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.keyLabel = keyLabel
    }

    var isModifierOnly: Bool { keyCode == nil }
    var isEmpty: Bool { modifiers.isEmpty && keyCode == nil }

    var displayString: String {
        let orderedMods = HotkeyModifier.allCases.filter { modifiers.contains($0) }
        let modStr = orderedMods.map { $0.symbol }.joined()
        let keyStr = keyLabel ?? ""
        let combined = modStr + keyStr
        return combined.isEmpty ? "–" : combined
    }

    /// Prüft ob diese Bindung exakt auf die gegebenen Modifier-Flags passt (alle erforderlichen
    /// Modifier aktiv, keine überflüssigen). Nur für modifier-only Bindungen gedacht.
    func matches(flags: HotkeyManager.FlagsInput) -> Bool {
        guard isModifierOnly else { return false }
        return matchesModifiers(flags)
    }

    /// Prüft nur die Modifier-Flags — unabhängig davon, ob keyCode vorhanden ist.
    func matchesModifiers(_ flags: HotkeyManager.FlagsInput) -> Bool {
        return flags.fn      == modifiers.contains(.fn)
            && flags.shift   == modifiers.contains(.shift)
            && flags.control == modifiers.contains(.control)
            && flags.option  == modifiers.contains(.option)
            && flags.command == modifiers.contains(.command)
    }

    static let defaultBlitztext     = HotkeyBinding(modifiers: [.fn, .shift])
    static let defaultBlitztextPlus = HotkeyBinding(modifiers: [.fn, .control])
    static let defaultBlitztextRant = HotkeyBinding(modifiers: [.fn, .option])

    static func defaultBinding(for mode: Mode) -> HotkeyBinding {
        switch mode {
        case .blitztext:     return .defaultBlitztext
        case .blitztextPlus: return .defaultBlitztextPlus
        case .blitztextRant: return .defaultBlitztextRant
        }
    }
}

// MARK: - HotkeyModifier Carbon-Konvertierung (Phase 7)

extension HotkeyModifier {
    /// Carbon-Modifier-Flag für KeyboardShortcuts.Shortcut(carbonKeyCode:carbonModifiers:).
    /// fn hat kein Carbon-Äquivalent — gibt 0 zurück. Caller muss fn-Modifier VOR dem
    /// Aufruf ablehnen (Pitfall 3 — RESEARCH.md).
    var carbonModifierFlag: Int {
        switch self {
        case .fn:      return 0                  // kein Carbon-Äquivalent
        case .command: return Int(cmdKey)         // 0x0100
        case .shift:   return Int(shiftKey)       // 0x0200
        case .option:  return Int(optionKey)      // 0x0800
        case .control: return Int(controlKey)     // 0x1000
        }
    }
}

// MARK: - KeyboardShortcuts.Name (Phase 7)

extension KeyboardShortcuts.Name {
    static let toggleBlitztext     = Self("toggleBlitztext")
    static let toggleBlitztextPlus = Self("toggleBlitztextPlus")
    static let toggleBlitztextRant = Self("toggleBlitztextRant")
}
