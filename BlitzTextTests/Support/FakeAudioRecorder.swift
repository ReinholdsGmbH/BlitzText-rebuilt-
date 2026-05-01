import Foundation
@testable import BlitzText

/// RecorderProtocol-konformer Fake ohne AVAudioEngine, ohne Mikrofon-Zugriff,
/// ohne TCC-Prompts. Liefert eine konfigurierbare `fixtureURL` zurueck.
final class FakeAudioRecorder: RecorderProtocol, @unchecked Sendable {
    enum FakeError: Error { case stopWithoutStart }

    var fixtureURL: URL
    var startError: Error? = nil
    /// Wenn gesetzt, liefert `stop()` diesen Wert (z. B. nil fuer Silence-Pfad).
    var stopOverride: URL?? = nil

    private(set) var startCalled = 0
    private(set) var stopCalled = 0

    init(fixtureURL: URL) { self.fixtureURL = fixtureURL }

    func start() throws -> URL {
        startCalled += 1
        if let e = startError { throw e }
        return fixtureURL
    }

    func stop() -> URL? {
        stopCalled += 1
        if let override = stopOverride { return override }
        return fixtureURL
    }
}
