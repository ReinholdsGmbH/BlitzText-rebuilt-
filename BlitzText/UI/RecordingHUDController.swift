import AppKit
import SwiftUI
import Combine

/// Schwebendes Aufnahme-HUD am unteren Bildschirmrand mit Live-Pegel-Visualisierung.
/// Inspiriert von Whispr Flow — pille-förmig, click-through, immer im Vordergrund.
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

        // Auf Recording-State hören und HUD ein-/ausblenden
        processor.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .recording: self?.show()
                default:         self?.hide()
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        if window != nil { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
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

        let hostView = NSHostingView(rootView: RecordingHUDView(recorder: recorder, settings: settings))
        hostView.frame = panel.contentView!.bounds
        hostView.autoresizingMask = [.width, .height]
        panel.contentView = hostView

        // Position: zentriert horizontal, etwa 100pt über Bildschirm-Unterkante des Hauptscreens
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let w: CGFloat = 240, h: CGFloat = 56
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
    @ObservedObject var settings: SettingsStore

    private var langBadge: String {
        switch settings.transcriptionLanguage.lowercased() {
        case "":   return "AUTO"
        case "de": return "DE"
        case "en": return "EN"
        default:   return settings.transcriptionLanguage.uppercased()
        }
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.85))
                .overlay(
                    Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )

            HStack(spacing: 12) {
                PulsingDot()

                LevelBars(level: recorder.currentLevel)
                    .frame(height: 24)

                Text(langBadge)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 18)
        }
        .padding(8)
    }
}

private struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .opacity(pulsing ? 1.0 : 0.4)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

private struct LevelBars: View {
    var level: Float
    private let barCount = 12

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(barColor(index: i))
                        .frame(height: barHeight(index: i, in: proxy.size.height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(index: Int, in maxHeight: CGFloat) -> CGFloat {
        // Wellenform-Optik: mittlere Bars größer als äußere
        let center = Float(barCount - 1) / 2
        let distance = abs(Float(index) - center) / center
        let envelope = 1.0 - distance * 0.4
        let scaled = max(0.15, level * envelope)
        return CGFloat(scaled) * maxHeight
    }

    private func barColor(index: Int) -> Color {
        let active = Float(index) / Float(barCount - 1) < level + 0.1
        return active ? .white : .white.opacity(0.25)
    }
}
