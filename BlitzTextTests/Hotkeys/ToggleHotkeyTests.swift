@testable import BlitzText
import XCTest

/// Tests fuer die testbaren Seams der Toggle-Hotkey-Funktionalitaet:
///   - SC-2: SettingsStore-Persistenz (Snapshot-Roundtrip via save/load)
///   - SC-2: Validierungslogik (Doppelbelegung, fn-Modifier, Nur-Modifier)
///   - SC-4: Conflict-Detection (bekannte System-Hotkeys)
///   - SC-1: Hold-Bindings unberuehrt nach Toggle-Operationen (Regression-Check)
///
/// Was NICHT testbar ist: Carbon/KeyboardShortcuts-Registrierung (braucht laufende App).
/// Die Tests pinnen den testbaren Seam als Regression-Schutz.
final class ToggleHotkeyTests: XCTestCase {

    var settings: SettingsStore!

    override func setUp() {
        super.setUp()
        settings = SettingsStore()
        // Sauber starten — alle Toggle-Bindings auf nil zuruecksetzen
        settings.setToggleHotkeyBinding(nil, for: .blitztext)
        settings.setToggleHotkeyBinding(nil, for: .blitztextPlus)
        settings.setToggleHotkeyBinding(nil, for: .blitztextRant)
        // Zustand sofort persistieren, damit spaetere load()-Aufrufe sauber starten
        settings.save()
    }

    // MARK: - SC-2: SettingsStore-Persistenz

    /// Snapshot-Roundtrip: Toggle-Binding wird gesetzt, via save() persistiert,
    /// und von einem neuen SettingsStore korrekt geladen.
    func testToggleBinding_snapshotRoundtrip() {
        let binding = HotkeyBinding(modifiers: [.command, .shift], keyCode: 0x0B, keyLabel: "B")
        settings.setToggleHotkeyBinding(binding, for: .blitztext)
        // save() ist internal — direkt aufrufbar (kein Debounce-Warten noetig)
        settings.save()

        // Neuer SettingsStore liest den gerade gespeicherten Zustand
        let settings2 = SettingsStore()
        let loaded = settings2.toggleHotkeyBinding(for: .blitztext)

        XCTAssertNotNil(loaded, "Toggle-Binding sollte nach Roundtrip nicht nil sein")
        XCTAssertEqual(loaded?.keyCode, 0x0B, "keyCode muss nach Roundtrip identisch sein")
        XCTAssertTrue(
            loaded?.modifiers.contains(.command) ?? false,
            "command-Modifier muss nach Roundtrip erhalten bleiben"
        )
        XCTAssertTrue(
            loaded?.modifiers.contains(.shift) ?? false,
            "shift-Modifier muss nach Roundtrip erhalten bleiben"
        )
    }

    // MARK: - SC-2: Doppelbelegung

    /// Doppelbelegungs-Erkennung: Wenn .blitztext bereits mit ⌘⇧B belegt ist,
    /// muss die Validierungslogik fuer .blitztextPlus einen Konflikt zurueckgeben.
    func testDuplicateBinding_detectedInState() {
        let binding = HotkeyBinding(modifiers: [.command, .shift], keyCode: 0x0B, keyLabel: "B")
        settings.setToggleHotkeyBinding(binding, for: .blitztext)

        // Validierungslogik (analog zu ToggleHotkeyRow.handleCommit in SettingsView.swift):
        // Fuer den Modus .blitztextPlus alle anderen Modi pruefen
        var conflictFound = false
        for other in Mode.allCases where other != .blitztextPlus {
            if let existing = settings.toggleHotkeyBinding(for: other), existing == binding {
                conflictFound = true
                break
            }
        }

        XCTAssertTrue(
            conflictFound,
            "Doppelbelegung muss erkannt werden: ⌘⇧B ist bereits fuer .blitztext vergeben"
        )
    }

    // MARK: - SC-2: fn-Modifier-Validierung

    /// fn-Modifier hat kein Carbon-Aequivalent und wird als ungueltig identifiziert.
    /// Die Validierung prueft binding.modifiers.contains(.fn) — dieser Test pinnt
    /// dass .fn in der modifiers-Menge sichtbar ist.
    func testFnModifier_invalidForToggle() {
        let binding = HotkeyBinding(modifiers: [.fn, .command], keyCode: 0x0B, keyLabel: "B")

        XCTAssertTrue(
            binding.modifiers.contains(.fn),
            "fn-Modifier muss in modifiers-Set erkennbar sein — Validierung kann darauf pruefen"
        )
        XCTAssertFalse(
            binding.isModifierOnly,
            "fn+⌘B ist kein Nur-Modifier-Binding (keyCode vorhanden)"
        )
        // Carbon-Guard: fn-Modifier wird in registerToggleHotkey() explizit abgelehnt
        // (guard !binding.modifiers.contains(.fn) in HotkeyManager.registerToggleHotkey)
        XCTAssertEqual(
            HotkeyModifier.fn.carbonModifierFlag,
            0,
            "fn.carbonModifierFlag muss 0 sein (kein Carbon-Aequivalent)"
        )
    }

