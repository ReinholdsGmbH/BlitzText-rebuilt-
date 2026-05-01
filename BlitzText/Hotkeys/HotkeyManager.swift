import AppKit
import CoreGraphics

/// Globaler Hotkey-Watcher für fn+Shift, fn+Control, fn+Option.
/// Nutzt CGEventTap auf .flagsChanged, weil fn nicht via Carbon RegisterEventHotKey abfangbar ist.
/// Braucht Accessibility-Permission (TCC). Ohne diese Permission liefert `eventTapCreate` `nil` —
/// wir pollen `AXIsProcessTrusted()` mit 1 Hz und installieren den Tap automatisch nach,
/// sobald der User die Permission erteilt.
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
    }

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
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let unmanagedSelf = Unmanaged.passUnretained(self)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if type == .flagsChanged {
                manager.handleFlagsChanged(event: event)
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
            option: flags.contains(.maskAlternate)
        )
        Log.write("flagsChanged raw=0x\(String(flags.rawValue, radix: 16)) fn=\(input.fn) shift=\(input.shift) ctrl=\(input.control) opt=\(input.option)")

        let outcomes = decideTransition(flags: input, triggerMode: settings.triggerMode, now: Date())
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

    /// Pure Uebergangsfunktion (Test-Seam) — kein I/O, kein CGEvent, kein DispatchQueue.
    /// Mode-/Timestamp-State auf `self` wird deterministisch auf Basis von `now` aktualisiert,
    /// damit Tests Sequenzen mit kontrollierter Wallclock fahren koennen.
    /// Produktionsverhalten ist byte-identisch zur vorherigen handleHold/Toggle-Implementierung
    /// (gleiche Debounce-Konstanten, gleiche Mode-Mapping-Reihenfolge, gleiche Edge-Semantik).
    internal func decideTransition(
        flags: FlagsInput,
        triggerMode: TriggerMode,
        now: Date
    ) -> [Outcome] {
        let newMode: Mode? = {
            guard flags.fn else { return nil }
            if flags.shift { return .blitztext }
            if flags.control { return .blitztextPlus }
            if flags.option { return .blitztextRant }
            return nil
        }()

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
