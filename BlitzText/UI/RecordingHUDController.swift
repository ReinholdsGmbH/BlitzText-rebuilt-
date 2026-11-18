import AppKit
import SwiftUI
import Combine

/// Schwebendes Aufnahme-HUD am unteren Bildschirmrand mit Live-Pegel-Visualisierung.
/// Kleine schwarze Kapsel wie Wispr Flows Leiste und die Meeting-Pille; click-through, immer vorn.
@MainActor
final class RecordingHUDController {
    private var window: NSPanel?
    private let recorder: AudioRecorder
    private let processor: ModeProcessor
    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(recorder: AudioRecorder, processor: ModeProcessor, settings: SettingsStore) {
        self.recorder = recorder
        self.processor = processor
        self.settings = settings

        // Auf Recording-State hören und HUD ein-/ausblenden.
        // Phase 8 / UI-SPEC Surface 3: HUD bleibt auch während .transcribing und
        // .rewriting sichtbar, damit der BackendBadge VOR dem Cloud-Call sichtbar ist.
        processor.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .recording, .transcribing, .rewriting: self?.show()
                default:                                    self?.hide()
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        if window != nil { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        let hostView = NSHostingView(rootView: RecordingHUDView(recorder: recorder, processor: processor, settings: settings))
        hostView.frame = panel.contentView!.bounds
        hostView.autoresizingMask = [.width, .height]
        panel.contentView = hostView

        // Position: zentriert horizontal, etwa 100pt über Bildschirm-Unterkante des Hauptscreens
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let w: CGFloat = 240, h: CGFloat = 48
            let x = frame.midX - w / 2
            let y = frame.minY + 100
            panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }

        panel.orderFrontRegardless()
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct RecordingHUDView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var processor: ModeProcessor
    @ObservedObject var settings: SettingsStore

    private var langBadge: String {
        switch settings.transcriptionLanguage.lowercased() {
        case "":   return "AUTO"
        case "de": return "DE"
        case "en": return "EN"
        default:   return settings.transcriptionLanguage.uppercased()
        }
    }

    /// Aktiver Mode während recording/transcribing/rewriting — sonst nil.
    private var activeMode: Mode? {
        switch processor.state {
        case .recording(let m):    return m
        case .transcribing(let m): return m
        case .rewriting(let m):    return m
        default:                   return nil
        }
    }

    /// BackendBadge nur sichtbar für rewrite-fähige Modes (Plus / Rant) —
    /// `.blitztext` (plain) hat keinen Rewrite-Schritt → kein Backend-Indikator.
    private var showsBackendBadge: Bool {
        guard let mode = activeMode, mode != .blitztext else { return false }
        return true
    }

    private var backendSymbol: String {
        guard let mode = activeMode else { return "questionmark" }
        switch settings.rewriteBackend(for: mode) {
        case .openAI, .openRouter, .requesty: return "cloud"
        case .ollama:  return "server.rack"
        }
    }

    private var backendTooltip: String {
        guard let mode = activeMode else { return "" }
        switch settings.rewriteBackend(for: mode) {
        case .openAI:  return "Rewrite über OpenAI \(settings.rewriteModel) (Cloud)"
        case .ollama:  return "Rewrite lokal über Ollama (\(settings.ollamaModel))"
        case .openRouter, .requesty:
            let backend = settings.rewriteBackend(for: mode)
            let model = backend.provider.map { settings.meetingSummaryModel(for: $0) } ?? ""
            return "Rewrite über \(backend.label) mit \(model)"
        }
    }

    var body: some View {
        // Kleine Kapsel im Stil der Flow-Leiste (wie die Meeting-Pille): Modus-Symbol, fünf
        // Pegelbalken, beim Transkribieren/Umformulieren wandernde Balken.
        HStack(spacing: 9) {
            Image(systemName: modeSymbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MeetingTheme.dawn500)
            if case .recording = processor.state {
                CompactLevelBars(level: recorder.currentLevel)
            } else {
                WorkingBars()
            }
            Text(langBadge)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            if showsBackendBadge {
                Image(systemName: backendSymbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .help(backendTooltip)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(
            Capsule().fill(MeetingTheme.vast950)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        )
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modeSymbol: String {
        switch activeMode {
        case .blitztextPlus: return "sparkles"
        case .blitztextRant: return "flame.fill"
        default:             return "bolt.fill"
        }
    }
}

private struct CompactLevelBars: View {
    var level: Float
    private let weights: [CGFloat] = [0.45, 0.8, 1, 0.7, 0.4]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 4 + 14 * weights[i] * max(0.12, CGFloat(min(1, level * 1.4))))
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}

private struct WorkingBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(MeetingTheme.dawn500)
                        .frame(width: 3, height: 5 + 9 * (0.5 + 0.5 * sin(t * 5 - Double(i) * 0.8)))
                }
            }
            .frame(height: 20)
        }
    }
}
