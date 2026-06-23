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
            button.action = #selector(statusItemClicked)
            button.target = self
            // Links- UND Rechtsklick an dieselbe Action liefern (Rechtsklick → Kontextmenü).
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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

    // `nonisolated` @objc: AppKit ruft die Action via `sendAction:to:from:` OHNE Swift-Task-
    // Kontext auf. Eine `@MainActor`-`@objc`-Methode bekäme im Prolog den dynamischen
    // `swift_task_isCurrentExecutor`-Check, der hier (strict-concurrency: minimal, Swift 6.3)
    // als EXC_BAD_ACCESS crasht. Das Klick-Event wird SYNCHRON ausgewertet (`currentEvent`
    // gilt nur während des Klicks), dann synchron in den (ohnehin Main-)Kontext gereicht —
    // kein async-Defer, der mit `.transient`-Popovers flackert.
    @objc nonisolated private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? false
        Log.write("StatusItem-Klick: type=\(event?.type.rawValue.description ?? "nil") right=\(isRightClick)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { Log.write("StatusItem-Klick: self deallokiert"); return }
            self.handleStatusClick(rightClick: isRightClick)
        }
    }

    @MainActor private func handleStatusClick(rightClick: Bool) {
        if rightClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    /// Rechtsklick-Kontextmenü: Einstellungen öffnen oder App beenden.
    private func showContextMenu() {
        guard let button = statusItem.button else { Log.write("Kontextmenü: kein Button"); return }
        if popover.isShown { popover.performClose(nil) }

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Einstellungen…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "BlitzText beenden", action: #selector(quitFromMenu), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        Log.write("Kontextmenü angezeigt")
    }

    // Menü-Actions ebenfalls `nonisolated` @objc (AppKit-Dispatch ohne Task-Kontext) — die
    // @MainActor-Arbeit läuft über DispatchQueue.main (vermeidet Prolog-Executor-Check + Crash).
    @objc nonisolated private func openSettingsFromMenu() {
        DispatchQueue.main.async { [weak self] in self?.settingsWindow.show() }
    }
    @objc nonisolated private func quitFromMenu() {
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { Log.write("Popover: kein Button"); return }
        Log.write("Popover toggle: isShown=\(popover.isShown) inWindow=\(button.window != nil)")
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Accessory-App (LSUIElement): ein `.transient`-Popover zeigt sich nur, wenn die
            // App aktiv ist — sonst verschwindet es sofort wieder. `activate()` (modern, macOS 14+)
            // statt des deprecated `activate(ignoringOtherApps:)`, das auf neuem macOS oft no-op ist.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            Log.write("Popover.show → isShown=\(popover.isShown)")
        }
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate()
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
