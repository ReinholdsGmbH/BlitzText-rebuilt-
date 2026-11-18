import AppKit
import Combine
import SwiftUI

/// Schwebende Meeting-Pille am unteren Bildschirmrand, angelehnt an die Leiste von
/// Wispr Flow: dunkle Kapsel, ein Satz Status, höchstens zwei Knöpfe.
///
/// Sitzt unterhalb des Diktat-HUDs (das liegt 100 pt über der Unterkante), damit beide
/// gleichzeitig sichtbar bleiben, wenn während eines Meetings diktiert wird. Anders als
/// das Diktat-HUD nimmt die Pille Klicks an, aktiviert BlitzText dabei aber nicht.
@MainActor
final class MeetingPillController {
    private var panel: NSPanel?
    private let controller: MeetingController
    private var cancellables = Set<AnyCancellable>()

    static let size = NSSize(width: 460, height: 56)

    init(controller: MeetingController) {
        self.controller = controller
        controller.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange feuert vor der Änderung — eine Runde später auswerten.
                DispatchQueue.main.async { self?.update() }
            }
            .store(in: &cancellables)
    }

    private var shouldShow: Bool {
        switch controller.phase {
        // Ergebnis und Fehler bleiben stehen, bis sie weggeklickt werden (`dismissNotice`
        // setzt die Phase zurück auf `.idle`).
        case .recording, .importing, .diarizing, .transcribing, .summarizing, .finished, .failed: return true
        case .idle: return controller.showsDetectionNotice
        }
    }

    private func update() {
        if shouldShow { show() } else { hide() }
    }

    private func show() {
        if panel != nil { return }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        // Erst nach isFloatingPanel: das setzt die Ebene sonst auf .floating zurück, und die
        // Meeting-App (gleiche Ebene, aber aktiv) lag dann über der Pille.
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let host = NSHostingView(rootView: MeetingPillView(controller: controller))
        host.frame = NSRect(origin: .zero, size: Self.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 36))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Die Pille im Stil der Flow-Leiste: eine kleine schwarze Kapsel. Während der Aufnahme nur
