import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    let historyStore = HistoryStore()
    let modelManager = LocalModelManager()
    let diarizerManager = DiarizerModelManager()
    private(set) var speakerProfileViewModel: SpeakerProfileViewModel!
    private var menuBarController: MenuBarController!
    private var hotkeyManager: HotkeyManager!
    private var modeProcessor: ModeProcessor!
    private var settingsWindow: SettingsWindowController!
    private var historyWindow: HistoryWindowController!
    private var recordingHUD: RecordingHUDController!
    private var suggestionToast: SuggestionToastController!
    /// Token des `didBecomeActiveNotification`-Observers. Muss in
    private var didBecomeActiveObserver: NSObjectProtocol?

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

        // DI-Wiring: Manager-Reference in Store, damit Toggle-On den Manager triggert (D-01).
        settingsStore.diarizerManager = diarizerManager

        modeProcessor = ModeProcessor(
            settings: settingsStore,
            history: historyStore,
            modelManager: modelManager,
            diarizerManager: diarizerManager
        )
        speakerProfileViewModel = SpeakerProfileViewModel(store: modeProcessor.speakerStore)
        settingsWindow = SettingsWindowController(
            settings: settingsStore,
            modelManager: modelManager,
            diarizerManager: diarizerManager,
            speakerViewModel: speakerProfileViewModel
        )
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

        // D-13/D-14: Wenn Diarization aktiv persistiert war, Modell im Hintergrund prewarmen.
        // Best-effort — Fehler landen in `diarizerManager.lastError`, App-Start blockiert nie.
        if settingsStore.parakeetDiarization {
            Task { [diarizerManager] in
                await MainActor.run { diarizerManager.prewarm() }
            }
        }

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

        // Settings nur dann automatisch öffnen, wenn der User OpenAI braucht aber
        // keinen Key hinterlegt hat. Bei rein lokalem Setup (Whisper/Parakeet,
        // KI-Vorschläge aus) ist der Key irrelevant und der Auto-Open nervt.
        let forceSettings = CommandLine.arguments.contains("--settings")
        if forceSettings || needsOpenAIKey() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.settingsWindow.show()
            }
        }
    }

    /// True, wenn der OpenAI-Key bei aktueller Config gebraucht wird, aber fehlt.
    /// Gebraucht wird er, wenn das Cloud-Backend aktiv ist ODER KI-Eigennamen-Vorschläge an sind.
    /// Rewrite (Blitztext+, $%&!) braucht ihn auch — aber das fängt der Pipeline-Fehler später ab,
    /// kein Grund für Auto-Open beim Start.
    private func needsOpenAIKey() -> Bool {
        guard settingsStore.apiKey.isEmpty else { return false }
        if settingsStore.backend == .openAI { return true }
        if settingsStore.aiSuggestProperNouns { return true }
        return false
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let token = self.didBecomeActiveObserver {
                NotificationCenter.default.removeObserver(token)
                self.didBecomeActiveObserver = nil
            }
            self.settingsStore.save()
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
