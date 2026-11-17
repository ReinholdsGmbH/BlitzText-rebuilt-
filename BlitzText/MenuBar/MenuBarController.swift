import AppKit
import SwiftUI
import Combine

/// Menüleisten-Symbol: Linksklick öffnet das App-Fenster, Rechtsklick das Kontextmenü,
/// die Farbe zeigt den Zustand (Diktat, Meeting-Aufnahme).
@MainActor
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem
    private let processor: ModeProcessor
    private let settings: SettingsStore
    private let settingsWindow: SettingsWindowController
    private let updateService: UpdateService
    private let meeting: MeetingController
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore, processor: ModeProcessor, settingsWindow: SettingsWindowController, updateService: UpdateService, meeting: MeetingController) {
        self.meeting = meeting
        self.settings = settings
        self.processor = processor
        self.settingsWindow = settingsWindow
        self.updateService = updateService
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()

        // State-Indikator im Menubar-Icon.
        // Bewusst `DispatchQueue.main` statt `RunLoop.main`: Der MainActor-Executor IST die
        // Main-DispatchQueue. `RunLoop.main`-Delivery ist genau der Übergang, an dem der
        // Swift-6-`isCurrentExecutor`-Check in eine komplexe Executor-Vergleichslogik fällt
        // und (bei `strict-concurrency: minimal`) als EXC_BAD_ACCESS durchschlagen kann.
        processor.$state
            .combineLatest(meeting.$phase)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, phase in
                self?.updateIcon(for: state, meetingRecording: { if case .recording = phase { return true }; return false }())
            }
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

    // `nonisolated` @objc: AppKit ruft die Action via `sendAction:to:from:` OHNE Swift-Task-
    // Kontext auf. Eine `@MainActor`-`@objc`-Methode bekäme im Prolog den dynamischen
    // `swift_task_isCurrentExecutor`-Check, der hier (strict-concurrency: minimal, Swift 6.3)
    // als EXC_BAD_ACCESS crasht. Das Klick-Event wird SYNCHRON ausgewertet (`currentEvent`
    // gilt nur während des Klicks), dann synchron in den (ohnehin Main-)Kontext gereicht —
    // kein async-Defer, der Klicks verzögert.
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

    /// Linksklick öffnet das App-Fenster (Meetings, Verlauf, Einstellungen), Rechtsklick das
    /// Kontextmenü. Das frühere Popover mit Modi-Liste ist im App-Fenster aufgegangen.
    var openApp: (() -> Void)?

    @MainActor private func handleStatusClick(rightClick: Bool) {
        if rightClick {
            showContextMenu()
        } else {
            openApp?()
        }
    }

    /// Rechtsklick-Kontextmenü: Einstellungen öffnen oder App beenden.
    private func showContextMenu() {
        guard let button = statusItem.button else { Log.write("Kontextmenü: kein Button"); return }

        let menu = NSMenu()

        // Versions-/Release-Info: nicht klickbare Kopfzeile (zeigt die laufende Version) +
        // Link zu den Release-Notes auf GitHub.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let versionItem = NSMenuItem(title: "BlitzText \(version) (Build \(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        let updateItem = NSMenuItem(title: "Nach Updates suchen…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        let releaseItem = NSMenuItem(title: "Release-Notes…", action: #selector(showReleaseNotesFromMenu), keyEquivalent: "")
        releaseItem.target = self
        menu.addItem(releaseItem)
        menu.addItem(.separator())

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

    /// Öffnet das In-App-Release-Notes-Fenster — auch wenn kein Update ansteht. Der Link zur
    /// GitHub-Releases-Seite (zentral aus `GitHubRepo`) sitzt als Button im Fenster.
    @objc nonisolated private func showReleaseNotesFromMenu() {
        Task { @MainActor [weak self] in
            self?.updateService.showReleaseNotes()
        }
    }

    /// Manuelle Update-Prüfung aus dem Menü — zeigt bei Erfolg das Release-Notes-Fenster.
    @objc nonisolated private func checkForUpdatesFromMenu() {
        Task { @MainActor [weak self] in
            await self?.updateService.checkForUpdates(userInitiated: true)
        }
    }

    /// Für die laufende Instanz, wenn eine zweite gestartet wird.
    func showApp() {
        openApp?()
    }

    private func updateIcon(for state: ModeProcessor.State, meetingRecording: Bool) {
        guard let button = statusItem.button else { return }
        let color: NSColor? = {
            // Diktat hat Vorrang in der Anzeige; ein laufender Meeting-Mitschnitt färbt
            // das Icon sonst dauerhaft rot, damit er nicht vergessen wird.
            if case .idle = state, meetingRecording { return .systemRed }
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
