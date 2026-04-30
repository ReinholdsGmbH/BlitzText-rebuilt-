import AppKit
import SwiftUI
import Combine

/// Schwebender Toast unten am Display, der einen Eigennamen-Vorschlag mit Countdown anzeigt.
/// Nach Ablauf des Countdowns wird der Begriff automatisch ins Glossar aufgenommen,
/// es sei denn, der User klickt das X.
@MainActor
final class SuggestionToastController {
    private var window: NSPanel?
    private let presenter: SuggestionPresenter
    private var cancellables = Set<AnyCancellable>()

    init(presenter: SuggestionPresenter) {
        self.presenter = presenter
        presenter.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] suggestion in
                if suggestion != nil { self?.show() } else { self?.hide() }
            }
            .store(in: &cancellables)
    }

    func show() {
        if window != nil { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false

        let hostView = NSHostingView(rootView: SuggestionToastView(presenter: presenter))
        hostView.frame = panel.contentView!.bounds
        hostView.autoresizingMask = [.width, .height]
        panel.contentView = hostView

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let w: CGFloat = 320, h: CGFloat = 56
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

private struct SuggestionToastView: View {
    @ObservedObject var presenter: SuggestionPresenter

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.85))
                .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Begriff merken")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.5)
                    Text(presenter.current?.word ?? "")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(presenter.remainingSeconds)s")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 24)

                Button {
                    presenter.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .padding(8)
    }
}
