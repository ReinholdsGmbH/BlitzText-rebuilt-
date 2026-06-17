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
    private(set) var enrollmentViewModel: EnrollmentViewModel!
    private var menuBarController: MenuBarController!
    private var hotkeyManager: HotkeyManager!
    private var modeProcessor: ModeProcessor!
    private var settingsWindow: SettingsWindowController!
    private var historyWindow: HistoryWindowController!
    private var recordingHUD: RecordingHUDController!
    private var suggestionToast: SuggestionToastController!
    private var didBecomeActiveObserver: NSObjectProtocol?

    // Ping-Pong: Duplikat-Instanzen senden einen Ping und warten auf den Pong der bereits
    // laufenden Instanz. DistributedNotificationCenter ist dafür der macOS-idiomatische Weg —
    // kein Dateisystem-Locking, kein Timing-Race beim gleichzeitigen Start.
    private static let pingName = Notification.Name("de.blitztext.instance.ping")
    private static let pongName = Notification.Name("de.blitztext.instance.pong")

    // Bewusst NICHT `nonisolated` + `MainActor.assumeIsolated`: AppKit ruft diese
    // NSApplicationDelegate-Methoden auf dem Main-Actor auf. `assumeIsolated` würde den
    // fragilen `swift_task_isCurrentExecutor`-Check triggern (Swift 6.3), der hier als
    // EXC_BAD_ACCESS crasht. Als `@MainActor`-Methoden der `@MainActor`-Klasse entfällt der Check.
    func applicationWillFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrap()
    }

    /// Single-Instance via DistributedNotificationCenter Ping-Pong.
    /// Sendet einen Ping; antwortet eine laufende Instanz mit einem Pong, zeigen wir
    /// den Duplikat-Dialog. Kein Dateisystem-Lock nötig, kein Timing-Race.
    private func enforceSingleInstance() {
        // Im XCTest-Hosted-Run läuft die echte App als Bundle-Loader im Test-Runner —
        // ein Single-Instance-Check würde den Test-Host beim parallelen Testen beenden.
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCInjectBundleInto"] != nil { return }

        var pongReceived = false
        let pongObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.pongName,
            object: nil,
            queue: .main
        ) { _ in pongReceived = true }

        DistributedNotificationCenter.default().postNotificationName(
            Self.pingName, object: nil, userInfo: nil, deliverImmediately: true
        )

        // 200 ms auf Pong warten — ausreichend für jede laufende Instanz auf demselben Rechner.
        let deadline = Date().addingTimeInterval(0.2)
        while !pongReceived && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        DistributedNotificationCenter.default().removeObserver(pongObserver)

        guard pongReceived else { return }

        // Eine andere Instanz läuft — alle anderen beenden und selbst übernehmen.
        // Kein Dialog: Re-Launch aus Xcode oder Terminal soll einfach funktionieren.
        Log.write("Doppelte Instanz erkannt (PID \(ProcessInfo.processInfo.processIdentifier)) — ersetze vorhandene Instanz(en).")
        if let bundleID = Bundle.main.bundleIdentifier {
            let me = ProcessInfo.processInfo.processIdentifier
            NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != me }
                .forEach { $0.forceTerminate() }
        }
        // KEIN Thread.sleep + Rekursion mehr: das blockierte den Main-Thread während des
        // Launches (Watchdog-Risiko). forceTerminate ist asynchron, aber für unseren Zweck
        // (eine bereits laufende Instanz ablösen) genügt ein einmaliger Versuch.
    }

    private func bootstrap() {
        NSApp.setActivationPolicy(.accessory)

        // Auf Ping einer Duplikat-Instanz antworten und Popover zeigen.
        DistributedNotificationCenter.default().addObserver(
            forName: Self.pingName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DistributedNotificationCenter.default().postNotificationName(
                Self.pongName, object: nil, userInfo: nil, deliverImmediately: true
            )
            Task { @MainActor [weak self] in self?.menuBarController?.showPopover() }
        }

        // Hinweis: Der frühere `de.blitztext.showPopover`-Observer wurde entfernt — er hatte
        // KEINEN internen Sender (reine externe Trigger-Fläche: jede lokale App hätte das
        // Popover aufzwingen können). DistributedNotificationCenter authentifiziert Sender nicht.

        // DI-Wiring: Manager-Reference in Store, damit Toggle-On den Manager triggert (D-01).
        settingsStore.diarizerManager = diarizerManager

        modeProcessor = ModeProcessor(
            settings: settingsStore,
            history: historyStore,
            modelManager: modelManager,
            diarizerManager: diarizerManager
        )
        speakerProfileViewModel = SpeakerProfileViewModel(store: modeProcessor.speakerStore)
        enrollmentViewModel = EnrollmentViewModel(
            audioRecorder: modeProcessor.recorder,
            parakeetClient: modeProcessor.parakeetClient,
            speakerVM: speakerProfileViewModel
        )
        settingsWindow = SettingsWindowController(
            settings: settingsStore,
            modelManager: modelManager,
            diarizerManager: diarizerManager,
            speakerViewModel: speakerProfileViewModel,
            enrollmentViewModel: enrollmentViewModel
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
    private func needsOpenAIKey() -> Bool {
        guard settingsStore.apiKey.isEmpty else { return false }
        if settingsStore.backend == .openAI { return true }
        if settingsStore.aiSuggestProperNouns { return true }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let token = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
            didBecomeActiveObserver = nil
        }
        settingsStore.save()
        hotkeyManager?.stop()
        cleanupTempFiles()
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