/// Pegelbalken, Laufzeit und ein grünes Stopp-Quadrat, wie auf wisprflow.ai zu sehen.
struct MeetingPillView: View {
    @ObservedObject var controller: MeetingController

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 36)
            .background(
                Capsule().fill(MeetingTheme.vast950)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            )
            .foregroundStyle(MeetingTheme.sand50)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: controller.phase)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .recording where controller.meetingEndSuggested:
            Image(systemName: "phone.down.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(MeetingTheme.glow300)
            VStack(alignment: .leading, spacing: 0) {
                Text("Meeting beendet?").font(.system(size: 12, weight: .semibold))
                Text("Die Meeting-App nutzt das Mikrofon nicht mehr.").font(.system(size: 10))
                    .foregroundStyle(MeetingTheme.sand50.opacity(0.6))
            }
            Button("Weiter") { controller.keepRecording() }
                .buttonStyle(PillChoiceStyle(prominent: false))
            Button("Stoppen") { controller.stop() }
                .buttonStyle(PillChoiceStyle(prominent: true))

        case .recording(let startedAt):
            LevelBars(level: { controller.microphoneLevel })
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(MeetingMarkdown.clock(context.date.timeIntervalSince(startedAt), alwaysHours: false))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(MeetingTheme.sand50.opacity(0.7))
            }
            StopSquare { controller.stop() }

        case .importing:
            progress("Importiere …")
        case .diarizing:
            progress("Erkenne Sprecher …")
        case .transcribing(let done, let total):
            progress(total == 0 ? "Transkribiere …" : "Transkribiere \(done)/\(total)")
        case .summarizing:
            progress("Schreibe Notizen …")

        case .finished where controller.accidentalFolder != nil:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(MeetingTheme.glow300)
            VStack(alignment: .leading, spacing: 0) {
                Text("Versehentlich gestartet?").font(.system(size: 12, weight: .semibold))
                Text("Nur wenige Wörter erfasst.").font(.system(size: 10)).foregroundStyle(MeetingTheme.sand50.opacity(0.6))
            }
            Button("Verwerfen") { controller.resolveAccidental(keep: false) }
                .buttonStyle(PillChoiceStyle(prominent: false))
            Button("Behalten") { controller.resolveAccidental(keep: true) }
                .buttonStyle(PillChoiceStyle(prominent: true))

        case .finished(_, let warning, let unnamed) where !controller.showsDetectionNotice:
            Circle().fill(warning == nil ? MeetingTheme.success : MeetingTheme.glow300).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text("Notizen fertig").font(.system(size: 12, weight: .semibold))
                if let warning {
                    Text(warning).font(.system(size: 10)).foregroundStyle(MeetingTheme.sand50.opacity(0.55)).lineLimit(1)
                } else if unnamed > 0 {
                    Text(unnamed == 1 ? "1 Sprecher zuordnen" : "\(unnamed) Sprecher zuordnen")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(MeetingTheme.glow300)
                }
            }
            .frame(maxWidth: 200, alignment: .leading)
            Button("Öffnen") {
                controller.openLastMeeting()
                controller.dismissNotice()
            }
            .buttonStyle(LavenderButtonStyle(compact: true))
            CloseButton { controller.dismissNotice() }

        case .failed(let message) where !controller.showsDetectionNotice:
            Circle().fill(MeetingTheme.coral).frame(width: 7, height: 7)
            Text(message).font(.system(size: 11)).lineLimit(2).frame(maxWidth: 260, alignment: .leading)
            CloseButton { controller.dismissNotice() }

        default:
            Image(systemName: "waveform").font(.system(size: 11, weight: .bold)).foregroundStyle(MeetingTheme.dawn500)
            Text(noticeTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Button("Aufnehmen") { controller.start() }
                .buttonStyle(LavenderButtonStyle(compact: true))
            CloseButton { controller.dismissNotice() }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            CyclingBars()
            Text(text).font(.system(size: 12, weight: .medium).monospacedDigit())
        }
        .padding(.trailing, 8)
    }

    private var noticeTitle: String {
        guard let name = controller.activeSources.first?.displayName else { return "Meeting erkannt" }
        return "\(name)-Meeting erkannt"
    }
}

/// Fünf weiße Pegelbalken, die dem Mikrofon folgen.
private struct LevelBars: View {
    let level: () -> Float
    private let weights: [CGFloat] = [0.45, 0.8, 1, 0.7, 0.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let value = CGFloat(min(1, max(0, level() * 6)))
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(weights.indices, id: \.self) { i in
                    let wobble = 0.5 + 0.5 * sin(t * 9 + Double(i) * 1.3)
                    Capsule()
                        .fill(MeetingTheme.sand50)
                        .frame(width: 3, height: 4 + 14 * weights[i] * max(0.12, value * CGFloat(0.65 + 0.35 * wobble)))
                }
            }
            .frame(height: 20)
        }
    }
}

/// Ruhig wandernde Balken als Arbeitsanzeige, statt eines System-Spinners.
private struct CyclingBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(MeetingTheme.dawn500)
                        .frame(width: 3, height: 5 + 9 * (0.5 + 0.5 * sin(t * 5 - Double(i) * 0.8)))
                }
            }
            .frame(height: 16)
        }
    }
}

/// Grünes Stopp-Quadrat wie in Wispr Flows Aufnahmeleiste.
private struct StopSquare: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(MeetingTheme.success)
                .frame(width: 10, height: 10)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Aufnahme beenden")
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : 0)))
                .foregroundStyle(MeetingTheme.sand50.opacity(0.6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Ausblenden")
    }
}

/// Knöpfe wie in Wispr Flows „Started by mistake?“: dunkelgrau und cremefarben.
private struct PillChoiceStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .fixedSize()
            .foregroundStyle(prominent ? MeetingTheme.vast950 : MeetingTheme.sand50)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(prominent ? MeetingTheme.vast50 : Color.white.opacity(0.12))
                .opacity(configuration.isPressed ? 0.75 : 1))
    }
}
