import Foundation
import Combine
import FluidAudio

/// State-Machine des Diarizer-Modell-Lifecycle.
/// Spec: 03-CONTEXT.md D-15.
enum DiarizerModelState: Equatable {
    case notInstalled
    case downloading(progress: Double, etaSeconds: Double?)
    case installed
    case failed(message: String)
}

/// `@MainActor`-Lifecycle-Manager für das FluidAudio-Diarizer-Modell.
/// Wrapped `DiarizerModels.downloadIfNeeded(progressHandler:)` (Variant A —
/// siehe ADR in 03-01-PLAN.md). Spec: 03-CONTEXT.md D-15, D-16.
@MainActor
final class DiarizerModelManager: ObservableObject {

    // MARK: - Published state for UI consumption

    @Published private(set) var state: DiarizerModelState = .notInstalled
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var etaSeconds: Double?
    @Published private(set) var lastError: String?

    // MARK: - Dependencies (DI seam, Phase-2-Pattern)

    private let loader: DiarizerLoaderProtocol
    private var loadingTask: Task<Void, Never>?
    private var cachedModels: DiarizerModels?
    private var etaEstimator: ETAEstimator

    init(
        loader: DiarizerLoaderProtocol = FluidAudioDiarizerLoader(),
        etaWindowSeconds: TimeInterval = 5.0
    ) {
        self.loader = loader
        self.etaEstimator = ETAEstimator(windowSeconds: etaWindowSeconds)
        // Initialer State spiegelt Disk-Realität (D-13 Pre-Warm vorbereitend)
        if loader.isInstalled() {
            self.state = .installed
        }
    }

    // MARK: - Public API for UI + ParakeetClient

    /// Sync-Existenz-Check ohne Inferenz. Wird von `ParakeetClient.ensureLoaded`
    /// und `AppDelegate.bootstrap` (Pre-Warm) aufgerufen.
    var isInstalled: Bool { loader.isInstalled() }

    /// Cached `DiarizerModels`-Instanz für `ParakeetClient`-Konsum (D-16).
    /// `nil` wenn nicht installiert oder noch nicht geladen.
    var modelsIfInstalled: DiarizerModels? { cachedModels }

    /// Toggle-On-Trigger (D-01). Idempotent: zweiter Call während aktivem
    /// Download ist No-Op.
    func start() {
        // D-02: bereits installiert + im Cache → fertig, kein Download
        if loader.isInstalled(), cachedModels != nil {
            state = .installed
            return
        }
        // Dateien extern gelöscht — stale In-Memory-Referenz verwerfen,
        // sonst gibt FluidAudio's downloadIfNeeded sofort zurück (kein Progress).
        if !loader.isInstalled() {
            loader.clearCache()
            cachedModels = nil
        }
        guard loadingTask == nil else { return }
        beginDownload()
    }

    /// User-Klick auf "Erneut versuchen" (D-10, D-11).
    func retry() {
        // Pitfall 4 mitigation: alten Task canceln vor neuem Download
        loadingTask?.cancel()
        loadingTask = nil
        // D-11: partielle Dateien löschen vor Retry
        loader.clearCache()
        cachedModels = nil
        lastError = nil
        beginDownload()
    }

    /// Best-effort Pre-Warm beim App-Start (D-13, D-14).
    /// Wird von `AppDelegate.bootstrap` aufgerufen wenn `parakeetDiarization == true`.
    /// Fehler im Pre-Warm setzen `lastError`, aber App-Start blockiert nie.
    func prewarm() {
        // Wenn schon installiert + cached → nichts zu tun
        if loader.isInstalled(), cachedModels != nil {
            state = .installed
            return
        }
        // Sonst: regulärer Download-Pfad. Wenn Files schon da sind, ist das
        // ein No-Op-Download, der nur die MLModels in cachedModels lädt.
        // Wenn Files fehlen: echter Download mit Progress.
        guard loadingTask == nil else { return }
        beginDownload()
    }

