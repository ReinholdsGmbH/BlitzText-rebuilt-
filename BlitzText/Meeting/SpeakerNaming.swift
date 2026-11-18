import Foundation

/// Namensvergabe ohne Dubletten.
///
/// Zwei Fehlerquellen fängt das ab: Die Sprechertrennung zerlegt eine Person manchmal in
/// zwei Stimmen („Sprecher 1“ und „Sprecher 3“), und beim Tippen entstehen Varianten
/// („anna mueller“ statt „Anna Müller“). Beides würde sonst eine Person doppelt führen,
/// im Meeting und im Profilspeicher.
enum SpeakerNaming {

    /// Name des eigenen Stimmprofils (Einstellungen › Sprecher). Eine Stimme mit diesem Namen
    /// erscheint überall als „Ich“, auch in importierten Mischspuren ohne eigene Mikrofonspur.
    nonisolated(unsafe) static var selfName: String?

    static func isSelf(_ name: String?) -> Bool {
        guard let name, let me = selfName, !me.isEmpty else { return false }
        return key(name) == key(me)
    }

    /// Vergleichsform: ohne Groß-/Kleinschreibung, Akzente, Umlaut-Schreibweisen und
    /// doppelte Leerzeichen. „Müller“ und „Mueller“ gelten als gleich.
    static func key(_ name: String) -> String {
        let folded = name
            .lowercased()
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Übernimmt die Schreibweise eines vorhandenen Namens, wenn der getippte ihm entspricht.
    static func canonical(_ typed: String, known: [String]) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = key(trimmed)
        return known.first { key($0) == wanted } ?? trimmed
    }

    /// Vorschläge beim Tippen, wie bei MacWhisper. Leere Eingabe zeigt alle bekannten
    /// Namen. Treffer am Wortanfang kommen vor Treffern mitten im Wort.
    static func suggestions(for typed: String, known: [String], limit: Int = 6) -> [String] {
        var seen = Set<String>()
        let unique = known.filter { !$0.isEmpty && seen.insert(key($0)).inserted }
        let needle = key(typed)
        guard !needle.isEmpty else { return Array(unique.sorted { key($0) < key($1) }.prefix(limit)) }

        func rank(_ name: String) -> Int? {
            let candidate = key(name)
            if candidate == needle { return 0 }
            if candidate.hasPrefix(needle) { return 1 }
            if candidate.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 2 }
            if candidate.contains(needle) { return 3 }
            return nil
        }
        return Array(unique
            .compactMap { name in rank(name).map { (name, $0) } }
            .sorted { $0.1 == $1.1 ? key($0.0) < key($1.0) : $0.1 < $1.1 }
            .map(\.0)
            .prefix(limit))
    }
}

extension MeetingDocument {

    /// Vergibt einen Namen an eine Stimme. Trägt im selben Meeting schon eine andere Stimme
    /// diesen Namen, werden beide zu einer zusammengeführt: Alle Beiträge wandern auf die
    /// zuerst benannte Stimme, aufeinanderfolgende Beiträge werden wieder zu Absätzen.
    func assigning(name: String, to speakerID: String, source: NameSource) -> MeetingDocument {
        var document = self
        let wanted = SpeakerNaming.key(name)
        let twin = speakerIDs.first { $0 != speakerID && SpeakerNaming.key(speakerNames[$0] ?? "") == wanted }

        guard let target = twin else {
            document.speakerNames[speakerID] = name
            document.nameSources[speakerID] = source
            return document
        }

        document.lines = TranscriptMerger.merge(lines.map { line in
            guard line.speakerID == speakerID else { return line }
            var moved = line
            moved.speakerID = target
            return moved
        })
        document.speakerNames[speakerID] = nil
        document.nameSources[speakerID] = nil
        // Die stärkere Herkunft gewinnt: bestätigt oder Profil schlägt Meeting-App.
        if source == .confirmed || document.nameSources[target] == nil {
            document.nameSources[target] = source == .meetingApp ? (document.nameSources[target] ?? source) : source
        }
        return document
    }

    /// Ob ein Beitrag einer anderen Person zugeordnet werden darf. Bei eigenen Mitschnitten
    /// kommen „Ich“-Beiträge immer aus dem Mikrofon und die übrigen immer aus der
    /// Gegenseite. Ein Umhängen über diese Grenze würde Text und Tonspur auseinanderreißen.
    /// Bei Mischspuren gibt es nur eine Spur, dort ist alles frei.
    func canReassign(_ line: TranscriptLine) -> Bool {
        line.speaker == .others
    }

    /// Hängt einen einzelnen Beitrag an eine andere Stimme dieses Meetings.
    func reassigning(lineAt index: Int, toSpeaker target: String) -> MeetingDocument {
        guard lines.indices.contains(index), canReassign(lines[index]) else { return self }
        var document = self
        document.lines[index].speakerID = target
        document.lines = TranscriptMerger.merge(document.lines, echoSimilarity: 2)
        return document
    }

    /// Hängt einen einzelnen Beitrag an eine Person mit Namen. Gibt es im Meeting schon eine
    /// Stimme mit diesem Namen, landet der Beitrag dort; sonst entsteht eine neue Person,
    /// von Hand benannt und ohne Stimmprofil.
    func reassigning(lineAt index: Int, toName name: String) -> MeetingDocument {
        let wanted = SpeakerNaming.key(name)
        if let existing = speakerIDs.first(where: { SpeakerNaming.key(speakerNames[$0] ?? "") == wanted }) {
            return reassigning(lineAt: index, toSpeaker: existing)
        }
        var document = self
        let id = "hand-" + UUID().uuidString.prefix(8)
        document.speakerNames[id] = name
        document.nameSources[id] = .manual
        return document.reassigning(lineAt: index, toSpeaker: id)
    }
}
