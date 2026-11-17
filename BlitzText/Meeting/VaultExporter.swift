import Foundation

/// Legt fertige Meetings direkt im Wissensordner (Baalda-Vault) ab, im selben Format und nach
/// denselben Regeln wie `mw-route`: `<Bereich>/transkripte/<Datei>.md` mit Kopfzeile
/// `**Projekt:**`. So ist das Projektwissen sofort nach dem Meeting da und über den
/// Baalda-MCP auch von anderen Rechnern erreichbar, nicht erst, wenn mw-route läuft.
///
/// Wird bei jeder Änderung erneut aufgerufen (Sprecher zuordnen, Beiträge umhängen, Notizen neu
/// erstellen, Bereich wechseln) und überschreibt die Datei, damit im Vault immer die
/// korrigierte Fassung liegt. Die `log.md` des Bereichs bekommt nur beim ersten Export einen
/// Eintrag; sie ist laut Ordnerregel ein reines Anhänge-Protokoll.
struct VaultExporter {
    let root: URL

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Baalda Vaults/Raba IT/Wissen", isDirectory: true)
    }

    // MARK: Regeln aus mw-route (Stand 17.11.2026)

    /// Bereichsschlüssel → Ordner relativ zum Wissensordner.
    static let areas: [(key: String, label: String, folder: String)] = [
        ("pag", "PAG", "arbeit/pag"),
        ("wk", "WK", "arbeit/wk"),
        ("tm", "TenderMatchAI", "arbeit/tendermatchai"),
        ("intern", "Reinholds intern", "arbeit/reinholds"),
        ("kursbar", "Kursbar", "raba-it/kursbar"),
        ("auftragslauf", "Auftragslauf", "raba-it/auftragslauf"),
        ("websites", "Websites", "raba-it/websites"),
        ("rabaconsulting", "Raba Consulting", "raba-consulting"),
        ("thraba", "thraba.de", "thraba-de"),
        ("privat", "Privat", "privat"),
        ("eingang", "Eingang (unsortiert)", "_eingang")
    ]

    /// Stichwörter je Bereich, in der Prüfreihenfolge von mw-route: Spezifisches zuerst, PAG
    /// zuletzt, weil dort breite Begriffe wie „test“ stehen.
    static let keywords: [(key: String, pattern: String)] = [
        ("kursbar", "kursbar"),
        ("auftragslauf", "auftragslauf"),
        ("rabaconsulting", "raba.consulting"),
        ("thraba", "thraba|dia.profile|profile.router"),
        ("tm", "tendermatch|AI.Services|ai-services|TenderMatch|tender.match|checkpoint.*tendermatch"),
        ("wk", "libra|WS0?9|CRM.integration|salesforce|attio|ETL|account.matching|CRM.sync|CRM.workshop|IIB|field.matching|ERP.integration|DE50|sync.*CRM|DACH.region|statusberichterstattung|DAC.pipeline|DAC.e-commerce|business.approval.*pack|steerco.*CRM|closed.one"),
        ("pag", "testplanung|testmanagement|xray|migrationstest|UAT|go.live|go-live|golive|testf(a|ä)ll|teststatus|testvorbereitung|testphase|cutover|abnahmeprozess|kickoff.*test|projektstatus.*test|defect|SAP.*test|mig.*test")
    ]
    /// Interne Dauertermine, die alle Projekte streifen, gehen immer nach „intern“.
    static let internTitles = "thomas.daily|reinholds.daily|reinholds.teamabstimmung|quarterly.review"

    static func folder(for key: String) -> String {
        areas.first { $0.key == key }?.folder ?? "_eingang"
    }

    /// Bereich wie mw-route: Titel gegen interne Termine, dann Zusammenfassung und
    /// Transkriptanfang gegen die Stichwörter. Ohne Treffer: Eingang.
    static func detectProject(title: String, text: String) -> String {
        if matches(internTitles, in: title) { return "intern" }
        for rule in keywords where matches(rule.pattern, in: text) { return rule.key }
        return "eingang"
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Namen

    /// Überschrift „dd.mm.jj_hh:mm_Titel“, wie gewünscht mit Doppelpunkt.
    static func heading(for document: MeetingDocument) -> String {
        MeetingMarkdown.title(for: document)
    }

    /// Dateiname „dd.mm.jj_hh.mm_Titel.md“. Punkt statt Doppelpunkt: Finder zeigt „:“ als „/“,
    /// und Cloud-Ablagen wie OneDrive lehnen ihn ab.
    static func fileName(for document: MeetingDocument) -> String {
        let title = MeetingMarkdown.baseTitle(for: document)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return MeetingMarkdown.stamp(document.startedAt, timeSeparator: ".") + "_" + String(title.prefix(80)) + ".md"
    }

    // MARK: Export

    enum ExportError: LocalizedError {
        case rootMissing(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .rootMissing(let path): return "Wissensordner nicht gefunden: \(path)"
            case .writeFailed(let path): return "Datei im Wissensordner nicht geschrieben: \(path)"
            }
        }
    }

    /// Schreibt bzw. aktualisiert die Datei und liefert das Dokument mit Bereich und Pfad zurück.
    func export(_ input: MeetingDocument) throws -> MeetingDocument {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { throw ExportError.rootMissing(root.path) }

        var document = input
        if document.projectChosenByUser != true || document.project == nil {
            let probe = (document.summary ?? "").prefix(500) + " " + document.transcriptText.prefix(1500)
            document.project = Self.detectProject(title: MeetingMarkdown.baseTitle(for: document), text: String(probe))
        }
        let area = Self.folder(for: document.project ?? "eingang")
        let relative = "\(area)/transkripte/\(Self.fileName(for: document))"
        let target = root.appendingPathComponent(relative)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let content = Self.markdown(for: document, area: area)
        try content.write(to: target, atomically: true, encoding: .utf8)
        // Cloud-Ordner können still scheitern (mw-route: „resource deadlock avoided“).
        let size = (try? fm.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
        guard size > 0 else { throw ExportError.writeFailed(target.path) }

        let firstExport = document.vaultFile == nil
        if let old = document.vaultFile, old != relative {
            try? fm.removeItem(at: root.appendingPathComponent(old))
        }
        if firstExport || document.vaultFile.map({ !$0.hasPrefix(area + "/") }) == true {
            try appendLog(for: document, area: area, relative: relative)
        }
        document.vaultFile = relative
        return document
    }

    /// Nimmt ein verworfenes oder gelöschtes Meeting wieder aus dem Wissensordner: Datei in den
    /// Papierkorb, in der log.md eine Korrekturzeile (sie ist ein reines Anhänge-Protokoll,
    /// deshalb wird die alte Zeile nicht gelöscht).
    func remove(_ document: MeetingDocument) {
        guard let file = document.vaultFile else { return }
        let url = root.appendingPathComponent(file)
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        let area = file.components(separatedBy: "/transkripte/").first ?? "_eingang"
        let log = root.appendingPathComponent("\(area)/log.md")
        let line = "- Meeting \(MeetingMarkdown.title(for: document)) wurde verworfen, die Datei liegt im Papierkorb.\n"
        if let handle = try? FileHandle(forWritingTo: log) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        }
    }

    static func markdown(for document: MeetingDocument, area: String) -> String {
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "de_DE")
        iso.timeZone = TimeZone(identifier: "Europe/Berlin")
        iso.dateFormat = "yyyy-MM-dd"
        let people = (document.lines.contains { $0.speaker == .me } ? ["Ich"] : [])
            + document.speakerIDs.map { document.label(forSpeaker: $0) }
        var out = ["# \(heading(for: document))", ""]
        out.append("**Datum:** \(iso.string(from: document.startedAt))")
        if let ai = document.aiTitle { out.append("**AI-Titel:** \(ai)") }
        out.append("**Projekt:** \((area as NSString).lastPathComponent)")
        out.append("**Quelle:** BlitzText, Dauer \(MeetingMarkdown.clock(document.duration, alwaysHours: false))")
        if !people.isEmpty { out.append("**Teilnehmende:** \(people.joined(separator: ", "))") }
        out.append("")
        if let summary = document.summary {
            out += ["## Zusammenfassung", "", summary, ""]
        }
        if let notes = document.userNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += ["## Meine Notizen", "", notes, ""]
        }
        out += ["## Transkript", ""]
        for line in document.lines {
            out.append("[\(MeetingMarkdown.clock(line.start, alwaysHours: true))] \(document.label(for: line)): \(line.text)")
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// Hängt eine Zeile an `<Bereich>/log.md`: Datum, Titel mit Link, erster Punkt der Notizen.
    private func appendLog(for document: MeetingDocument, area: String, relative: String) throws {
        let log = root.appendingPathComponent("\(area)/log.md")
        let firstPoint = (document.summary ?? "")
            .components(separatedBy: "\n")
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }?
            .trimmingCharacters(in: CharacterSet(charactersIn: "- ").union(.whitespaces)) ?? ""
        let link = String(relative.dropFirst(area.count + 1))
        var entry = "- Meeting [\(MeetingMarkdown.title(for: document))](<\(link)>)"
        if !firstPoint.isEmpty { entry += ": \(firstPoint)" }
        entry += "\n"

        if let handle = try? FileHandle(forWritingTo: log) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            let existing = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            let prefix = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
            handle.write(Data((prefix + entry).utf8))
        } else {
            try entry.write(to: log, atomically: true, encoding: .utf8)
        }
    }
}

extension MeetingArchive {
    /// Speichert das Meeting und spiegelt es, falls eingeschaltet, in den Wissensordner.
    /// Ein Fehler beim Export verhindert das Speichern nicht; er kommt als Hinweis zurück.
    @discardableResult
    func persist(_ document: MeetingDocument, in folder: URL, exporter: VaultExporter?) -> (document: MeetingDocument, exportError: Error?) {
        var current = document
        var exportError: Error?
        if let exporter {
            do { current = try exporter.export(document) } catch { exportError = error }
        }
        do { try writeProtocol(current, in: folder) } catch { exportError = exportError ?? error }
        return (current, exportError)
    }
}