    /// Async-Variante von `start()` — wartet auf Abschluss des Download/Compile-Schritts.
    /// Rückgabe: `true` wenn am Ende `state == .installed`, sonst `false` (failed/notInstalled).
    /// Wird von `ParakeetClient.ensureLoaded()` aufgerufen (D-16).
    /// Idempotent: bei `.installed` direkter Return; bei laufendem Task wird auf dessen Abschluss gewartet.
    @discardableResult
    func ensureInstalled() async -> Bool {
        // `.installed` heißt nur: Dateien liegen auf der Platte (so setzt es `init`). Geladen
        // sind die Modelle erst mit `cachedModels`. Ohne diese Prüfung bekam ein Aufrufer
        // `true` und danach `modelsIfInstalled == nil`. Bei vorhandenen Dateien lädt der
        // Download-Pfad nur noch, ohne etwas herunterzuladen.
        if case .installed = state, cachedModels != nil { return true }
        if loadingTask == nil {
            beginDownload()
        }
        // Snapshot des Tasks lokal halten — beginDownload setzt loadingTask = nil
        // im Erfolgs-/Fehler-Pfad bevor wir hier zurückkehren würden.
        let task = loadingTask
        await task?.value
        if case .installed = state, cachedModels != nil { return true }
        return false
    }

    // MARK: - Private

    private func beginDownload() {
        etaEstimator.reset()
        state = .downloading(progress: 0, etaSeconds: nil)
        downloadProgress = 0
        etaSeconds = nil
        lastError = nil
        Log.write("DiarizerModelManager: Download gestartet")

        let task = Task { [weak self, loader] in
            do {
                let models = try await loader.downloadIfNeeded(
                    progressHandler: { [weak self] fraction in
                        // Worker-Thread → MainActor (RESEARCH.md § Concurrency)
                        Task { @MainActor [weak self] in
                            self?.handleProgress(fraction: fraction)
                        }
                    }
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.cachedModels = models
                    self.state = .installed
                    self.downloadProgress = nil
                    self.etaSeconds = nil
                    self.loadingTask = nil
                    Log.write("DiarizerModelManager: bereit (Modell installiert)")
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let msg = Self.classify(error)
                    self.lastError = msg
                    self.state = .failed(message: msg)
                    self.downloadProgress = nil
                    self.etaSeconds = nil
                    self.loadingTask = nil
                    Log.write("DiarizerModelManager: Download fehlgeschlagen — \(error.localizedDescription) → '\(msg)'")
                }
            }
        }
        loadingTask = task
    }

    private func handleProgress(fraction: Double) {
        let now = Date()
        let eta = etaEstimator.tick(fraction: fraction, now: now)
        downloadProgress = fraction
        etaSeconds = eta
        state = .downloading(progress: fraction, etaSeconds: eta)
    }

    // MARK: - Error Classification (D-10, drei deutsche Klassen)
    // Strings sind LOCKED durch UI-SPEC § Copywriting Contract — bei Änderung
    // muss UI-SPEC zuerst geändert werden.

    static func classify(_ error: Error) -> String {
        // Klasse 1: Netzwerk
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .secureConnectionFailed,
                 .resourceUnavailable,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return "Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut."
            default:
                break
            }
        }
        // Klasse 2: Speicher
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain
            && ns.code == CocoaError.Code.fileWriteOutOfSpace.rawValue {
            return "Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht)."
        }
        if ns.domain == NSPOSIXErrorDomain
            && ns.code == Int(POSIXError.ENOSPC.rawValue) {
            return "Nicht genug Speicherplatz für den Download (~80 MB werden gebraucht)."
        }
        // FluidAudio-Errors → Netzwerk-Klasse (HF-Server-Probleme)
        if let hf = error as? DownloadUtils.HuggingFaceDownloadError {
            switch hf {
            case .rateLimited, .invalidResponse, .htmlErrorResponse, .downloadFailed:
                return "Verbindung fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut."
            case .modelNotFound:
                return "Download fehlgeschlagen. Versuch es später erneut — wenn das Problem bleibt, schau in das Log unter ~/Library/Logs/BlitzText.log."
            }
        }
        // Klasse 3: Unbekannt (Default)
        return "Download fehlgeschlagen. Versuch es später erneut — wenn das Problem bleibt, schau in das Log unter ~/Library/Logs/BlitzText.log."
    }
}
