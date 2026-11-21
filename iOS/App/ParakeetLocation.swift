import FluidAudio
import Foundation

/// Parakeet v3 liegt im gemeinsamen Ordner der App Group. Die Tastatur nutzt es derzeit nicht
/// (Apples Erkennung startet dort ohne Ladezeit), der Ordner bleibt aber, damit kein
/// bereits verschobenes Modell neu geladen werden muss.
enum ParakeetLocation {
    static var directory: URL? {
        Blitz.containerURL?
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(AsrModels.defaultCacheDirectory().lastPathComponent, isDirectory: true)
    }

    static var isStaged: Bool {
        directory.map { AsrModels.modelsExist(at: $0, version: .v3) } ?? false
    }

    /// Modell bereitstellen: ein früher in den App-Ordner geladenes Modell wird verschoben statt
    /// neu geladen, sonst lädt FluidAudio es herunter.
    static func ensureModels() async throws -> URL {
        guard let target = directory else { return try await AsrModels.download() }
        let legacy = AsrModels.defaultCacheDirectory()
        let files = FileManager.default
        if !AsrModels.modelsExist(at: target, version: .v3), AsrModels.modelsExist(at: legacy, version: .v3) {
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? files.removeItem(at: target)
            try files.moveItem(at: legacy, to: target)
        }
        return try await AsrModels.download(to: target)
    }
}
