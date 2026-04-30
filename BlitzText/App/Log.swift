import Foundation

/// Append-Only Log nach ~/Library/Logs/BlitzText.log
enum Log {
    private static let url: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs!, withIntermediateDirectories: true)
        return logs!.appendingPathComponent("BlitzText.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ msg: String) {
        let line = "[\(formatter.string(from: Date()))] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        NSLog("[BlitzText] %@", msg)
    }
}
