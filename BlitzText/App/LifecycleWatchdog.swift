import AppKit
import Foundation

/// Diagnose- und Selbstheilungs-Schicht für den „App reagiert nicht mehr"-Fehler.
///
/// Hintergrund (siehe BlitzText.log vom 2026-06-25): Nach Sleep/Wake feuert der CGEventTap
/// weiter (`flagsChanged` wird geloggt) UND der StatusItem-Klick kommt an (`StatusItem-Klick`
/// wird geloggt) — aber die danach via `DispatchQueue.main.async` / `Task { @MainActor }`
/// zugestellte Folge-Arbeit läuft NICHT mehr (kein `Popover toggle`, keine Pipeline). Der
/// RunLoop dreht also noch (Input-Sources feuern), während die Main-GCD-Queue verhungert —
/// das typische Symptom von **App Nap** bei einer LSUIElement-Accessory-App.
///
/// Dieser Watchdog tut dreierlei:
///  1. **App-Nap-Schutz**: hält über die App-Lebenszeit ein `beginActivity`-Token, damit der
///     Prozess nie genapped wird (System-Idle-Sleep bleibt erlaubt — der Mac darf nachts schlafen).
///  2. **Doppelter Heartbeat**: ein RunLoop-Timer-Schlag UND ein Main-Queue-Schlag. Stoppt beim
///     nächsten Freeze nur der Main-Queue-Schlag, ist die Main-Queue-Starvation bewiesen; stoppen
///     beide, hängt der ganze Main-Thread. So wird der Fehler beim nächsten Auftreten eindeutig.
///  3. **Wake-Recovery**: bei `didWake` Event-Tap revalidieren und Diagnose-Snapshot loggen.
///
/// Concurrency: Wie `HotkeyManager` bewusst `@unchecked Sendable` statt `@MainActor` — alle
/// Methoden laufen ausschließlich auf dem Main-Thread (per Konstruktion: `start()` wird im
/// Bootstrap auf dem Main-Actor gerufen; alle Callbacks feuern auf `RunLoop.main`/`.main`-Queue).
/// `MainActor.assumeIsolated` wird BEWUSST vermieden — es triggert den fragilen
/// `swift_task_isCurrentExecutor`-Check (Swift 6.3, strict-concurrency: minimal) und crasht
/// dort als EXC_BAD_ACCESS (siehe AppDelegate/MenuBarController).
///
/// DSGVO: loggt ausschließlich Status/Zähler — niemals Transkripte oder Klarnamen.
/// Thread-sicherer Halter für ein kurzes Status-Label (z. B. ModeProcessor.state).
/// @unchecked Sendable, damit der Watchdog es lesen kann, ohne den @MainActor-ModeProcessor
/// über eine Isolationsgrenze zu reichen. Schreiben passiert auf dem MainActor, Lesen im
/// Heartbeat-Callback — der NSLock serialisiert beides.
final class StateLabelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = "idle"
    var current: String { lock.withLock { value } }
    func set(_ newValue: String) { lock.withLock { value = newValue } }
}

final class LifecycleWatchdog: @unchecked Sendable {

    /// Heartbeat-Intervall. 30 s ist fein genug, um den Sleep/Wake-Übergang einzugrenzen,
    /// und grob genug, dass das Log nicht zugespammt wird (Rotation greift bei 2 MB).
    private static let heartbeatInterval: TimeInterval = 30

    private unowned let hotkeys: HotkeyManager
    private let stateLabel: StateLabelBox

    private var activityToken: (any NSObjectProtocol)?
    private var runLoopHeartbeat: Timer?
    private var mainQueueHeartbeatActive = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastWakeAt: Date?
    private var runLoopTick = 0
    private var mainQueueTick = 0

    // MARK: - Freeze-Erkennung / Auto-Recovery
    /// Zeitpunkt des letzten Main-Queue-Herzschlags. Wird im (auch bei Freeze weiterlaufenden)
    /// RunLoop-Herzschlag gegen jetzt geprüft: liegt er zu weit zurück, ist die Main-Queue tot
    /// (App eingefroren, RunLoop lebt) → automatischer Neustart.
    private var lastMainQueueBeatAt = Date()
    /// Nur EIN Auto-Neustart pro Prozess — verhindert Neustart-Schleifen.
    private var didTriggerRecovery = false
    /// So lange darf ein Main-Queue-Schlag ausbleiben, bevor Freeze angenommen wird. Deutlich
    /// über dem normalen Hintergrund-Coalescing (~1,5 s auf 30 s Intervall) → keine Fehlalarme.
    private static let freezeThreshold: TimeInterval = 90

    init(hotkeys: HotkeyManager, stateLabel: StateLabelBox) {
        self.hotkeys = hotkeys
        self.stateLabel = stateLabel
    }

    func start() {
        assert(Thread.isMainThread, "LifecycleWatchdog.start() muss auf dem Main-Thread laufen")
        beginAntiAppNapActivity()
        observeSleepWake()
        startRunLoopHeartbeat()
        startMainQueueHeartbeat()
        Log.write("Watchdog gestartet — heartbeat=\(Int(Self.heartbeatInterval))s, App-Nap-Schutz aktiv.")
    }

