import Testing
@testable import BlitzText

@MainActor
struct StatusPollerTests {

    @Test("Pollt im gesetzten Takt und stoppt nach Ablauf des Zeitfensters von allein")
    func ticksThenStops() async throws {
        let poller = StatusPoller(interval: 0.01, duration: 0.03)   // 3 Ticks
        poller.start()

        try await Task.sleep(for: .milliseconds(150))
        #expect(poller.tick == 3)

        // Nach Ablauf darf nichts mehr nachlaufen.
        try await Task.sleep(for: .milliseconds(60))
        #expect(poller.tick == 3)
    }

    @Test("stop() beendet das Nachfragen sofort")
    func stopHalts() async throws {
        let poller = StatusPoller(interval: 0.02, duration: 10)
        poller.start()
        poller.stop()

        try await Task.sleep(for: .milliseconds(120))
        #expect(poller.tick == 0)
    }

    @Test("Erneutes start() verlängert das Fenster statt einen zweiten Takt zu starten")
    func restartExtendsWindow() async throws {
        let poller = StatusPoller(interval: 0.02, duration: 0.04)   // 2 Ticks
        poller.start()
        poller.start()
        poller.start()

        try await Task.sleep(for: .milliseconds(200))
        // Bei parallelen Takten wären es mehr als die 2 Ticks eines Fensters.
        #expect(poller.tick == 2)
    }

    @Test("refreshOnce() aktualisiert einmalig, ohne ein Poll-Fenster zu öffnen")
    func refreshOnceIsSingleShot() async throws {
        let poller = StatusPoller(interval: 0.01, duration: 10)
        poller.refreshOnce()

        try await Task.sleep(for: .milliseconds(80))
        #expect(poller.tick == 1)
    }
}