    // MARK: - SC-2: Nur-Modifier-Validierung

    /// Ein Binding ohne keyCode (nur Modifier) ist isModifierOnly = true und
    /// wird von der Validierung als ungueltig abgelehnt.
    func testModifierOnly_invalid() {
        let binding = HotkeyBinding(modifiers: [.command, .shift], keyCode: nil, keyLabel: nil)

        XCTAssertTrue(
            binding.isModifierOnly,
            "Binding ohne keyCode muss isModifierOnly = true sein — Validierung muss ablehnen"
        )
        XCTAssertFalse(
            binding.isEmpty,
            "Binding mit Modifiern aber ohne keyCode ist nicht isEmpty (hat Modifier)"
        )
    }

    // MARK: - SC-4: Conflict-Detection

    /// ⌘Space ist ein bekannter Spotlight-Hotkey. Die Konflikt-Erkennungslogik
    /// (analog zu HotkeysTab.conflictingModes in SettingsView.swift) muss diesen
    /// Konflikt zurueckgeben wenn das Binding fuer einen Mode gesetzt ist.
    func testConflict_spotlightBindingDetected() {
        let spotlightBinding = HotkeyBinding(modifiers: [.command], keyCode: 49, keyLabel: "Space")
        settings.setToggleHotkeyBinding(spotlightBinding, for: .blitztext)

        // Statische Konflikt-Liste (Subset — wie in HotkeysTab.knownConflicts)
        // HotkeyBinding ist Hashable (seit Plan 07-03) — Dictionary-Lookup funktioniert
        let knownConflicts: [HotkeyBinding: String] = [
            HotkeyBinding(modifiers: [.command], keyCode: 49, keyLabel: "Space"): "Spotlight",
            HotkeyBinding(modifiers: [.command, .option], keyCode: 49, keyLabel: "Space"): "Spotlight (Finder-Suche)",
            HotkeyBinding(modifiers: [.control], keyCode: 49, keyLabel: "Space"): "Eingabequellen wechseln",
            HotkeyBinding(modifiers: [.command, .control], keyCode: 12, keyLabel: "Q"): "Bildschirm sperren",
            HotkeyBinding(modifiers: [.command, .shift], keyCode: 20, keyLabel: "3"): "Screenshot",
        ]

        // conflictingModes-Berechnung (analog zu HotkeysTab.conflictingModes)
        let conflicts = Mode.allCases.compactMap { mode -> (Mode, String)? in
            guard let binding = settings.toggleHotkeyBinding(for: mode) else { return nil }
            guard let conflictName = knownConflicts[binding] else { return nil }
            return (mode, conflictName)
        }

        XCTAssertFalse(conflicts.isEmpty, "⌘Space muss als Spotlight-Konflikt erkannt werden")
        XCTAssertEqual(conflicts.first?.0, .blitztext, "Konflikt-Mode muss .blitztext sein")
        XCTAssertEqual(conflicts.first?.1, "Spotlight", "Konflikt-Name muss 'Spotlight' sein")
    }

    // MARK: - SC-1: Hold-Bindings Regression

    /// Hold-Bindings (fn+Modifier-Pfad) duerfen durch Toggle-Operationen nicht
    /// veraendert werden. Dieser Test sichert den SC-1-Pfad als Regression-Check.
    func testHoldBindings_unaffectedByToggleOperations() {
        // Hold-Defaults vor jeglichen Toggle-Operationen erfassen
        let holdBefore = settings.hotkeyBinding(for: .blitztext)

        // Toggle-Binding setzen und anschliessend wieder loeschen
        settings.setToggleHotkeyBinding(
            HotkeyBinding(modifiers: [.command, .shift], keyCode: 0x0B, keyLabel: "B"),
            for: .blitztext
        )
        settings.setToggleHotkeyBinding(nil, for: .blitztext)

        // Hold-Default muss unveraendert sein
        let holdAfter = settings.hotkeyBinding(for: .blitztext)
        XCTAssertEqual(
            holdBefore,
            holdAfter,
            "Hold-Binding darf durch Toggle-Operationen nicht veraendert werden (SC-1)"
        )
    }
}
