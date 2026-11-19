import Foundation

/// Was der Mac aus der gemeinsamen Ablage liest. Format bewusst schlicht und versioniert.
struct PhoneMeetingPackage: Codable {
    var format = "blitztext-iphone-meeting"
    var version = 1
    let id: String
    let title: String
    let start: Date
    let end: Date?
    /// Wann das iPhone das Paket geschrieben hat; neuer als beim letzten Abholen heißt „aktualisiert“.
    let sharedAt: Date
    let transcript: String
    let segments: [TranscriptSegment]
    /// Automatische Notizen (Markdown).
    let summary: String
    let ownNotes: String
    let audioFile: String?

    static let fileName = "meeting.json"
    static let audioName = "audio.m4a"
    static let folderName = "BlitzText iPhone"
}

/// Gemeinsame Ablage ohne iCloud-Berechtigung: ein Ordner, den du in der Dateien-App wählst
/// (iCloud Drive, OneDrive …). Die App merkt sich den Zugriff als Lesezeichen.
@MainActor
final class SharedFolder: ObservableObject {
    @Published private(set) var folderName: String?
    @Published private(set) var lastMessage: String?
    @Published var autoDeliver: Bool = UserDefaults.standard.object(forKey: "sharedFolderAuto") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoDeliver, forKey: "sharedFolderAuto") }
    }

    private let bookmarkKey = "sharedFolderBookmark"

    init() {
        folderName = resolve()?.lastPathComponent
    }

    var isConfigured: Bool { folderName != nil }

    /// Übernimmt den gewählten Ordner. Manche Anbieter (z. B. Nextcloud) liefern kein volles
    /// Lesezeichen; dann wird ein minimales versucht. Danach ein Probeschreiben, damit ein
    /// Ordner ohne Schreibrecht sofort auffällt statt erst beim ersten Meeting.
    func choose(_ url: URL) {
        lastMessage = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            do {
                data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch let fallbackError {
                lastMessage = "„\(url.lastPathComponent)“ nicht übernommen: \(fallbackError.localizedDescription) (Zugriff beim Start: \(scoped ? "ja" : "nein"))"
                return
            }
        }
        let probe = url.appendingPathComponent(PhoneMeetingPackage.folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
        } catch {
            lastMessage = "„\(url.lastPathComponent)“ gewählt, aber nicht beschreibbar: \(error.localizedDescription)"
            return
        }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        folderName = url.lastPathComponent
        lastMessage = "Ordner „\(url.lastPathComponent)“ gewählt."
    }

    func report(_ error: Error) {
        lastMessage = nil
        lastMessage = "Ordnerwahl fehlgeschlagen: \(error.localizedDescription)"
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
    }

    private func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    /// Legt das Meeting als Paket ab: `<Ablage>/BlitzText iPhone/<Ordner>/meeting.json` und `audio.m4a`.
    /// Der Ordnername hängt nur an Beginn und ID, damit Umbenennen kein zweites Paket erzeugt.
    func deliver(_ id: UUID, store: MeetingStore, log: (String) -> Void) async {
        guard let root = resolve() else { lastMessage = "Keine gemeinsame Ablage gewählt."; return }
        guard let meeting = store.meeting(id), meeting.status == .done else { return }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        do {
            let audio = try? await MeetingExport.audioFile(for: meeting, parts: store.audioURLs(for: id))
            let package = PhoneMeetingPackage(
                id: meeting.id.uuidString, title: meeting.title, start: meeting.start, end: meeting.end,
                sharedAt: Date(), transcript: meeting.transcript, segments: meeting.segments ?? [],
                summary: meeting.summary, ownNotes: meeting.ownNotes,
                audioFile: audio == nil ? nil : PhoneMeetingPackage.audioName)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = try encoder.encode(package)
            let target = root.appendingPathComponent(PhoneMeetingPackage.folderName, isDirectory: true)
                .appendingPathComponent(Self.packageFolderName(for: meeting), isDirectory: true)
            try write(json: json, audio: audio, to: target)
            store.update(id) { $0.sharedAt = package.sharedAt }
            lastMessage = "„\(meeting.title)“ abgelegt."
            log("Ablage: \(meeting.title) → \(target.lastPathComponent)")
        } catch {
            lastMessage = "Ablegen fehlgeschlagen: \(error.localizedDescription)"
            log("Ablage-Fehler: \(error.localizedDescription)")
        }
    }

    /// „2026-11-19 10-07 iPhone 1A2B3C4D“
    static func packageFolderName(for meeting: Meeting) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return "\(formatter.string(from: meeting.start)) iPhone \(meeting.id.uuidString.prefix(8))"
    }

    /// Schreibt koordiniert, damit iCloud Drive oder OneDrive nicht mitten im Schreiben synchronisiert.
    private func write(json: Data, audio: URL?, to folder: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { url in
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                if let audio {
                    let audioTarget = url.appendingPathComponent(PhoneMeetingPackage.audioName)
                    try? fm.removeItem(at: audioTarget)
                    try fm.copyItem(at: audio, to: audioTarget)
                }
                // JSON zuletzt: Der Mac holt ein Paket erst ab, wenn meeting.json da ist.
                try json.write(to: url.appendingPathComponent(PhoneMeetingPackage.fileName), options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
    }
}
