import Foundation

/// Append-Only Log nach ~/Library/Logs/BlitzText.log mit Größen-Rotation.
///
/// WICHTIG (DSGVO): Hier dürfen KEINE Transkript-Inhalte und KEINE Sprecher-Klarnamen
/// landen. Aufrufer loggen nur Längen/Zähler/IDs, niemals den dictierten Text selbst.
enum Log {
    /// Ab dieser Größe wird die aktuelle Datei nach `.old` rotiert und neu begonnen.
    private static let maxBytes = 2 * 1024 * 1024

    private static let url: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("BlitzText.log")
    }()

    /// Serielle Queue: serialisiert Datei-Append UND den (nicht thread-sicheren) DateFormatter.
    private static let queue = DispatchQueue(label: "de.reinholds.blitztext.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ msg: String) {
        let now = Date()
        queue.async {
            rotateIfNeeded()
            let line = "[\(formatter.string(from: now))] \(msg)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: url)
            }
        }
        #if DEBUG
        // Nur im Debug-Build in Console.app spiegeln — sonst wäre der Inhalt im
        // systemweiten Unified Log für andere Prozesse sichtbar.
        NSLog("[BlitzText] %@", msg)
        #endif
    }

    /// Rotiert die Logdatei, wenn sie `maxBytes` überschreitet (überschreibt die vorige `.old`).
    private static func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > maxBytes else { return }
        let rotated = url.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }
}
