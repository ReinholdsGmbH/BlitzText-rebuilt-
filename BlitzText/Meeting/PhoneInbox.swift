import Foundation

/// Ein Meeting, das die iPhone-App in die gemeinsame Ablage gelegt hat
/// (`<Ablage>/BlitzText iPhone/<Ordner>/meeting.json` plus `audio.m4a`).
struct PhoneMeetingPackage: Codable, Equatable {
    struct Segment: Codable, Equatable {
        /// „1“, „2“ … oder nil, wenn nur eine Stimme erkannt wurde.
        let speaker: String?
        let start: Double
        let end: Double
        let text: String
    }

    let format: String
    let version: Int
    let id: String
    let title: String
    let start: Date
    let end: Date?
    let sharedAt: Date
    let transcript: String
    let segments: [Segment]
    let summary: String
    let ownNotes: String
    let audioFile: String?

    static let fileName = "meeting.json"
    static let folderName = "BlitzText iPhone"
    static let expectedFormat = "blitztext-iphone-meeting"
}

enum PhoneInbox {
    static func decode(_ data: Data) throws -> PhoneMeetingPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PhoneMeetingPackage.self, from: data)
    }

    /// Baut das Mac-Meeting aus dem Paket, ohne neu zu transkribieren: Abschnitte werden
    /// Protokollzeilen, die Notizen vom iPhone die Zusammenfassung. Alle Stimmen gelten als
    /// Gegenseite, weil das iPhone nur ein Mikrofon hat.
    static func document(from package: PhoneMeetingPackage) -> MeetingDocument {
        var lines = package.segments.map {
            TranscriptLine(speaker: .others, start: $0.start, end: $0.end, text: $0.text, speakerID: $0.speaker)
        }
        if lines.isEmpty, !package.transcript.isEmpty {
            lines = [TranscriptLine(speaker: .others, start: 0, end: 0, text: package.transcript)]
        }
        let duration = package.end.map { $0.timeIntervalSince(package.start) } ?? (lines.last?.end ?? 0)
        var document = MeetingDocument(
            startedAt: package.start,
            duration: max(duration, 0),
            sourceNames: ["iPhone"],
            lines: lines,
            summary: package.summary.isEmpty ? nil : package.summary,
            notes: ["Vom iPhone übernommen; Transkript und Notizen unverändert."],
            diarizedTrack: MeetingArchive.mixedTrackFile
        )
        document.aiTitle = package.title.isEmpty || package.title == "Meeting" ? nil : package.title
        let own = package.ownNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        document.userNotes = own.isEmpty ? nil : own
        return document
    }

    /// Paketordner, deren meeting.json vorliegt. Gesucht wird in „<Ablage>/BlitzText iPhone“
    /// und direkt in der Ablage; Letzteres für den OneDrive-App-Ordner „Apps/BlitzText iPhone“,
    /// den man direkt wählt. Liegt eine Datei bei iCloud Drive nur in der Cloud
    /// („.meeting.json.icloud“), wird der Download angestoßen und das Paket später geholt.
    static func packageFolders(in root: URL) -> [URL] {
        let fm = FileManager.default
        let nested = root.appendingPathComponent(PhoneMeetingPackage.folderName, isDirectory: true)
        let folders = [nested, root].flatMap { base in
            (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        }
        return folders.filter { folder in
            let json = folder.appendingPathComponent(PhoneMeetingPackage.fileName)
            if fm.fileExists(atPath: json.path) { return true }
            let placeholder = folder.appendingPathComponent(".\(PhoneMeetingPackage.fileName).icloud")
            if fm.fileExists(atPath: placeholder.path) { try? fm.startDownloadingUbiquitousItem(at: json) }
            return false
        }
    }
}

/// Holt Pakete aus der gemeinsamen Ablage ins Meeting-Archiv und spiegelt sie in den
/// Wissensordner. Merkt sich je Paket-ID den Stand; ein neuerer Stand aktualisiert das Meeting.
@MainActor
final class PhoneInboxImporter {
    private struct Imported: Codable {
        var sharedAt: Date
        var folder: String
    }

