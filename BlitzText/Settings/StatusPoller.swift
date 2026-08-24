import Foundation
import Combine

/// Fragt System-Status (Bedienungshilfen, Anmeldeobjekt) nach einer nutzerinitiierten
/// Aktion eine Weile im Sekundentakt nach.
///
/// Hintergrund: Beide werden vom Nutzer AUSSERHALB der App umgelegt (Systemeinstellungen,
/// passwortgeschützt). macOS schickt dafür keine Notification, die wir abonnieren könnten —
/// also pollen wir. Zeitlich begrenzt (`duration`), damit kein Dauer-Timer im Hintergrund
/// läuft, wenn der Nutzer den Dialog einfach liegen lässt.
@MainActor
final class StatusPoller: ObservableObject {

    /// Views lesen diesen Zähler als Invalidierungs-Trigger für `PermissionsHelper`- bzw.
    /// `LoginItemHelper`-Abfragen. Der Wert selbst hat keine Bedeutung.
    @Published private(set) var tick: Int = 0

    private let interval: TimeInterval
    private let maxTicks: Int
    private var remainingTicks: Int = 0
    private var pollTask: Task<Void, Never>?

    init(interval: TimeInterval = 1, duration: TimeInterval = 60) {
        self.interval = interval
        self.maxTicks = max(1, Int(duration / interval))
    }

    /// Startet das Nachfragen — oder verlängert nur das Zeitfenster, wenn schon gepollt wird.
    func start() {
        let wasRunning = remainingTicks > 0
        remainingTicks = maxTicks
        // Läuft schon ein Task, übernimmt der das verlängerte Fenster.
        guard !wasRunning else { return }
        pollTask?.cancel()
        // Starker self-Bezug ist unkritisch: der Task endet garantiert nach `duration`.
        // Ein `deinit`-Cleanup wäre ohnehin nicht möglich (nonisolated deinit darf den
        // MainActor-State nicht anfassen).
        pollTask = Task {
            while remainingTicks > 0 {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                tick += 1
                remainingTicks -= 1
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        remainingTicks = 0
    }

    /// Einmalige Aktualisierung ohne Poll-Fenster (Button „Status aktualisieren").
    func refreshOnce() {
        tick += 1
    }
}
