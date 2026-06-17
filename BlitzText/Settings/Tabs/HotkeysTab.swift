import SwiftUI
import AppKit

// MARK: - Hotkey-Recorder

/// Verwaltet den NSEvent-Monitor während des Aufnahme-Modus.
/// Läuft auf dem Main-Thread (NSEvent.addLocalMonitorForEvents liefert auf Main).
@MainActor
final class KeyRecorderViewModel: ObservableObject {
    @Published var liveModifiers: Set<HotkeyModifier> = []
    @Published var peakModifiers: Set<HotkeyModifier> = []
    private var monitor: Any?

    var liveDisplay: String {
        let mods = liveModifiers.isEmpty ? peakModifiers : liveModifiers
        if mods.isEmpty { return "Drücke Tastenkombination …" }
        return HotkeyModifier.allCases.filter { mods.contains($0) }.map { $0.symbol }.joined()
    }

    func start(onCommit: @escaping (HotkeyBinding?) -> Void) {
        liveModifiers = []
        peakModifiers = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.handleFlagsChanged(event, onCommit: onCommit)
            } else if event.type == .keyDown {
                self.handleKeyDown(event, onCommit: onCommit)
            }
            return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        liveModifiers = []
        peakModifiers = []
    }

    private func handleFlagsChanged(_ event: NSEvent, onCommit: @escaping (HotkeyBinding?) -> Void) {
        var mods: Set<HotkeyModifier> = []
        let flags = event.modifierFlags
        if flags.contains(.function) { mods.insert(.fn) }
        if flags.contains(.shift)    { mods.insert(.shift) }
        if flags.contains(.control)  { mods.insert(.control) }
        if flags.contains(.option)   { mods.insert(.option) }
        if flags.contains(.command)  { mods.insert(.command) }
        liveModifiers = mods
        if mods.count > peakModifiers.count { peakModifiers = mods }
        if mods.isEmpty && !peakModifiers.isEmpty {
            let binding = HotkeyBinding(modifiers: peakModifiers)
            stop()
            onCommit(binding)
        }
    }

    private func handleKeyDown(_ event: NSEvent, onCommit: @escaping (HotkeyBinding?) -> Void) {
        if event.keyCode == 53 { // Escape → Abbrechen
            stop()
            onCommit(nil)
        } else {
            let label = keyLabel(for: event)
            let binding = HotkeyBinding(modifiers: liveModifiers, keyCode: event.keyCode, keyLabel: label)
            stop()
            onCommit(binding)
        }
    }

    private func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case 0x7A: return "F1";  case 0x78: return "F2";  case 0x63: return "F3"
        case 0x76: return "F4";  case 0x60: return "F5";  case 0x61: return "F6"
        case 0x62: return "F7";  case 0x64: return "F8";  case 0x65: return "F9"
        case 0x6D: return "F10"; case 0x67: return "F11"; case 0x6F: return "F12"
        case 0x31: return "Space"
        case 0x24: return "↩"
        case 0x7B: return "←"; case 0x7C: return "→"; case 0x7D: return "↓"; case 0x7E: return "↑"
        default:   return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}

// MARK: - Hotkeys Tab (Phase 7)

// MARK: HotkeysTab

struct HotkeysTab: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // HOLD-HOTKEYS Section
            VStack(alignment: .leading, spacing: 8) {
                Text("HOLD-HOTKEYS").font(.caption).foregroundStyle(.secondary).bold()
                Text("Halten → Aufnahme; schneller Doppeltipp → Toggle-Modus")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Mode.allCases) { HotkeyRecorderRow(mode: $0) }
            }
        }
    }
}

/// Interaktive Zeile für eine Hotkey-Bindung in den Settings.
/// Zeigt die aktuelle Bindung und erlaubt dem User, eine neue aufzuzeichnen.
struct HotkeyRecorderRow: View {
    let mode: Mode
    @EnvironmentObject var settings: SettingsStore
    @State private var isRecording = false
    @StateObject private var recorder = KeyRecorderViewModel()

    var body: some View {
        HStack(spacing: 8) {
            Text(mode.title)
                .frame(minWidth: 110, alignment: .leading)
            Spacer()
            if isRecording {
                recordingField
            } else {
                displayField
            }
        }
        .onDisappear {
            recorder.stop()
            isRecording = false
        }
    }

    @ViewBuilder
    private var displayField: some View {
        Text(settings.hotkeyBinding(for: mode).displayString)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

        Button("Ändern") { startRecording() }

        Button {
            settings.setHotkeyBinding(.defaultBinding(for: mode), for: mode)
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Standard wiederherstellen")
    }

    @ViewBuilder
    private var recordingField: some View {
        Text(recorder.liveDisplay)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: 160, alignment: .leading)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1))

        Button {
            recorder.stop()
            isRecording = false
        } label: {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Abbrechen")
    }

    private func startRecording() {
        isRecording = true
        recorder.start { binding in
            if let b = binding, !b.isEmpty {
                settings.setHotkeyBinding(b, for: mode)
            }
            isRecording = false
        }
    }
}
