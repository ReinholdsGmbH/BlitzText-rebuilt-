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
    private var lifecycleWatchdog: LifecycleWatchdog!
    private var modeProcessor: ModeProcessor!
    private var settingsWindow: SettingsWindowController!
    private var updateService: UpdateService!
    private var updateWindow: UpdateWindowController!
    private var recordingHUD: RecordingHUDController!
    private var suggestionToast: SuggestionToastController!
    private var meetingController: MeetingController!
    private var meetingPill: MeetingPillController!
    private var meetingLibrary: MeetingLibrary!
    private var meetingWindow: AppWindowController!
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
        // App Nap hart deaktivieren: als LSUIElement-Menubar-App muss BlitzText jederzeit
        // sofort auf den Hotkey reagieren. `beginActivity` allein hat die Drosselung der
        // Main-Queue im Hintergrund NICHT verhindert (Freeze-Analyse 2026-07-02) —
        // `NSAppSleepDisabled` ist der dokumentierte, harte Opt-out. Muss vor dem ersten
        // AppKit-Nap-Assessment gesetzt sein, daher hier im frühesten Delegate-Hook.
        UserDefaults.standard.register(defaults: ["NSAppSleepDisabled": true])
        enforceSingleInstance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Als Test-Host keine Menüleiste, keine Hotkeys, keine Berechtigungsabfragen und kein
        // Schlüsselbund: Die Tests bauen sich ihre Objekte selbst.
        guard !RuntimeEnvironment.isRunningTests else { return }
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
            Task { @MainActor [weak self] in self?.menuBarController?.showApp() }
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
        // In-App-Updater: prüft GitHub-Releases, benachrichtigt und öffnet den Notes-Screen.
        updateService = UpdateService(settings: settingsStore)
        updateWindow = UpdateWindowController(service: updateService)
        updateService.presentWindow = { [weak updateWindow] in updateWindow?.show() }

        settingsWindow = SettingsWindowController()
        recordingHUD = RecordingHUDController(recorder: modeProcessor.recorder, processor: modeProcessor, settings: settingsStore)
        suggestionToast = SuggestionToastController(presenter: modeProcessor.suggestionPresenter)
        // Meeting-Mitschnitt: Transkription und Sprechertrennung immer lokal (Parakeet,
        // FluidAudio). Die Zusammenfassung läuft über den in Einstellungen → Meetings
        // gewählten Anbieter.
        let settings = settingsStore
        let parakeet = modeProcessor.parakeetClient
        let meetingDiarizer = FluidMeetingDiarizer(
            modelManager: diarizerManager,
            store: modeProcessor.speakerStore,
            threshold: { Float(settings.speakerMatchThreshold) }
        )
        meetingController = MeetingController(
            recorder: MeetingRecorder(),
            makeTranscriber: { PlainParakeetTranscriber(client: parakeet) },
            makeSummarizer: { settings.makeMeetingSummarizer() },
            diarizer: meetingDiarizer,
            makeExporter: { settings.makeVaultExporter() },
            language: { settings.transcriptionLanguage.isEmpty ? nil : settings.transcriptionLanguage }
        )
        meetingLibrary = MeetingLibrary(
            archive: meetingController.archive,
            diarizer: meetingDiarizer,
            makeSummarizer: { settings.makeMeetingSummarizer() },
            makeExporter: { settings.makeVaultExporter() }
        )
        meetingWindow = AppWindowController(
            library: meetingLibrary,
            controller: meetingController,
            chat: MeetingChat(makeSummarizer: { settings.makeMeetingSummarizer() }),
            environment: .init(
                settings: settingsStore,
                modelManager: modelManager,
                diarizerManager: diarizerManager,
                speakerViewModel: speakerProfileViewModel,
                enrollmentViewModel: enrollmentViewModel,
                updateService: updateService,
                history: historyStore
            )
        )
        // Einstellungen leben jetzt im App-Fenster; alle alten Einstiege führen dorthin.
        settingsWindow.openInApp = { [weak self] section in self?.meetingWindow.show(section: section) }
        meetingController.onOpenLibrary = { [weak self] folder in self?.meetingWindow.show(selecting: folder) }
        meetingController.onMeetingSaved = { [weak self] _ in self?.meetingLibrary.reload() }
        meetingPill = MeetingPillController(controller: meetingController)
        meetingController.startMonitoring()

        // Startparameter für Tests mit vorhandenen Aufnahmen (z. B. aus MacWhisper):
        //   --meetings                  öffnet die Meeting-Bibliothek
        //   --import-meeting <a> [<b>]  importiert eine Mischspur oder ein Spurpaar
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--import-meeting") {
            let files = arguments[(index + 1)...].prefix { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
            meetingController.importFiles(Array(files))
        }
        if arguments.contains("--meetings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.meetingWindow.show(section: .meetings) }
        }

        menuBarController = MenuBarController(
            settings: settingsStore,
            processor: modeProcessor,
            settingsWindow: settingsWindow,
            updateService: updateService,
            meeting: meetingController
        )
        menuBarController.openApp = { [weak self] in self?.meetingWindow.show() }
        menuBarController.toggleMeeting = { [weak self] in self?.meetingController.toggle() }
        menuBarController.openMeetings = { [weak self] in self?.meetingWindow.show(section: .meetings) }

        let processor = modeProcessor!
        hotkeyManager = HotkeyManager(settings: settingsStore) { mode, action in
            Task { @MainActor in
                // Diagnose: Bestätigt, dass der Hotkey-Trigger den MainActor TATSÄCHLICH erreicht.
                // Bei Main-Queue-Starvation (App-Nap-Symptom) feuert `flagsChanged` im Log, aber
                // diese Zeile bleibt aus → eindeutiger Beleg, dass die Zustellung hängt.
                Log.write("Hotkey-Trigger: mode=\(mode) action=\(action) state=\(processor.state)")
                switch action {
                case .start:  await processor.start(mode: mode)
                case .stop:   await processor.stop()
                case .toggle: await processor.toggle(mode: mode)
                }
            }
        }

        hotkeyManager.start()

        // Lifecycle-Watchdog: App-Nap-Schutz + Sleep/Wake-Logging + doppelter Heartbeat.
        // Adressiert das „App reagiert nach Ruhezustand nicht mehr"-Symptom (Main-Queue-Starvation).
        lifecycleWatchdog = LifecycleWatchdog(hotkeys: hotkeyManager, stateLabel: modeProcessor.stateLabel)
        lifecycleWatchdog.start()

        // Update-Prüfung starten (verzögerte erste Prüfung + 2h-Takt; Opt-out beachtet).
        updateService.start()

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
        // `needsOpenAIKey()` BEWUSST verzögert auswerten: Der API-Key wird beim Start
        // asynchron aus der Keychain in den Cache geladen (nicht-blockierend). Würde man
        // hier sofort prüfen, wäre der Cache noch leer → Settings poppte fälschlich auf.
        // Gewartet wird, bis der Schlüssel wirklich geladen ist: Nach einem neuen Build hängt
        // der Schlüsselbund an der Passwortabfrage, und ein noch leerer Cache öffnete sonst
        // jedes Mal die Einstellungen statt der Meetings.
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.settingsWindow.show(section: .dictation)
            }
        } else {
            checkOpenAIKeyWhenLoaded(attempt: 0)
        }
    }

    /// Prüft alle halbe Sekunde, höchstens zwei Minuten lang.
    private func checkOpenAIKeyWhenLoaded(attempt: Int) {
        guard attempt < 240 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            guard self.settingsStore.isAPIKeyLoaded else {
                self.checkOpenAIKeyWhenLoaded(attempt: attempt + 1)
                return
            }
            if self.needsOpenAIKey() { self.settingsWindow.show(section: .models) }
        }
    }

    /// True, wenn der OpenAI-Key bei aktueller Config gebraucht wird, aber fehlt.
    private func needsOpenAIKey() -> Bool {
        guard settingsStore.apiKey.isEmpty else { return false }
        if settingsStore.backend == .openAI { return true }
        if settingsStore.aiSuggestProperNouns { return true }
        return false
    }

    /// Rechtsklick aufs Dock-Symbol: Aufnahme starten/beenden und Meetings öffnen, wie bei Wispr.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let recording = meetingController?.isRecording == true
        let record = NSMenuItem(title: recording ? "Aufnahme beenden" : "Meeting aufnehmen",
                                action: #selector(toggleMeetingFromMenu), keyEquivalent: "")
        record.target = self
        record.isEnabled = meetingController?.isProcessing != true
        menu.addItem(record)
        let open = NSMenuItem(title: "Meetings öffnen", action: #selector(openMeetingsFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        return menu
    }

    // `nonisolated` @objc + Main-Queue: AppKit ruft Menü-Actions ohne Swift-Task-Kontext auf;
    // eine @MainActor-@objc-Methode crasht dort im Executor-Check (siehe MenuBarController).
    @objc nonisolated func toggleMeetingFromMenu() {
        DispatchQueue.main.async { [weak self] in self?.meetingController?.toggle() }
    }

    @objc nonisolated func openMeetingsFromMenu() {
        DispatchQueue.main.async { [weak self] in self?.meetingWindow?.show(section: .meetings) }
    }

    /// Klick aufs Dock-Symbol (oder erneutes Öffnen im Finder) holt das App-Fenster.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        meetingWindow?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let token = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
            didBecomeActiveObserver = nil
        }
        settingsStore.save()
        lifecycleWatchdog?.stop()
        hotkeyManager?.stop()
        updateService?.stop()
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
