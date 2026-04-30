import Foundation
import Combine

/// Lifecycle für lokale Whisper-Modelle: Liste, Download mit Progress, Aktivierung, Löschung.
/// Modelle liegen unter `~/Library/Application Support/BlitzText/Models/<variant>/`.
@MainActor
final class LocalModelManager: ObservableObject {

    struct ModelInfo: Identifiable, Hashable {
        let id: String          // WhisperKit-Variant, z.B. "openai_whisper-base"
        let displayName: String
        let approxSizeMB: Int
        let isMultilingual: Bool
        let note: String?

        var displaySize: String {
            if approxSizeMB >= 1000 {
                return String(format: "%.1f GB", Double(approxSizeMB) / 1000.0)
            }
            return "\(approxSizeMB) MB"
        }

        var languageBadge: String {
            isMultilingual ? "99 Sprachen" : "Englisch"
        }
    }

    /// Kuratierte Auswahl aus dem WhisperKit/CoreML-Repo argmaxinc/whisperkit-coreml.
    /// `.en`-Varianten sind nur für Englisch — kleiner und schneller, aber nicht für Deutsch.
    static let available: [ModelInfo] = [
        // Tiny
        .init(id: "openai_whisper-tiny",                displayName: "Tiny",            approxSizeMB: 39,   isMultilingual: true,  note: "ultra-schnell, niedrige Qualität"),
        .init(id: "openai_whisper-tiny.en",             displayName: "Tiny (EN)",       approxSizeMB: 39,   isMultilingual: false, note: "nur Englisch, ultra-schnell"),
        // Base
        .init(id: "openai_whisper-base",                displayName: "Base",            approxSizeMB: 74,   isMultilingual: true,  note: "schnell, ok für klare Sprache"),
        .init(id: "openai_whisper-base.en",             displayName: "Base (EN)",       approxSizeMB: 74,   isMultilingual: false, note: "nur Englisch, schnell"),
        // Small
        .init(id: "openai_whisper-small",               displayName: "Small",           approxSizeMB: 244,  isMultilingual: true,  note: "guter Kompromiss"),
        .init(id: "openai_whisper-small.en",            displayName: "Small (EN)",      approxSizeMB: 244,  isMultilingual: false, note: "nur Englisch, präziser als Multi"),
        // Distil
        .init(id: "distil-whisper_distil-large-v3",     displayName: "Distil Large v3", approxSizeMB: 756,  isMultilingual: false, note: "Englisch-only, sehr schnell, hohe Qualität"),
        // Large v3 Turbo (Argmax-quantisiert, klein + multilingual)
        .init(id: "openai_whisper-large-v3-v20240930_turbo_632MB", displayName: "Large v3 Turbo (632 MB)", approxSizeMB: 632, isMultilingual: true, note: "quantisiert, schnell, multilingual"),
        // Large v3 turbo full
        .init(id: "openai_whisper-large-v3_turbo",      displayName: "Large v3 Turbo",  approxSizeMB: 809,  isMultilingual: true,  note: "schnell + multilingual, sehr gute Qualität"),
        // Large v3
        .init(id: "openai_whisper-large-v3",            displayName: "Large v3",        approxSizeMB: 1550, isMultilingual: true,  note: "beste Qualität, höchster Speicherbedarf")
    ]

    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var activeID: String? = UserDefaults.standard.string(forKey: activeKey)
    @Published var lastError: String?

    /// True während WhisperKit das Modell lädt (CoreML-Compile beim ersten Mal kann lange dauern).
    @Published var isPreloading: Bool = false
    /// ID des aktuell vorgeladenen / einsatzbereiten Modells.
    @Published var preloadedID: String?
    /// Wie lange der letzte Preload gedauert hat (für Anzeige).
    @Published var preloadDurationSeconds: Double?

    private static let activeKey = "de.reinholds.blitztext.activeLocalModel"

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    /// Wird nach `activate()` aufgerufen, damit der ModeProcessor das Modell preloaden kann.
    var onActivate: (@MainActor () -> Void)?

    init() {
        rescanDownloaded()
    }

    // MARK: - File system

    static var modelsRoot: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BlitzText", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    func folder(for id: String) -> URL {
        Self.modelsRoot.appendingPathComponent(id, isDirectory: true)
    }

    func rescanDownloaded() {
        var ids = Set<String>()
        for m in Self.available {
            let dir = folder(for: m.id)
            if FileManager.default.fileExists(atPath: dir.path),
               let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
               !contents.isEmpty {
                ids.insert(m.id)
            }
        }
        self.downloadedIDs = ids
        if let active = activeID, !ids.contains(active) {
            activeID = nil
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
        }
    }

    // MARK: - Activation

    func activate(_ id: String) {
        guard downloadedIDs.contains(id) else { return }
        activeID = id
        UserDefaults.standard.set(id, forKey: Self.activeKey)
        // Preloaden, sobald ein Modell aktiviert wird
        onActivate?()
    }

    func deactivate() {
        activeID = nil
        UserDefaults.standard.removeObject(forKey: Self.activeKey)
    }

    // MARK: - Delete

    func delete(_ id: String) {
        cancelDownload(id)
        let dir = folder(for: id)
        try? FileManager.default.removeItem(at: dir)
        downloadedIDs.remove(id)
        if activeID == id { deactivate() }
    }

    // MARK: - Download

    func cancelDownload(_ id: String) {
        downloadTasks[id]?.cancel()
        downloadTasks[id] = nil
        downloadProgress[id] = nil
    }

    /// Lädt das Modell asynchron herunter. Während Download läuft `downloadProgress[id]` (0…1).
    func download(_ id: String) {
        guard downloadTasks[id] == nil else { return }
        guard !downloadedIDs.contains(id) else { return }

        downloadProgress[id] = 0
        lastError = nil

        let dest = folder(for: id)
        let task = Task { [weak self] in
            let result = await ModelDownloader.downloadWhisperKitModel(
                variant: id,
                destination: dest,
                progress: { [weak self] frac in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress[id] = frac
                    }
                }
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.downloadProgress[id] = nil
                self.downloadTasks[id] = nil
                self.rescanDownloaded()
                if case .failure(let msg) = result {
                    self.lastError = "Download '\(id)' fehlgeschlagen: \(msg)"
                }
            }
        }
        downloadTasks[id] = task
    }
}
