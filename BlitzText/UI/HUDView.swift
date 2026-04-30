import SwiftUI

struct HUDView: View {
    @ObservedObject var processor: ModeProcessor
    @ObservedObject var settings: SettingsStore
    @ObservedObject var modelManager: LocalModelManager
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            languagePicker
            Divider()
            modesList
            Divider()
            footer
        }
        .frame(width: 360)
    }

    private var languagePicker: some View {
        HStack(spacing: 8) {
            Text("Sprache").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $settings.transcriptionLanguage) {
                Text("Auto").tag("")
                Text("DE").tag("de")
                Text("EN").tag("en")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("BlitzText").font(.headline)
                    Text("by Reinholds").font(.caption).foregroundStyle(.secondary)
                }
                statusLine
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Einstellungen")
        }
        .padding(12)
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch processor.state {
        case .idle: return .green
        case .recording: return .red
        case .transcribing, .rewriting: return .orange
        case .error: return .yellow
        }
    }

    private var statusText: String {
        if modelManager.isPreloading, settings.backend == .local {
            return "Lade lokales Modell …"
        }
        switch processor.state {
        case .idle: return "Bereit"
        case .recording(let m): return "Aufnahme — \(m.title)"
        case .transcribing: return "Transkribiere…"
        case .rewriting: return "Formuliere…"
        case .error(let m): return m
        }
    }

    private var modesList: some View {
        VStack(spacing: 0) {
            ForEach(Mode.allCases) { mode in
                ModeRow(mode: mode, hotkey: hotkeyLabel(for: mode), processor: processor)
                if mode != Mode.allCases.last {
                    Divider().padding(.leading, 56)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button(action: onOpenHistory) {
                Label("Verlauf", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Beenden", action: onQuit)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func hotkeyLabel(for mode: Mode) -> [String] {
        switch mode {
        case .blitztext: return ["fn", "Shift"]
        case .blitztextPlus: return ["fn", "Control"]
        case .blitztextRant: return ["fn", "Option"]
        }
    }
}

private struct ModeRow: View {
    let mode: Mode
    let hotkey: [String]
    @ObservedObject var processor: ModeProcessor

    private var isActive: Bool {
        switch processor.state {
        case .recording(let m), .transcribing(let m), .rewriting(let m): return m == mode
        default: return false
        }
    }

    private var canStart: Bool {
        if case .idle = processor.state { return true }
        if case .error = processor.state { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.systemImage)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title).font(.body).bold()
                Text(mode.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button(action: toggle) {
                    Image(systemName: isActive ? "stop.circle.fill" : "record.circle")
                        .font(.title2)
                        .foregroundStyle(isActive ? .red : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(!isActive && !canStart)
                .help(isActive ? "Aufnahme stoppen" : "Aufnahme starten (ohne Hotkey)")

                HStack(spacing: 4) {
                    ForEach(hotkey, id: \.self) { key in
                        Text(key)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func toggle() {
        Task { @MainActor in
            await processor.toggle(mode: mode)
        }
    }
}
