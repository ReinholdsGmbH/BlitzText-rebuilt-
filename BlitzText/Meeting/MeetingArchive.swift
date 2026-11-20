import Foundation

/// Inhalt eines Meetings, unabhängig von der Darstellung. Liegt als `meeting.json` im
/// Meeting-Ordner; `protokoll.md` wird daraus erzeugt.
struct MeetingDocument: Codable, Equatable {
    var startedAt: Date
    var duration: TimeInterval
    var sourceNames: [String]
    var lines: [TranscriptLine]
    /// Markdown der Zusammenfassung, `nil` solange sie fehlt oder fehlgeschlagen ist.
    var summary: String?
    /// Hinweise, die ins Protokoll gehören, etwa „Systemaudio war stumm".
    var notes: [String]
    /// Sprecher-ID → Name. Aus einem bekannten Profil, aus der Meeting-App oder von Hand.
    var speakerNames: [String: String] = [:]
    /// Woher ein Name stammt. Nur `confirmed` und `profile` bauen bzw. schärfen Profile.
    var nameSources: [String: NameSource] = [:]
    /// Spur im Meeting-Ordner, deren Stimmen getrennt wurden. Aus ihr entstehen Profile.
    var diarizedTrack: String = MeetingArchive.othersTrackFile
    /// Kurzer Titel aus der Zusammenfassung. Optional, damit ältere meeting.json lesbar bleiben.
    var aiTitle: String?
    /// Titel von Hand gesetzt: „Neu erstellen“ der Notizen überschreibt ihn dann nicht.
    var titleChosenByUser: Bool?
    /// Eigene Notizen, während oder nach dem Meeting geschrieben.
    var userNotes: String?

