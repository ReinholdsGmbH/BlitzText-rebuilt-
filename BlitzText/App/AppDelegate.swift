import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    let historyStore = HistoryStore()
    let modelManager = LocalModelManager()
    private var menuBarController: MenuBarController!
    private var hotkeyManager: HotkeyManager!
    private var modeProcessor: ModeProcessor!
    private var settingsWindow: SettingsWindowController!
    private var historyWindow: HistoryWindowController!
    private var recordingHUD: RecordingHUDController!
    private var suggestionToast: SuggestionToastController!

    nonisolated func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { self.enforceSingleInstance() }
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { self.bootstrap() }
    }

    /// Prüft, ob bereits eine BlitzText-Instanz läuft. Wenn ja: Hinweis-Dialog,
    /// alte Instanz in den Vordergrund holen, und sich selbst beenden.
    private func enforceSingleInstance() {
        // Im XCTest-Hosted-Run laeuft die echte App im Test-Runner als Bundle-Loader —
        // ein Single-Instance-Check wuerde den Test-Host beenden, sobald der User
        // BlitzText im Hintergrund laufen hat. Skip, wenn XCTest die App hostet.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me.processIdentifier }
        guard let other = others.first else { return }

        let alert = NSAlert()
        alert.messageText = "BlitzText läuft bereits"
        alert.informativeText = "Eine andere Instanz von BlitzText ist schon offen (PID \(other.processIdentifier)). Diese Instanz wird beendet."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Verstanden")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        other.activate(options: [.activateIgnoringOtherApps])
        Log.write("Doppelte Instanz erkannt — beende mich (PID \(me.processIdentifier)), aktive PID = \(other.processIdentifier)")
        exit(0)
    }

    private func bootstrap() {
        NSApp.setActivationPolicy(.accessory)

        modeProcessor = ModeProcessor(settings: settingsStore, history: historyStore, modelManager: modelManager)
        settingsWindow = SettingsWindowController(settings: settingsStore, modelManager: modelManager)
        historyWindow = HistoryWindowController(history: historyStore)
        recordingHUD = RecordingHUDController(recorder: modeProcessor.recorder, processor: modeProcessor, settings: settingsStore)
        suggestionToast = SuggestionToastController(presenter: modeProcessor.suggestionPresenter)
        menuBarController = MenuBarController(
            settings: settingsStore,
            processor: modeProcessor,
            settingsWindow: settingsWindow,
            historyWindow: historyWindow
        )

        let processor = modeProcessor!
        hotkeyManager = HotkeyManager(settings: settingsStore) { mode, action in
            Task { @MainActor in
                switch action {
                case .start:  await processor.start(mode: mode)
                case .stop:   await processor.stop()
                case .toggle: await processor.toggle(mode: mode)
                }
            }
        }
        hotkeyManager.start()
        cleanupTempFiles()

        // Lokales Modell beim App-Start vorladen — sonst würde die erste Aufnahme
        // 1–3 min CoreML-Compile-Zeit kosten. Läuft im Hintergrund, blockiert nicht.
        modeProcessor.preloadLocalModelIfActive()

        // Sobald der User in Settings ein Modell aktiviert, sofort preloaden.
        modelManager.onActivate = { [weak self] in
            self?.modeProcessor.preloadLocalModelIfActive()
        }

        // Proaktiv Mikrofon-Permission anfragen — sonst zeigt macOS BlitzText nicht in der Liste
        // unter Datenschutz → Mikrofon, weil noch kein Prompt erfolgt ist.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                NSLog("[BlitzText] Mikrofon-Permission: \(granted ? "erteilt" : "abgelehnt")")
            }
        }

        // Settings öffnen, wenn noch kein API-Key hinterlegt ist
        // ODER wenn die App mit `--settings` gestartet wurde.
        // Workaround für volle Menubar — du brauchst das Icon nicht zu finden.
        let forceSettings = CommandLine.arguments.contains("--settings")
        if settingsStore.apiKey.isEmpty || forceSettings {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.settingsWindow.show()
            }
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.hotkeyManager?.stop()
            self.cleanupTempFiles()
        }
    }

    private func cleanupTempFiles() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        if let entries = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in entries where url.lastPathComponent.hasPrefix("blitztext-") {
                try? fm.removeItem(at: url)
            }
        }
    }
}
