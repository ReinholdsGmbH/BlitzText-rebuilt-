import Foundation
import AppKit
import UserNotifications

/// Zustand der letzten Prüfung — für Feedback im Einstellungen-Tab.
enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case failed(String)
}

/// Koordiniert die Update-Erkennung: Prüfung bei Start + im 2-Stunden-Takt, Notification bei
/// neuer Version, Fenster mit aggregierten Release-Notes, und der (nutzerinitiierte) Download-/
/// Install-Anstoß.
///
/// Concurrency: `@MainActor`-`ObservableObject` — die Single Source of Truth für die UI.
/// Netzwerk (Client) und Installation (Installer) laufen STRIKT off-main; die Ergebnisse
/// werden über `await` bzw. `DispatchQueue.main` zurück auf den MainActor gereicht. Kein
/// `MainActor.assumeIsolated` (crasht hier). Der Prüf-Timer läuft wie der `LifecycleWatchdog`
/// als RunLoop-Timer.
@MainActor
final class UpdateService: NSObject, ObservableObject {

    /// Verfügbares Update (neuestes Release + aggregierte Notes). `nil` = alles aktuell.
    @Published private(set) var availableUpdate: UpdatePlan?
    /// Alle verwendbaren Releases (neueste zuerst) aus der letzten Prüfung — auch wenn kein
    /// Update ansteht. Speist den „Release-Notes"-Browse-Modus des Fensters.
    @Published private(set) var allReleases: [ReleaseInfo] = []
    /// Ergebnis der letzten (auch manuellen) Prüfung.
    @Published private(set) var checkState: UpdateCheckState = .idle
    /// Läuft eine Installation, ist hier ihre Phase — sonst `nil`.
    @Published private(set) var installPhase: InstallPhase?

    /// Wird von AppDelegate gesetzt: öffnet das Update-Fenster.
    var presentWindow: (@MainActor () -> Void)?

    let currentVersion: SemanticVersion

    private let settings: SettingsStore
    private let client: GitHubReleaseClient
    private let installer: UpdateInstaller

    /// Prüfintervall: 1 h. Das unauth. GitHub-Limit (60/h je Rechner) ist damit unkritisch.
    static let checkInterval: TimeInterval = 60 * 60
    /// Verzögerung der ersten Prüfung nach Start — nicht mit Modell-Preload konkurrieren.
    private static let initialDelay: TimeInterval = 12

    private var checkTimer: Timer?
    /// Für welche Version zuletzt eine Notification/das Auto-Fenster kam — verhindert Nerv-Spam.
    private var announcedVersion: SemanticVersion?

    init(settings: SettingsStore,
         client: GitHubReleaseClient = GitHubReleaseClient(),
         installer: UpdateInstaller = UpdateInstaller()) {
        self.settings = settings
        self.client = client
        self.installer = installer
        self.currentVersion = Self.resolveCurrentVersion()
        super.init()
    }

