@testable import BlitzText
import XCTest

/// Tests fuer die pure State-Machine `HotkeyManager.decideTransition(flags:triggerMode:now:)`.
///
/// Test-Seam wurde in Plan 02-01 (Wave 0) eingefuehrt:
///   - `decideTransition` ist `internal`, akzeptiert injizierten `now: Date`.
///   - Hold-Debounce = 50 ms, Toggle-Debounce = 300 ms (Konstanten in HotkeyManager.swift).
///   - Mode-Mapping: fn+shift = .blitztext, fn+control = .blitztextPlus, fn+option = .blitztextRant.
///
/// Determinismus: Jeder Aufruf bekommt explizit `Date(timeIntervalSince1970: T)` —
/// keine echten Sleeps, keine Wall-Clock-Reads (Pitfall 5 in 02-RESEARCH.md).
@MainActor
final class HotkeyStateMachineTests: XCTestCase {

    // MARK: - Helpers

    private func makeManager() -> HotkeyManager {
        let settings = SettingsStore()
        return HotkeyManager(settings: settings, onTrigger: { _, _ in })
    }

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private static let allOff = HotkeyManager.FlagsInput(fn: false, shift: false, control: false, option: false)
    private static let fnShift = HotkeyManager.FlagsInput(fn: true, shift: true, control: false, option: false)
    private static let fnControl = HotkeyManager.FlagsInput(fn: true, shift: false, control: true, option: false)
    private static let fnOption = HotkeyManager.FlagsInput(fn: true, shift: false, control: false, option: true)
    private static let fnOnly = HotkeyManager.FlagsInput(fn: true, shift: false, control: false, option: false)
    private static let shiftOnly = HotkeyManager.FlagsInput(fn: false, shift: true, control: false, option: false)

    // MARK: - Hold mode (push-to-talk)

    func test_holdMode_pressAndRelease() {
        let m = makeManager()
        // press fn+shift @ t0 → start(.blitztext)
        let press = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(press, [.start(.blitztext)])

        // release @ t0+0.100 (>50 ms holdDebounce) → stop(.blitztext)
        let release = m.decideTransition(flags: Self.allOff, triggerMode: .hold, now: t(0.100))
        XCTAssertEqual(release, [.stop(.blitztext)])
    }

    func test_holdMode_modeSwitchMidPress() {
        let m = makeManager()
        _ = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        // ohne Release direkt auf fn+control wechseln, ausserhalb des Debounce-Fensters
        let switched = m.decideTransition(flags: Self.fnControl, triggerMode: .hold, now: t(0.100))
        XCTAssertEqual(switched, [.stop(.blitztext), .start(.blitztextPlus)])
    }

    func test_holdMode_pressWithoutRelease_thenCleanup() {
        let m = makeManager()
        let first = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(first, [.start(.blitztext)])
        // Identische flags & gleicher now → newMode == currentMode → idempotent (leer).
        let second = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(second, [])
    }

    func test_holdMode_fastTap_pressReleaseWithinDebounce() {
        let m = makeManager()
        let press = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(press, [.start(.blitztext)])
        // Release nach 10 ms → < 50 ms holdDebounce.
        // Beobachtetes Wave-0-Verhalten (siehe HotkeyManager.holdOutcomes,
        // Pitfall 5 in 02-RESEARCH.md): Release wird verschluckt → [].
        // currentMode bleibt damit auf .blitztext bis das Debounce-Fenster verstrichen ist.
        let release = m.decideTransition(flags: Self.allOff, triggerMode: .hold, now: t(0.010))
        XCTAssertEqual(release, [])
    }

    // MARK: - Toggle mode (Drücken)

    func test_toggleMode_firstPress_emitsToggle() {
        let m = makeManager()
        let outcome = m.decideTransition(flags: Self.fnShift, triggerMode: .toggle, now: t(0))
        XCTAssertEqual(outcome, [.toggle(.blitztext)])
    }

    func test_toggleMode_releaseEdge_emitsNothing() {
        let m = makeManager()
        _ = m.decideTransition(flags: Self.fnShift, triggerMode: .toggle, now: t(0))
        // Release-Edge im Toggle-Modus → newMode == nil → guard returns [].
        let release = m.decideTransition(flags: Self.allOff, triggerMode: .toggle, now: t(0.500))
        XCTAssertEqual(release, [])
    }

    func test_toggleMode_doubleTapWithinDebounce() {
        let m = makeManager()
        // 1. press @ t0 → toggle.
        let p1 = m.decideTransition(flags: Self.fnShift, triggerMode: .toggle, now: t(0))
        XCTAssertEqual(p1, [.toggle(.blitztext)])
        // 2. release @ t0+0.050 → ignoriert.
        _ = m.decideTransition(flags: Self.allOff, triggerMode: .toggle, now: t(0.050))
        // 3. press @ t0+0.100 (< 300 ms toggleDebounce) → debounced → [].
        let p2 = m.decideTransition(flags: Self.fnShift, triggerMode: .toggle, now: t(0.100))
        XCTAssertEqual(p2, [])
        // 4. release.
        _ = m.decideTransition(flags: Self.allOff, triggerMode: .toggle, now: t(0.150))
        // 5. press @ t0+0.350 (> 300 ms ab letztem erfolgreichen Toggle bei t0) → toggle.
        let p3 = m.decideTransition(flags: Self.fnShift, triggerMode: .toggle, now: t(0.350))
        XCTAssertEqual(p3, [.toggle(.blitztext)])
    }

