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
    /// Zugriff aus der Ordnerwahl, offen gehalten bis die App endet. Hilft, wenn der Anbieter
    /// (z. B. Nextcloud) ein Lesezeichen liefert, das sich später nicht auflösen lässt.
    private var liveParent: URL?
    private var liveInbox: URL?
    private var resolveError: String?
    /// Das Lesezeichen zeigt direkt auf „BlitzText iPhone“ statt auf den gewählten Ordner.
    private let bookmarkIsInboxKey = "sharedFolderBookmarkIsInbox"
    private let displayNameKey = "sharedFolderName"

    init() {
        if resolve() != nil {
            folderName = UserDefaults.standard.string(forKey: displayNameKey) ?? resolve()?.lastPathComponent
        }
    }

    /// Ordner, in den die Pakete kommen („…/BlitzText iPhone“).
    private func packageRoot(from resolved: URL) -> URL {
        UserDefaults.standard.bool(forKey: bookmarkIsInboxKey)
            ? resolved
            : resolved.appendingPathComponent(PhoneMeetingPackage.folderName, isDirectory: true)
    }

    var isConfigured: Bool { folderName != nil }

    /// Übernimmt den gewählten Ordner. Anbieter wie Nextcloud liefern zunächst nur einen
    /// Platzhalter, für den iOS kein Lesezeichen anlegen kann („existiert nicht“). Deshalb legt
    /// die App zuerst koordiniert den Unterordner „BlitzText iPhone“ an und merkt sich diesen;
    /// erst wenn das nicht geht, den gewählten Ordner selbst.
    func choose(_ url: URL) {
        lastMessage = nil
        let scoped = url.startAccessingSecurityScopedResource()
        var keepAccess = false
        defer { if scoped && !keepAccess { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var createError: Error?
        var inbox: URL?
        NSFileCoordinator().coordinate(
            writingItemAt: url.appendingPathComponent(PhoneMeetingPackage.folderName, isDirectory: true),
            options: [], error: &coordinationError
        ) { target in
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                inbox = target
            } catch {
                createError = error
            }
        }
        guard let inbox else {
            let reason = (coordinationError ?? createError).map { $0.localizedDescription } ?? "unbekannt"
            lastMessage = "„\(url.lastPathComponent)“ nicht beschreibbar: \(reason)"
            return
        }

        var lastError: Error?
        for (candidate, isInbox) in [(inbox, true), (url, false)] {
            for options in [URL.BookmarkCreationOptions(), .minimalBookmark] {
                do {
                    let data = try candidate.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(data, forKey: bookmarkKey)
                    UserDefaults.standard.set(isInbox, forKey: bookmarkIsInboxKey)
                    UserDefaults.standard.set(url.lastPathComponent, forKey: displayNameKey)
                    folderName = url.lastPathComponent
                    if let previous = liveParent { previous.stopAccessingSecurityScopedResource() }
                    liveParent = scoped ? url : nil
                    liveInbox = inbox
                    keepAccess = true
                    lastMessage = "Ordner „\(url.lastPathComponent)“ gewählt."
                    return
                } catch {
                    lastError = error
                }
            }
        }
        lastMessage = "„\(url.lastPathComponent)“ nicht übernommen: \(lastError?.localizedDescription ?? "unbekannt")"
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
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            resolveError = "kein Ordner gewählt"
            return nil
        }
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            resolveError = error.localizedDescription
            return nil
        }
        resolveError = nil
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    /// Legt das Meeting als Paket ab: `<Ablage>/BlitzText iPhone/<Ordner>/meeting.json` und `audio.m4a`.
    /// Der Ordnername hängt nur an Beginn und ID, damit Umbenennen kein zweites Paket erzeugt.
    func deliver(_ id: UUID, store: MeetingStore, log: (String) -> Void) async {
        guard let meeting = store.meeting(id), meeting.status == .done else { return }
        let base: URL
        var scopedRoot: URL?
        if let liveInbox {
            base = liveInbox
        } else if let root = resolve() {
            if root.startAccessingSecurityScopedResource() { scopedRoot = root }
            base = packageRoot(from: root)
        } else {
            lastMessage = "Ablage nicht erreichbar (\(resolveError ?? "unbekannt")). Bitte den Ordner in den Einstellungen neu wählen."
            log("Ablage: Lesezeichen nicht auflösbar — \(resolveError ?? "unbekannt")")
            return
        }
        defer { scopedRoot?.stopAccessingSecurityScopedResource() }
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
            let target = base.appendingPathComponent(Self.packageFolderName(for: meeting), isDirectory: true)
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
