import AppKit
import SwiftUI
import Combine

/// Menu-Bar-Icon mit Popover-HUD ("Bereit", Modi-Liste, Status).
@MainActor
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let processor: ModeProcessor
    private let settings: SettingsStore
    private let settingsWindow: SettingsWindowController
    private let historyWindow: HistoryWindowController
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore, processor: ModeProcessor, settingsWindow: SettingsWindowController, historyWindow: HistoryWindowController) {
        self.settings = settings
        self.processor = processor
        self.settingsWindow = settingsWindow
        self.historyWindow = historyWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()

        // State-Indikator im Menubar-Icon.
        // Bewusst `DispatchQueue.main` statt `RunLoop.main`: Der MainActor-Executor IST die
        // Main-DispatchQueue. `RunLoop.main`-Delivery ist genau der Übergang, an dem der
        // Swift-6-`isCurrentExecutor`-Check in eine komplexe Executor-Vergleichslogik fällt
        // und (bei `strict-concurrency: minimal`) als EXC_BAD_ACCESS durchschlagen kann.
        processor.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updateIcon(for: state) }
            .store(in: &cancellables)
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill",
                                   accessibilityDescription: "BlitzText")
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 280)
        let host = NSHostingController(
            rootView: HUDView(processor: processor, settings: settings, modelManager: processor.modelManager, onOpenSettings: { [weak self] in
                guard let self else { return }
                self.popover.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.settingsWindow.show()
                }
            }, onOpenHistory: { [weak self] in
                guard let self else { return }
                self.popover.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.historyWindow.show()
                }
            }, onQuit: {
                NSApp.terminate(nil)
            })
        )
        popover.contentViewController = host
    }

    // `nonisolated` + GCD-Dispatch: AppKit ruft die @objc-Action via `sendAction:to:from:`
    // OHNE Swift-Task-Kontext auf. Eine `@MainActor`-`@objc`-Methode bekäme im Prolog den
    // dynamischen `swift_task_isCurrentExecutor`-Check, der hier (strict-concurrency: minimal,
    // Swift 6.3) als EXC_BAD_ACCESS in `isMainExecutor`/`getObjectType` durchschlägt.
    // `nonisolated` vermeidet den Prolog-Check; `DispatchQueue.main` garantiert den Main-Thread.
    @objc nonisolated private func togglePopover() {
        DispatchQueue.main.async { [weak self] in self?.togglePopoverOnMain() }
    }

    @MainActor private func togglePopoverOnMain() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func updateIcon(for state: ModeProcessor.State) {
        guard let button = statusItem.button else { return }
        let color: NSColor? = {
            switch state {
            case .idle:         return nil
            case .recording:    return .systemGreen
            case .transcribing: return .systemOrange
            case .rewriting:    return .systemBlue
            case .error:        return .systemYellow
            }
        }()

        let baseImage = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "BlitzText")

        if let color {
            // SF Symbol direkt mit Palette-Farbe konfigurieren — robuster als contentTintColor
            // bei NSStatusItem-Buttons in der Menubar.
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            let tinted = baseImage?.withSymbolConfiguration(config)
            tinted?.isTemplate = false
            button.image = tinted
            button.contentTintColor = color
        } else {
            baseImage?.isTemplate = true
            button.image = baseImage
            button.contentTintColor = nil
        }
    }
}
