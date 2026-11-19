import AVFoundation
import SwiftUI
import UIKit

/// Baut aus allen Audio-Teilen eines Meetings eine einzige M4A-Datei für den Mac.
/// Dateiname „dd.mm.jj_hh.mm_Titel.m4a“ wie beim Wissensordner-Export am Mac; der Mac-Import
/// liest daraus den Beginn. Eigene Notizen stehen im Kommentar-Feld, der Titel im Titel-Feld.
enum MeetingExport {
    enum ExportError: LocalizedError {
        case noAudio
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .noAudio: "Zu diesem Meeting gibt es kein Audio."
            case .exportFailed: "Audiodatei ließ sich nicht erstellen."
            }
        }
    }

    @MainActor
    static func audioFile(for meeting: Meeting, parts: [URL]) async throws -> URL {
        guard !parts.isEmpty else { throw ExportError.noAudio }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.exportFailed
        }
        var cursor = CMTime.zero
        for url in parts {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(fileName(for: meeting))

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.exportFailed
        }
        var metadata = [item(.iTunesMetadataSongName, meeting.title)]
        let notes = meeting.ownNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { metadata.append(item(.iTunesMetadataUserComment, notes)) }
        session.metadata = metadata
        try await session.export(to: target, as: .m4a)
        return target
    }

    /// „19.11.26_10.07_Titel.m4a“; Zeichen, die Finder oder Dateisysteme stören, werden ersetzt.
    static func fileName(for meeting: Meeting) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yy_HH.mm"
        let title = meeting.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return formatter.string(from: meeting.start) + "_" + String(title.prefix(80)) + ".m4a"
    }

    private static func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}

/// Teilen-Dialog des Systems (AirDrop an den Mac, In Dateien sichern …).
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}
