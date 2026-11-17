import Foundation
@testable import BlitzText

/// SystemAudioCapturing-Fake ohne CoreAudio-HAL, ohne TCC-Prompt.
/// Deckt die drei Faelle ab, die im Betrieb zaehlen: Erfolg, Startfehler, stumme Spur.
final class FakeSystemAudioTap: SystemAudioCapturing, @unchecked Sendable {
    enum FakeError: Error { case startRefused }

    var startError: Error?
    /// Steuert, ob `stop()` eine stumme Spur meldet (fehlende Berechtigung simuliert).
    var reportsSilence = false
    var fixtureURL: URL

    private(set) var startCalled = 0
    private(set) var stopCalled = 0
    private(set) var lastProcesses: [pid_t] = []
    private(set) var isRunning = false

    init(fixtureURL: URL) { self.fixtureURL = fixtureURL }

    func start(writingTo url: URL, processes: [pid_t]) throws {
        startCalled += 1
        lastProcesses = processes
        if let startError { throw startError }
        isRunning = true
    }

    @discardableResult
    func stop() -> SystemAudioOutcome? {
        stopCalled += 1
        guard isRunning else { return nil }
        isRunning = false
        return SystemAudioOutcome(
            url: fixtureURL,
            duration: 12,
            peak: reportsSilence ? 0 : 0.4,
            wasSilent: reportsSilence
        )
    }
}