    /// Laufende Version aus der Info.plist. In DEBUG per UserDefaults überschreibbar, um den
    /// Update-Flow ohne echtes zweites Release zu testen:
    ///   `defaults write de.reinholds.blitztext BlitztextFakeVersion 0.0.1`
    /// Dann erkennt die App das echte GitHub-Release als „Update" und spielt Download/Install durch.
    private static func resolveCurrentVersion() -> SemanticVersion {
        #if DEBUG
        if let fake = UserDefaults.standard.string(forKey: "BlitztextFakeVersion"),
           let version = SemanticVersion(fake) {
            Log.write("Update: DEBUG-Fake-Version aktiv → \(version)")
            return version
        }
        #endif
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return SemanticVersion(raw) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    // MARK: - Lifecycle

    func start() {
        // Im XCTest-Host keine Netzwerkprüfung starten.
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil { return }

        UNUserNotificationCenter.current().delegate = self
        requestNotificationAuthorization()

        // Erste Prüfung verzögert — nicht mit dem Modell-Preload beim Start konkurrieren.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.initialDelay * 1_000_000_000))
            self?.triggerAutomaticCheck()
        }

        // RunLoop-Timer (wie Watchdog): feuert auf dem Main-Thread. Der Block hüpft explizit
        // auf den MainActor (Projektmuster: kein Direktaufruf von @MainActor-Code aus einem
        // nonisolierten Closure).
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.triggerAutomaticCheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
        Log.write("UpdateService gestartet — laufende Version \(currentVersion), Takt \(Int(Self.checkInterval))s.")
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func triggerAutomaticCheck() {
        guard settings.autoUpdateCheckEnabled else { return }
        Task { await checkForUpdates(userInitiated: false) }
    }

    // MARK: - Prüfung

    /// Führt eine Prüfung durch. `userInitiated` = aus den Einstellungen („Jetzt suchen"):
    /// dann wird bei Erfolg IMMER das Fenster gezeigt (auch wenn schon angekündigt) bzw.
    /// „aktuell" gemeldet. Die automatische Prüfung kündigt jede neue Version nur EINMAL an.
    func checkForUpdates(userInitiated: Bool) async {
        checkState = .checking
        do {
            let dtos = try await client.fetchReleases()   // off-main
            allReleases = UpdatePlanner.usableReleases(from: dtos)
            let plan = UpdatePlanner.plan(current: currentVersion, from: dtos)
            availableUpdate = plan

            if let plan {
                checkState = .idle
                Log.write("Update verfügbar: \(plan.latest.tag) (laufend \(currentVersion))")
                if userInitiated {
                    presentWindow?()
                } else if announcedVersion != plan.latest.version {
                    announcedVersion = plan.latest.version
                    postNotification(for: plan)
                    presentWindow?()
                }
            } else {
                checkState = .upToDate
                Log.write("Update-Prüfung: bereits aktuell (\(currentVersion)).")
            }
        } catch let error as UpdateCheckError {
            checkState = .failed(error.errorDescription ?? "Prüfung fehlgeschlagen.")
            Log.write("Update-Prüfung fehlgeschlagen: \(error)")
        } catch {
            checkState = .failed("Prüfung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    /// Öffnet das Release-Notes-Fenster — auch ohne verfügbares Update (Menü „Release-Notes…").
    /// Zeigt die zwischengespeicherten Releases; sind noch keine geladen, wird im Hintergrund
    /// nachgeladen (das Fenster zeigt solange einen Ladeindikator).
    func showReleaseNotes() {
        presentWindow?()
        if allReleases.isEmpty, checkState != .checking {
            Task { await checkForUpdates(userInitiated: false) }
        }
    }

    // MARK: - Installation

    /// Startet Download + Installation des verfügbaren Updates. Läuft off-main; bei Erfolg
    /// beendet sich die App und der Helfer startet die neue Version.
    func beginInstall() {
        guard let plan = availableUpdate, installPhase == nil else { return }
        installPhase = .downloading(0)
        let installer = self.installer
        Task.detached { [weak self] in
            await installer.install(plan: plan) { phase in
                // Phasen-Callback feuert off-main → zurück auf den MainActor.
                Task { @MainActor in self?.installPhase = phase }
            }
        }
    }

    /// Bricht die Fehleranzeige zurück, damit der Button erneut versucht werden kann.
    func resetInstallError() {
        if case .failed = installPhase { installPhase = nil }
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                // Self-signed/Dev-Builds können hier scheitern — kein Crash, nur Log.
                Log.write("Notification-Authorization-Fehler: \(error.localizedDescription)")
            } else {
                Log.write("Notification-Authorization: \(granted ? "erteilt" : "abgelehnt")")
            }
        }
    }

    private func postNotification(for plan: UpdatePlan) {
        let content = UNMutableNotificationContent()
        content.title = "BlitzText-Update verfügbar"
        content.body = "Version \(plan.latest.version) ist da. Klicke, um die Neuerungen zu sehen."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "blitztext-update-\(plan.latest.tag)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.write("Notification-Post-Fehler: \(error.localizedDescription)") }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

// Delegate-Methoden feuern nicht garantiert auf dem Main-Thread → `nonisolated` + Hop auf
// die Main-Queue (Projektmuster: kein `assumeIsolated`).
extension UpdateService: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Auch im Vordergrund als Banner zeigen.
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Fenster-Präsentation auf den MainActor hüpfen; die Bestätigung an das System
        // synchron außerhalb des Tasks (kein Capture des completionHandlers im Task).
        Task { @MainActor [weak self] in self?.presentWindow?() }
        completionHandler()
    }
}
