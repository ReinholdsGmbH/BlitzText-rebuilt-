import Foundation
import FluidAudio

/// Test-Seam für `DiarizerModelManager`. Production-Default ist
/// `FluidAudioDiarizerLoader`; Tests injizieren `FakeDiarizerLoader`.
/// Pattern analog Phase-2-`RecorderProtocol` (DI-Seam ohne Netzwerk).
protocol DiarizerLoaderProtocol: Sendable {
    /// Lädt das Diarizer-Modell, falls noch nicht vorhanden.
    /// `progressHandler` bekommt `fractionCompleted ∈ [0, 1]`.
    /// Wirft bei Netzwerk-/Speicher-/HF-Fehler — Klassifikation übernimmt der Manager.
    func downloadIfNeeded(
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> DiarizerModels

    /// Sync-Existenz-Check ohne Inferenz (Pre-Warm-Detection D-13).
    func isInstalled() -> Bool

    /// Cache-Cleanup vor Retry (D-11).
    func clearCache()
}

/// Production-Implementation. Konsumiert FluidAudio 0.14.3 direkt
/// (Variant A — siehe ADR in 03-01-PLAN.md).
struct FluidAudioDiarizerLoader: DiarizerLoaderProtocol {

    /// Basis-Verzeichnis für FluidAudio-Modelle (Default-Pfad).
    /// `~/Library/Application Support/FluidAudio/Models/`
    private static var fluidAudioModelsRoot: URL? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// Diarizer-Repo-Folder unter dem FluidAudio-Models-Root.
    /// `~/Library/Application Support/FluidAudio/Models/speaker-diarization/`
    private static var diarizerRepoDir: URL? {
        Self.fluidAudioModelsRoot?
            .appendingPathComponent("speaker-diarization", isDirectory: true)
    }

    func downloadIfNeeded(
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> DiarizerModels {
        let wrapped: DownloadUtils.ProgressHandler? = progressHandler.map { ph in
            let handler: DownloadUtils.ProgressHandler = { (p: DownloadUtils.DownloadProgress) in
                ph(p.fractionCompleted)
            }
            return handler
        }
        return try await DiarizerModels.downloadIfNeeded(progressHandler: wrapped)
    }

    func isInstalled() -> Bool {
        // FluidAudio-Default-Pfad: ~/Library/Application Support/FluidAudio/Models/speaker-diarization/
        // Source: 03-RESEARCH.md § FluidAudio Internals, On-Disk-Layout
        guard let dir = Self.diarizerRepoDir else { return false }
        let seg = dir.appendingPathComponent(ModelNames.Diarizer.segmentationFile)
        let emb = dir.appendingPathComponent(ModelNames.Diarizer.embeddingFile)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: seg.path, isDirectory: &isDir) && isDir.boolValue
            && fm.fileExists(atPath: emb.path, isDirectory: &isDir) && isDir.boolValue
    }

    func clearCache() {
        guard let modelsRoot = Self.fluidAudioModelsRoot else { return }
        // FluidAudio's eigene Cleanup-API. Beim Aufruf: Repo-spezifisches Verzeichnis
        // wird gelöscht — nicht die ASR-Modelle daneben (separater Repo-Folder).
        // `Repo` ist top-level public enum (FluidAudio.ModelNames.swift:4).
        DownloadUtils.clearModelCache(forRepo: .diarizer, directory: modelsRoot)
    }
}