    func test_toggleMode_modifierOnlyPress_noFollowUp() {
        let m = makeManager()
        // Nur fn ohne shift/control/option → newMode == nil → [].
        let outcome = m.decideTransition(flags: Self.fnOnly, triggerMode: .toggle, now: t(0))
        XCTAssertEqual(outcome, [])
    }

    // MARK: - Modifier-Kombinationen

    func test_modifiers_fullCombo_emitsStart() {
        let m = makeManager()
        let outcome = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(outcome, [.start(.blitztext)])
    }

    func test_modifiers_partialCombo_isIgnored() {
        let m = makeManager()
        // fn alleine (ohne shift/control/option) → newMode = nil → []. Kein Start.
        let fnAlone = m.decideTransition(flags: Self.fnOnly, triggerMode: .hold, now: t(0))
        XCTAssertEqual(fnAlone, [])
        // shift alleine (ohne fn) → guard flags.fn → newMode = nil → [].
        let shiftAlone = m.decideTransition(flags: Self.shiftOnly, triggerMode: .hold, now: t(0.100))
        XCTAssertEqual(shiftAlone, [])
    }

    func test_modifiers_releaseOrderInvariance_shiftFirst() {
        let m = makeManager()
        _ = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        // Release shift-first → flags = fn only → newMode = nil → stop(.blitztext).
        let r1 = m.decideTransition(flags: Self.fnOnly, triggerMode: .hold, now: t(0.100))
        XCTAssertEqual(r1, [.stop(.blitztext)])
        // Anschliessend fn release → currentMode bereits nil → [].
        let r2 = m.decideTransition(flags: Self.allOff, triggerMode: .hold, now: t(0.200))
        XCTAssertEqual(r2, [])
    }

    func test_modifiers_releaseOrderInvariance_fnFirst() {
        let m = makeManager()
        _ = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        // Release fn-first → flags = shift only → guard fn → newMode = nil → stop(.blitztext).
        let r1 = m.decideTransition(flags: Self.shiftOnly, triggerMode: .hold, now: t(0.100))
        XCTAssertEqual(r1, [.stop(.blitztext)])
        // Anschliessend shift release → currentMode bereits nil → [].
        let r2 = m.decideTransition(flags: Self.allOff, triggerMode: .hold, now: t(0.200))
        XCTAssertEqual(r2, [])
    }

    func test_modifiers_secondCombo_switchesMode() {
        let m = makeManager()
        let p1 = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(p1, [.start(.blitztext)])
        // Wechsel auf fn+control ohne vollstaendigen Release, ausserhalb Debounce.
        let p2 = m.decideTransition(flags: Self.fnControl, triggerMode: .hold, now: t(0.100))
        XCTAssertEqual(p2, [.stop(.blitztext), .start(.blitztextPlus)])
    }

    // MARK: - Debounce / Fast-Release (Hold mode)

    /// Pinnt das Wave-0-Verhalten: ein Release innerhalb des 50 ms Hold-Debounce-Fensters
    /// wird verschluckt (siehe `holdOutcomes` in BlitzText/Hotkeys/HotkeyManager.swift —
    /// die Debounce-Bedingung `now - lastTriggerAt < holdDebounce` filtert release-Edges
    /// genauso wie press-Edges). Verweis: 02-RESEARCH.md § Pitfall 5.
    func test_fastRelease_withinDebounce() {
        let m = makeManager()
        let press = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(press, [.start(.blitztext)])
        // Release @ t0+0.020 (< 50 ms) → debounced → [].
        let release = m.decideTransition(flags: Self.allOff, triggerMode: .hold, now: t(0.020))
        XCTAssertEqual(release, [])
    }

    func test_fastRelease_afterDebounce() {
        let m = makeManager()
        let press = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(press, [.start(.blitztext)])
        // Release @ t0+0.080 (> 50 ms holdDebounce) → stop emittiert.
        let release = m.decideTransition(flags: Self.allOff, triggerMode: .hold, now: t(0.080))
        XCTAssertEqual(release, [.stop(.blitztext)])
    }

    func test_debounce_twoPressesCollapseToOne() {
        let m = makeManager()
        let p1 = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(p1, [.start(.blitztext)])
        // Identische Press-Edge nach 10 ms — newMode == currentMode → [] (idempotent,
        // Debounce greift erst gar nicht, weil schon der Mode-Vergleich abkuerzt).
        let p2 = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0.010))
        XCTAssertEqual(p2, [])
    }

    func test_debounce_twoPressesAfterWindow() {
        let m = makeManager()
        let p1 = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0))
        XCTAssertEqual(p1, [.start(.blitztext)])
        let r1 = m.decideTransition(flags: Self.allOff, triggerMode: .hold, now: t(0.100))
        XCTAssertEqual(r1, [.stop(.blitztext)])
        let p2 = m.decideTransition(flags: Self.fnShift, triggerMode: .hold, now: t(0.200))
        XCTAssertEqual(p2, [.start(.blitztext)])
    }
}
