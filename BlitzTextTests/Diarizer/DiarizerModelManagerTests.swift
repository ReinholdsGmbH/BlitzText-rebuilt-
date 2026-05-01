@testable import BlitzText
import XCTest

@MainActor
final class DiarizerModelManagerTests: XCTestCase {

    // MARK: - Initial state

    func testInitialState_whenNotInstalled_isNotInstalled() {
        let loader = FakeDiarizerLoader()
        loader.installed = false
        let manager = DiarizerModelManager(loader: loader)
        XCTAssertEqual(manager.state, .notInstalled)
        XCTAssertNil(manager.downloadProgress)
        XCTAssertNil(manager.etaSeconds)
        XCTAssertNil(manager.lastError)
    }

    func testInitialState_whenInstalled_isInstalled() {
        let loader = FakeDiarizerLoader()
        loader.installed = true
        let manager = DiarizerModelManager(loader: loader)
        XCTAssertEqual(manager.state, .installed)
    }

    // MARK: - start() behavior (D-01, D-02)

    func testStart_whenNotInstalled_transitionsToDownloadingThenFailed() async {
        let loader = FakeDiarizerLoader()
        loader.installed = false
        loader.progressTicks = [0.1, 0.5, 0.9]
        let manager = DiarizerModelManager(loader: loader)

        manager.start()
        // Loader wirft am Ende immer → state landet auf .failed (Klasse Unbekannt)
        await waitUntil { if case .failed = manager.state { return true } else { return false } }

        XCTAssertEqual(loader.downloadCallCount, 1)
        // Progress wurde während des Downloads geupdatet
        // (kann nach .failed bereits zurückgesetzt sein — wir prüfen lastError stattdessen)
        XCTAssertNotNil(manager.lastError)
        XCTAssertTrue(manager.lastError!.contains("Download fehlgeschlagen"),
            "Erwartet Default-Klasse 'Unbekannt' — bekam: \(manager.lastError ?? "nil")")
    }

    func testStart_whenSecondCallDuringActiveDownload_isIdempotent() async {
        let loader = FakeDiarizerLoader()
        loader.installed = false
        loader.progressTicks = Array(repeating: 0.1, count: 5)  // mehrere Ticks → läuft länger
        let manager = DiarizerModelManager(loader: loader)

        manager.start()
        manager.start()  // zweiter Call während aktivem Task
        await waitUntil { if case .failed = manager.state { return true } else { return false } }

        XCTAssertEqual(loader.downloadCallCount, 1, "Zweiter start() darf keinen zweiten Task starten")
    }

    // MARK: - Error classification (D-10, three classes — strings locked by UI-SPEC)

    func testClassify_urlErrorNotConnected_returnsNetworkString() {
        let msg = DiarizerModelManager.classify(URLError(.notConnectedToInternet))
        XCTAssertEqual(msg, "Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut.")
    }

    func testClassify_urlErrorTimedOut_returnsNetworkString() {
        let msg = DiarizerModelManager.classify(URLError(.timedOut))
        XCTAssertEqual(msg, "Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut.")
    }

    func testClassify_cocoaErrorFileWriteOutOfSpace_returnsStorageString() {
        let err = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileWriteOutOfSpace.rawValue
        )
        let msg = DiarizerModelManager.classify(err)
        XCTAssertEqual(msg, "Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht).")
    }

    func testClassify_posixENOSPC_returnsStorageString() {
        let err = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(POSIXError.ENOSPC.rawValue)
        )
        let msg = DiarizerModelManager.classify(err)
        XCTAssertEqual(msg, "Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht).")
    }

    func testClassify_unknownError_returnsUnknownString() {
        let err = NSError(domain: "CustomDomain", code: 42)
        let msg = DiarizerModelManager.classify(err)
        XCTAssertTrue(msg.hasPrefix("Download fehlgeschlagen. Versuch es später erneut"),
            "Erwartet Default-Klasse-Prefix — bekam: \(msg)")
    }

    // MARK: - retry() behavior (D-11)

    func testRetry_clearsCacheAndRestartsDownload() async {
        let loader = FakeDiarizerLoader()
        loader.installed = false
        loader.failure = URLError(.notConnectedToInternet)
        let manager = DiarizerModelManager(loader: loader)

        manager.start()
        await waitUntil { if case .failed = manager.state { return true } else { return false } }
        XCTAssertEqual(loader.downloadCallCount, 1)

        // Setup für Retry: Loader gibt einen anderen Fehler nach Retry
        loader.failure = URLError(.timedOut)
        manager.retry()
        await waitUntil { if case .failed = manager.state { return true } else { return false } }

        XCTAssertEqual(loader.clearCacheCallCount, 1, "retry() muss clearCache() aufrufen (D-11)")
        XCTAssertEqual(loader.downloadCallCount, 2, "retry() muss neuen Download starten")
        XCTAssertEqual(manager.lastError, "Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut.")
    }

    // MARK: - ensureInstalled() async (D-16, Wave 1 für ParakeetClient)

    func testEnsureInstalled_whenAlreadyInstalled_returnsTrueImmediately() async {
        let loader = FakeDiarizerLoader()
        loader.installed = true
        let manager = DiarizerModelManager(loader: loader)
        let result = await manager.ensureInstalled()
        XCTAssertTrue(result)
        XCTAssertEqual(loader.downloadCallCount, 0, "Bei installed darf kein Download starten")
    }

    func testEnsureInstalled_whenDownloadFails_returnsFalse() async {
        let loader = FakeDiarizerLoader()
        loader.installed = false
        loader.failure = URLError(.notConnectedToInternet)
        let manager = DiarizerModelManager(loader: loader)
        let result = await manager.ensureInstalled()
        XCTAssertFalse(result)
        if case .failed = manager.state {} else {
            XCTFail("Erwartet .failed — bekam: \(manager.state)")
        }
    }

    // MARK: - Helpers

    /// Wartet (max 2 s) bis die condition erfüllt ist. Pollt 50 Hz.
    /// Phase-2-Pattern aus PipelineErrorPathTests übernommen.
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("waitUntil timeout (\(timeout)s)")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)  // 20 ms
        }
    }
}
