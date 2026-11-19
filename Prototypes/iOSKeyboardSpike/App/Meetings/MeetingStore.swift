import Foundation

enum MeetingStatus: Codable, Hashable {
    case recording
    case transcribing
    case diarizing
    case summarizing
    case done
    case failed(String)

    var label: String {
        switch self {
        case .recording: "Aufnahme läuft"
        case .transcribing: "Transkribiert …"
        case .diarizing: "Trennt Sprecher …"
        case .summarizing: "Schreibt Notizen …"
        case .done: "Fertig"
        case .failed(let reason): "Fehler: \(reason)"
        }
    }

    var isBusy: Bool {
        switch self {
        case .transcribing, .diarizing, .summarizing: true
        default: false
        }
    }
}

struct Meeting: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    let start: Date
    var end: Date?
    var status: MeetingStatus
    var transcript: String = ""
    /// Automatische Notizen (Markdown wie am Mac: Zusammenfassung, Entscheidungen, Aufgaben, Offene Fragen).
    var summary: String = ""
    /// Eigene Notizen, Stichpunkte, Aufgaben, während oder nach dem Meeting getippt.
    var ownNotes: String = ""

    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
    var words: Int { WordCounter.count(transcript) }

    /// „19.11.2026, 08:30 bis 09:12 Uhr“
    var timeRange: String {
        let day = start.formatted(date: .numeric, time: .omitted)
        let from = start.formatted(date: .omitted, time: .shortened)
        guard let end else { return "\(day), ab \(from) Uhr" }
        return "\(day), \(from) bis \(end.formatted(date: .omitted, time: .shortened)) Uhr"
    }

    /// Text für „Notizen kopieren“: Titel, Zeit, eigene und automatische Notizen.
    var notesForCopy: String {
        var parts = ["# \(title)", "Zeit: \(timeRange)"]
        let own = ownNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { parts.append("### Eigene Notizen\n\(own)") }
        if !summary.isEmpty { parts.append(summary) }
        return parts.joined(separator: "\n\n")
    }
}

/// Meetings liegen in Application Support/Meetings: eine Index-Datei plus Audio je Meeting.
@MainActor
final class MeetingStore: ObservableObject {
    @Published private(set) var meetings: [Meeting] = []

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("meetings.json") }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        recoverInterrupted()
    }

    func audioURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).m4a")
    }

    func meeting(_ id: UUID) -> Meeting? { meetings.first { $0.id == id } }

    func create() -> Meeting {
        let meeting = Meeting(id: UUID(), title: "Meeting", start: Date(), status: .recording)
        meetings.insert(meeting, at: 0)
        save()
        return meeting
    }

    func update(_ id: UUID, _ change: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        change(&meetings[index])
        save()
    }

    func delete(_ id: UUID) {
        meetings.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: audioURL(for: id))
        save()
    }

    /// Wurde die App während Aufnahme oder Verarbeitung beendet, bleibt sonst ein Meeting ewig „läuft“.
    private func recoverInterrupted() {
        var changed = false
        for index in meetings.indices where meetings[index].status == .recording || meetings[index].status.isBusy {
            meetings[index].status = .failed("unterbrochen, bitte erneut verarbeiten")
            if meetings[index].end == nil { meetings[index].end = meetings[index].start }
            changed = true
        }
        if changed { save() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Meeting].self, from: data) else { return }
        meetings = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(meetings) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
