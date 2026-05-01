import Foundation
@testable import BlitzText
@testable import FluidAudio

/// Test-Fake für `DiarizerLoaderProtocol`. Konfigurierbarer Progress-Tick-Stream
/// und optionaler injizierter Fehler. Wirft am Ende immer (auch bei "Erfolg"),
/// weil `DiarizerModels` keinen public init hat — Tests prüfen state-Transitionen,
/// nicht den `cachedModels`-Wert.
final class FakeDiarizerLoader: DiarizerLoaderProtocol, @unchecked Sendable {
    var installed: Bool = false
    var failure: Error?
    var progressTicks: [Double] = []
    private(set) var downloadCallCount: Int = 0
    private(set) var clearCacheCallCount: Int = 0

    func isInstalled() -> Bool {
        installed
    }

    func clearCache() {
        clearCacheCallCount += 1
        installed = false
    }

    func downloadIfNeeded(
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> DiarizerModels {
        downloadCallCount += 1
        for tick in progressTicks {
            progressHandler?(tick)
            try await Task.sleep(nanoseconds: 5_000_000)  // 5 ms zwischen Ticks
        }
        if let failure {
            throw failure
        }
        // DiarizerModels-Init ist internal (siehe 03-RESEARCH.md § FluidAudio Internals).
        // Tests prüfen state-Transitionen, nicht den cachedModels-Wert.
        // Bei "Erfolg" werfen wir einen Marker-Fehler, den der Manager als
        // Unbekannt klassifiziert. Test-Assertions arbeiten dagegen.
        throw NSError(
            domain: "FakeDiarizerLoader",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Test-Stub: kein echtes Modell"]
        )
    }
}