    private let archive: MeetingArchive
    private let makeExporter: () -> VaultExporter?
    private let rootPath: () -> String
    private let onSaved: (URL) -> Void
    private let stateURL: URL?
    private var imported: [String: Imported] = [:]
    private var running = false
    private var timer: Timer?

    /// „Jetzt abholen“ aus den Einstellungen.
    static let pollNow = Notification.Name("BlitzTextPhoneInboxPollNow")

    static var defaultState: URL? {
        guard !RuntimeEnvironment.isRunningTests else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BlitzText/iphone-ablage.json")
    }

    init(archive: MeetingArchive, makeExporter: @escaping () -> VaultExporter?, rootPath: @escaping () -> String,
         stateURL: URL? = PhoneInboxImporter.defaultState, onSaved: @escaping (URL) -> Void) {
        self.archive = archive
        self.makeExporter = makeExporter
        self.rootPath = rootPath
        self.stateURL = stateURL
        self.onSaved = onSaved
        loadState()
    }

    /// Prüft jetzt und danach alle zwei Minuten.
    func start() {
        Task { await poll() }
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { Task { await self?.poll() } }
        }
    }

    /// Liefert die Zahl der neu übernommenen oder aktualisierten Meetings.
    @discardableResult
    func poll() async -> Int {
        let path = (rootPath() as NSString).expandingTildeInPath
        guard !path.isEmpty, !running else { return 0 }
        running = true
        defer { running = false }
        var count = 0
        for folder in PhoneInbox.packageFolders(in: URL(fileURLWithPath: path, isDirectory: true)) {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(PhoneMeetingPackage.fileName)),
                  let package = try? PhoneInbox.decode(data),
                  package.format == PhoneMeetingPackage.expectedFormat else { continue }
            if let known = imported[package.id], known.sharedAt >= package.sharedAt { continue }
            do {
                try await take(package, from: folder)
                count += 1
            } catch {
                Log.write("iPhone-Ablage: \(folder.lastPathComponent) nicht übernommen — \(error.localizedDescription)")
            }
        }
        return count
    }

    private func take(_ package: PhoneMeetingPackage, from source: URL) async throws {
        let fm = FileManager.default
        var document = PhoneInbox.document(from: package)
        let target: URL
        if let known = imported[package.id], fm.fileExists(atPath: known.folder),
           let existing = archive.load(folder: URL(fileURLWithPath: known.folder)) {
            // Aktualisierung: Was am Mac nachgetragen wurde, bleibt.
            target = URL(fileURLWithPath: known.folder)
            document.speakerNames = existing.speakerNames
            document.nameSources = existing.nameSources
            document.project = existing.project
            document.projectChosenByUser = existing.projectChosenByUser
            document.vaultFile = existing.vaultFile
            if existing.titleChosenByUser == true {
                document.aiTitle = existing.aiTitle
                document.titleChosenByUser = true
            }
        } else {
            target = try archive.makeFolder(startedAt: package.start, sourceName: "iPhone")
        }

        if let audioName = package.audioFile {
            let audio = source.appendingPathComponent(audioName)
            let wav = target.appendingPathComponent(MeetingArchive.mixedTrackFile)
            if fm.fileExists(atPath: audio.path) {
                try? fm.removeItem(at: wav)
                _ = try await Task.detached(priority: .utility) { try MeetingImport.convert(audio, to: wav) }.value
            }
        }

        let exporter = makeExporter()
        if exporter != nil, document.projectChosenByUser != true, document.project == nil {
            document.project = VaultExporter.detectProject(for: document)
        }
        let saved = archive.persist(document, in: target, exporter: exporter)
        if let error = saved.exportError {
            Log.write("iPhone-Ablage: \(package.title) gespeichert, nicht im Wissensordner — \(error.localizedDescription)")
        } else {
            Log.write("iPhone-Ablage: \(package.title) übernommen → \(saved.document.vaultFile ?? target.lastPathComponent)")
        }
        imported[package.id] = Imported(sharedAt: package.sharedAt, folder: target.path)
        saveState()
        onSaved(target)
    }

    private func loadState() {
        guard let stateURL, let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        imported = (try? decoder.decode([String: Imported].self, from: data)) ?? [:]
    }

    private func saveState() {
        guard let stateURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(imported).write(to: stateURL, options: .atomic)
    }
}