    /// Was das Modell für die Zusammenfassung bekommt: Gesprächsverlauf plus eigene Notizen.
    var summaryInput: String {
        guard let notes = userNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return transcriptText
        }
        return transcriptText + "\n\nNotizen von „Ich“ (Protokollierende Person) zum Meeting:\n" + notes
    }
    /// Bereichsschlüssel im Wissensordner (mw-route-Logik), z. B. „pag“. Von Hand überschreibbar.
    var project: String?
    /// Vom Nutzer gewählter Bereich hat Vorrang vor der Erkennung.
    var projectChosenByUser: Bool?
    /// Pfad der exportierten Datei relativ zum Wissensordner, sobald exportiert.
    var vaultFile: String?
    /// Ende des Meetings. Nur bei zusammengeführten Meetings gesetzt (Pausen zwischen den
    /// Teilen); sonst gilt Beginn plus Dauer.
    var endedAt: Date?
    /// Transkript wurde nach der Zusammenfassung gekürzt; „Neu erstellen“ setzt es zurück.
    var summaryOutdated: Bool?

    /// Wann das Meeting endete.
    var endDate: Date { endedAt ?? startedAt.addingTimeInterval(duration) }

    enum NameSource: String, Codable {
        /// Stimme passte zu einem gespeicherten Profil.
        case profile
        /// Name kam aus der Teilnehmerliste der Meeting-App (aktiver Sprecher).
        case meetingApp
        /// Vom Nutzer vergeben oder bestätigt; daraus ist ein Profil entstanden.
        case confirmed
        /// Von Hand an einzelne Beiträge vergeben, ohne Stimmprofil.
        case manual
    }

    init(startedAt: Date, duration: TimeInterval, sourceNames: [String], lines: [TranscriptLine],
         summary: String?, notes: [String], speakerNames: [String: String] = [:],
         nameSources: [String: NameSource] = [:], diarizedTrack: String = MeetingArchive.othersTrackFile) {
        self.startedAt = startedAt
        self.duration = duration
        self.sourceNames = sourceNames
        self.lines = lines
        self.summary = summary
        self.notes = notes
        self.speakerNames = speakerNames
        self.nameSources = nameSources
        self.diarizedTrack = diarizedTrack
    }

    /// Sprecher-IDs der Gegenseite in Reihenfolge des ersten Auftretens.
    var speakerIDs: [String] {
        var seen = Set<String>()
        return lines.compactMap(\.speakerID).filter { seen.insert($0).inserted }
    }

    /// Sprecher, deren Name noch nicht bestätigt ist: unbenannt oder nur aus der Meeting-App.
    var unconfirmedSpeakerIDs: [String] {
        speakerIDs.filter { ![.confirmed, .profile, .manual].contains(nameSources[$0]) }
    }

    /// Anzeigename je Beitrag: „Ich", ein Name, „Sprecher N" oder „Andere".
    func label(for line: TranscriptLine) -> String {
        guard line.speaker == .others else { return TranscriptLine.Speaker.me.rawValue }
        guard let id = line.speakerID else { return TranscriptLine.Speaker.others.rawValue }
        return label(forSpeaker: id)
    }

    func label(forSpeaker id: String) -> String {
        if let name = speakerNames[id], !name.isEmpty {
            return SpeakerNaming.isSelf(name) ? TranscriptLine.Speaker.me.rawValue : name
        }
        let unnamed = speakerIDs.filter { (speakerNames[$0] ?? "").isEmpty }
        let number = (unnamed.firstIndex(of: id) ?? unnamed.count) + 1
        return "Sprecher \(number)"
    }

    /// Gesprächsverlauf als Text für die Zusammenfassung.
    var transcriptText: String {
        lines.map { "[\(MeetingMarkdown.clock($0.start, alwaysHours: true))] \(label(for: $0)): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Gesprochene Sekunden je Sprecher, für die Anzeige der Teilnehmenden.
    func speakingTime(of id: String) -> TimeInterval {
        lines.filter { $0.speakerID == id }.reduce(0) { $0 + ($1.end - $1.start) }
    }
}

/// Rendert ein Protokoll als Markdown.
enum MeetingMarkdown {

    static func render(_ document: MeetingDocument) -> String {
        var out: [String] = []
        out.append("# \(title(for: document))")
        out.append("")
        out.append("- Beginn: \(dateFormatter.string(from: document.startedAt)) Uhr")
        out.append("- Ende: \(dateFormatter.string(from: document.endDate)) Uhr")
        out.append("- Dauer: \(clock(document.duration, alwaysHours: false))")
        if !document.sourceNames.isEmpty {
            out.append("- Quelle: \(document.sourceNames.joined(separator: ", "))")
        }
        let people = ["Ich"] + document.speakerIDs.map { document.label(forSpeaker: $0) }
        if document.lines.contains(where: { $0.speaker == .others }) || document.speakerIDs.count > 0 {
            out.append("- Teilnehmende: \(people.joined(separator: ", "))")
        }
        for note in document.notes { out.append("- Hinweis: \(note)") }
        out.append("")

        out.append("## Protokoll")
        out.append("")
        out.append(timeLine(for: document))
        out.append("")
        out.append(document.summary ?? "_Keine Zusammenfassung vorhanden._")
        out.append("")

        if let notes = document.userNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append("## Meine Notizen")
            out.append("")
            out.append(notes)
            out.append("")
        }

        out.append("## Transkript")
        out.append("")
        if document.lines.isEmpty {
            out.append("_Es wurde keine Sprache erkannt._")
        }
        for line in document.lines {
            out.append("**[\(clock(line.start, alwaysHours: true))] \(document.label(for: line)):** \(line.text)")
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// Titel, wie er überall erscheint: „TT.MM.JJ_hh:mm_Titel“ — in der Liste, im Kopf des
    /// Meetings, im Protokoll und im Wissensordner. Datum und Uhrzeit vorn, damit immer klar
    /// ist, von wann ein Meeting stammt.
    static func title(for document: MeetingDocument) -> String {
        stamp(document.startedAt, timeSeparator: ":") + "_" + baseTitle(for: document)
    }

    /// Titel ohne Zeitstempel: KI-Titel oder eigener Titel, sonst „Quelle-Meeting“.
    /// Das Datum steht hier bewusst nicht, es kommt über `title(for:)` vorn dazu.
    static func baseTitle(for document: MeetingDocument) -> String {
        if let ai = document.aiTitle, !ai.isEmpty { return ai }
        guard let source = document.sourceNames.first else { return "Meeting" }
        return source == "Import" ? "Import" : "\(source)-Meeting"
    }

    /// „17.11.26_21:43“ in Berliner Zeit; im Dateinamen mit Punkt statt Doppelpunkt.
    static func stamp(_ date: Date, timeSeparator: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.dateFormat = "dd.MM.yy'_'HH'\(timeSeparator)'mm"
        return f.string(from: date)
    }

    /// `01:02:03` bzw. `2:03` für kurze Dauern.
    static func clock(_ seconds: TimeInterval, alwaysHours: Bool) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if alwaysHours || h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// „Zeit: 18.11.2026, 08:30 bis 09:12 Uhr“, über Mitternacht mit beiden Daten.
    /// Steht über jeder Zusammenfassung, damit Beginn und Ende überall mitgehen.
    static func timeLine(for document: MeetingDocument) -> String {
        let day = formatter("dd.MM.yyyy"), time = formatter("HH:mm")
        let start = document.startedAt, end = document.endDate
        let sameDay = day.string(from: start) == day.string(from: end)
        let to = sameDay ? time.string(from: end) : day.string(from: end) + ", " + time.string(from: end)
        return "Zeit: \(day.string(from: start)), \(time.string(from: start)) bis \(to) Uhr"
    }

    /// Zusammenfassung mit der Zeitzeile davor, etwa zum Kopieren.
    static func summaryWithTime(_ document: MeetingDocument) -> String {
        timeLine(for: document) + "\n\n" + (document.summary ?? "")
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.dateFormat = format
        return f
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.dateFormat = "dd.MM.yyyy, HH:mm"
        return f
    }()

}

/// Ablage unter `~/Documents/BlitzText Meetings/<Datum Uhrzeit Quelle>/`.
///
/// Die Audiospuren werden direkt nach dem Stopp hierher verschoben, noch vor der
/// Transkription. Grund: BlitzText räumt `blitztext-*` im Temp-Ordner beim Beenden
/// auf. Wird die App während der Verarbeitung beendet, bliebe sonst nichts übrig.
struct MeetingArchive {
    let root: URL

    static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlitzText Meetings", isDirectory: true)
    }

    init(root: URL = MeetingArchive.defaultRoot) {
        self.root = root
    }

    static func folderName(startedAt: Date, sourceName: String?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "yyyy-MM-dd HH-mm"
        let stamp = f.string(from: startedAt)
        guard let sourceName, !sourceName.isEmpty else { return stamp }
        let safe = sourceName.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "-")
        return "\(stamp) \(safe)"
    }

    /// Legt einen freien Ordner an; bei Namensgleichheit mit Zählersuffix.
    func makeFolder(startedAt: Date, sourceName: String?) throws -> URL {
        let fm = FileManager.default
        let base = Self.folderName(startedAt: startedAt, sourceName: sourceName)
        var folder = root.appendingPathComponent(base, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: folder.path) {
            folder = root.appendingPathComponent("\(base) (\(suffix))", isDirectory: true)
            suffix += 1
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Legt den Meeting-Ordner an und verschiebt die Spuren hinein.
    func store(_ recording: MeetingRecording) throws -> (folder: URL, microphone: URL?, systemAudio: URL?) {
        let fm = FileManager.default
        let folder = try makeFolder(startedAt: recording.startedAt, sourceName: recording.sources.first?.displayName)

        func move(_ url: URL?, as name: String) throws -> URL? {
            guard let url else { return nil }
            let target = folder.appendingPathComponent(name)
            try fm.moveItem(at: url, to: target)
            return target
        }
        let mic = try move(recording.microphoneTrack, as: Self.microphoneTrackFile)
        let system = try move(recording.systemAudioTrack, as: Self.othersTrackFile)
        return (folder, mic, system)
    }

    /// Schreibt `meeting.json` und daraus `protokoll.md`. Liefert die Markdown-Datei.
    @discardableResult
    func writeProtocol(_ document: MeetingDocument, in folder: URL) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: folder.appendingPathComponent(Self.documentFile), options: .atomic)

        let url = folder.appendingPathComponent(Self.protocolFile)
        try MeetingMarkdown.render(document).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static let documentFile = "meeting.json"
    static let protocolFile = "protokoll.md"
    static let othersTrackFile = "gegenseite.wav"
    static let microphoneTrackFile = "mikrofon.wav"
    /// Importierte Mischspur mit allen Stimmen.
    static let mixedTrackFile = "aufnahme.wav"

    /// Legt einen Ordner für einen Import an und wandelt die Dateien nach 16 kHz mono.
    func storeImport(_ plan: MeetingImport.Plan, startedAt: Date, label: String)
        throws -> (folder: URL, microphone: URL?, others: URL, duration: TimeInterval) {
        let folder = try makeFolder(startedAt: startedAt, sourceName: label)
        let othersName = plan.isMixed ? Self.mixedTrackFile : Self.othersTrackFile
        let others = folder.appendingPathComponent(othersName)
        let duration = try MeetingImport.convert(plan.others, to: others)
        var microphone: URL?
        if let source = plan.microphone {
            let target = folder.appendingPathComponent(Self.microphoneTrackFile)
            try MeetingImport.convert(source, to: target)
            microphone = target
        }
        return (folder, microphone, others, duration)
    }

    func load(folder: URL) -> MeetingDocument? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.documentFile)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MeetingDocument.self, from: data)
    }

    /// Alle Meetings im Archiv, neuestes zuerst.
    func loadAll() -> [(folder: URL, document: MeetingDocument)] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return folders
            .compactMap { folder in load(folder: folder).map { (folder, $0) } }
            .sorted { $0.document.startedAt > $1.document.startedAt }
    }
}
