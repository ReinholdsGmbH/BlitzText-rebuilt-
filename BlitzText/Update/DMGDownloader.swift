import Foundation

/// Lädt eine Datei per `URLSessionDownloadTask` mit echtem Fortschritts-Callback.
///
/// Warum ein Delegate statt `session.download(for:)`: nur der Download-Delegate liefert
/// `totalBytesWritten` → Fortschritt. Der fertige Temp-File aus `didFinishDownloadingTo`
/// wird von URLSession sofort nach Rückkehr des Callbacks gelöscht, daher verschieben wir
/// ihn SYNCHRON im Callback an unser Ziel.
///
/// Concurrency: `@unchecked Sendable`. Der veränderliche Zustand (Continuation) wird über
/// einen `NSLock` serialisiert; der Delegate feuert auf der (seriellen) `delegateQueue`.
final class DMGDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var didResume = false
    private var destination: URL?
    private var progressHandler: (@Sendable (Double) -> Void)?

    /// Lädt `url` nach `destination`. `progress` liefert 0…1 (bzw. bleibt bei 0,
    /// falls der Server keine Content-Length schickt). Wirft bei Netzwerk-/IO-Fehler.
    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        self.destination = destination
        self.progressHandler = progress

        var request = URLRequest(url: url)
        request.setValue("BlitzText-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        // Eigene, seriell zugestellte Session — kein Sharing mit `.shared`, damit der Delegate
        // eindeutig zu diesem Download gehört.
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.withLock { self.continuation = cont }
            session.downloadTask(with: request).resume()
        }
    }

    private func resume(throwing error: Error?) {
        lock.withLock {
            guard !didResume, let cont = continuation else { return }
            didResume = true
            continuation = nil
            if let error { cont.resume(throwing: error) } else { cont.resume() }
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }   // Content-Length unbekannt
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(min(max(fraction, 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination else {
            resume(throwing: CocoaError(.fileNoSuchFile))
            return
        }
        // Prüfe HTTP-Status: bei 4xx/5xx kommt die Fehlerseite als „erfolgreicher" Download an.
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            resume(throwing: UpdateCheckError.http(http.statusCode))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            resume(throwing: nil)
        } catch {
            resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Nur der Fehlerfall ist hier relevant — der Erfolg wird in didFinishDownloadingTo behandelt.
        if let error { resume(throwing: error) }
    }
}
