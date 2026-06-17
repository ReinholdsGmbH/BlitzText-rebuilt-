import Foundation
import WhisperKit

/// Wrappt den WhisperKit-Download mit Progress-Callback in eine simplere API.
enum ModelDownloader {

    enum Result: Sendable {
        case success
        case failure(String)
    }

    /// Lädt eine WhisperKit-Variante in `destination`. Gibt Status zurück.
    static func downloadWhisperKitModel(
        variant: String,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> Result {
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

            let downloaded = try await WhisperKit.download(
                variant: variant,
                downloadBase: destination.deletingLastPathComponent(),
                useBackgroundSession: false,
                from: "argmaxinc/whisperkit-coreml",
                progressCallback: { p in
                    progress(p.fractionCompleted)
                }
            )
            Log.write("WhisperKit-Download abgeschlossen: \(variant) → \(downloaded.path)")

            // WhisperKit speichert i.d.R. unter <downloadBase>/<variant>/. Wenn der Pfad
            // nicht mit unserem destination übereinstimmt, ggf. verschieben.
            if downloaded.path != destination.path,
               FileManager.default.fileExists(atPath: downloaded.path) {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                // `try` statt `try?`: schlägt das Verschieben fehl, liegt das Modell NICHT am
                // erwarteten Pfad — dann muss der Aufrufer .failure sehen, nicht fälschlich .success.
                try FileManager.default.moveItem(at: downloaded, to: destination)
            }
            return .success
        } catch {
            Log.write("WhisperKit-Download fehlgeschlagen für \(variant): \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }
}