    func stop() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
        runLoopHeartbeat?.invalidate()
        runLoopHeartbeat = nil
        mainQueueHeartbeatActive = false
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - App Nap

    private func beginAntiAppNapActivity() {
        // `.userInitiatedAllowingIdleSystemSleep`: verhindert App Nap + Auto-Termination,
        // ERLAUBT aber weiterhin den System-Idle-Sleep (wir wollen den Mac nicht wachhalten,
        // nur unseren Prozess nie eingefroren bekommen).
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "BlitzText muss jederzeit sofort auf den Diktat-Hotkey reagieren"
        )
    }

    // MARK: - Sleep / Wake

    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification,        "System legt sich schlafen (willSleep)"),
            (NSWorkspace.didWakeNotification,          "System aufgewacht (didWake)"),
            (NSWorkspace.screensDidSleepNotification,  "Bildschirme aus (screensDidSleep)"),
            (NSWorkspace.screensDidWakeNotification,   "Bildschirme an (screensDidWake)"),
            (NSWorkspace.willPowerOffNotification,     "Abmeldung/Shutdown (willPowerOff)"),
        ]
        for (name, label) in pairs {
            // queue: .main → Block feuert auf dem Main-Thread; direkte Aufrufe ohne Actor-Hop.
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Log.write("Lifecycle: \(label)")
                if name == NSWorkspace.didWakeNotification {
                    self?.handleWake()
                }
            }
            workspaceObservers.append(token)
        }
    }

    private func handleWake() {
        lastWakeAt = Date()
        hotkeys.revalidateEventTap()
        Log.write("Wake-Recovery: tapAktiv=\(hotkeys.eventTapIsActive)")
    }

    // MARK: - Heartbeats

    /// RunLoop-getriebener Schlag (Timer in .common-Modi). Lebt, solange der RunLoop dreht —
    /// auch dann, wenn die Main-GCD-Queue bereits verhungert ist.
    private func startRunLoopHeartbeat() {
        let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.runLoopTick += 1
            let wakeAge = self.lastWakeAt.map { Int(Date().timeIntervalSince($0)) }
            Log.write("❤️ runloop #\(self.runLoopTick) tapAktiv=\(self.hotkeys.eventTapIsActive) state=\(self.stateLabel.current) wakeAge=\(wakeAge.map { "\($0)s" } ?? "–")")
            // Freeze-Erkennung: Wir laufen hier (RunLoop lebt), aber der Main-Queue-Schlag bleibt
            // aus → Main-Queue tot → Auto-Neustart.
            if Date().timeIntervalSince(self.lastMainQueueBeatAt) > Self.freezeThreshold {
                self.triggerRecovery()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        runLoopHeartbeat = timer
    }

    /// Main-GCD-Queue-Schlag (selbst-nachplanend). Genau der Zustellpfad, der laut Log beim
    /// Freeze versagt (Klick→`DispatchQueue.main.async`). Misst zusätzlich die Verspätung:
    /// stark verspätete oder ausbleibende Schläge = Drosselung/Starvation der Main-Queue.
    private func startMainQueueHeartbeat() {
        mainQueueHeartbeatActive = true
        scheduleMainQueueTick(scheduledFor: Date().addingTimeInterval(Self.heartbeatInterval))
    }

    private func scheduleMainQueueTick(scheduledFor target: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.heartbeatInterval) { [weak self] in
            guard let self, self.mainQueueHeartbeatActive else { return }
            self.mainQueueTick += 1
            self.lastMainQueueBeatAt = Date()
            let lateMs = Int(Date().timeIntervalSince(target) * 1000)
            Log.write("❤️ mainqueue #\(self.mainQueueTick) late=\(lateMs)ms")
            self.scheduleMainQueueTick(scheduledFor: Date().addingTimeInterval(Self.heartbeatInterval))
        }
    }

    // MARK: - Auto-Recovery

    /// Startet die App neu, wenn die Main-Queue tot ist (App eingefroren). Wird aus dem
    /// RunLoop-Herzschlag heraus aufgerufen — der läuft auch bei totem Main-Thread-Dispatch.
    /// Nur einmal pro Prozess (Schleifenschutz).
    private func triggerRecovery() {
        guard !didTriggerRecovery else { return }
        didTriggerRecovery = true
        let path = Bundle.main.bundlePath
        Log.write("Watchdog: Main-Queue seit >\(Int(Self.freezeThreshold))s tot (App eingefroren) — automatischer Neustart.")
        // Helfer wartet, bis dieser (eingefrorene) Prozess weg ist, und öffnet die App dann neu.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        // Harter Exit: die Main-GCD-Queue ist tot, `NSApp.terminate` liefe über sie und käme
        // nicht durch. `exit` beendet den Prozess sofort; der Helfer startet danach neu.
        exit(0)
    }
}
