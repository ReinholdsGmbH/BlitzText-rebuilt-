import FluidAudio
import Foundation

/// Parakeet TDT v3 über FluidAudio, gleiches Muster wie `ParakeetClient` auf macOS.
/// Lädt das Modell beim ersten Aufruf (Download beim allerersten Start).
actor ParakeetEngine {
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    func load() async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let task = Task {
            let manager = AsrManager(config: .default)
            try await manager.loadModels(AsrModels.downloadAndLoad())
            return manager
        }
        loading = task
        do {
            let loaded = try await task.value
            manager = loaded
            return loaded
        } catch {
            loading = nil
            throw error
        }
    }

    /// Für Meetings: volles Ergebnis mit Zeitstempeln pro Token (für die Sprecherzuordnung).
    func transcribe(samples: [Float]) async throws -> ASRResult {
        let manager = try await load()
        var state = TdtDecoderState.make()
        return try await manager.transcribe(samples, decoderState: &state)
    }

    func transcribe(_ url: URL) async throws -> String {
        let manager = try await load()
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(url, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
