import AppKit
import Combine
import Foundation

/// Steuert den ganzen Meeting-Ablauf: Erkennung, Aufnahme oder Import, Protokoll.
///
/// Erkennung: Alle paar Sekunden wird geprüft, ob eine Konferenz-App gerade das Mikrofon
/// benutzt. Dann erscheint ein Hinweis mit Aufnahme-Knopf. Gestartet wird nur auf Klick.
///
/// Pipeline nach Stopp oder Import:
/// 1. Spuren in den Meeting-Ordner (vor allem anderen, damit nichts verloren geht).
/// 2. Gegenseite (bzw. Mischspur) nach Stimmen trennen, mit gespeicherten Profilen abgleichen.
/// 3. Beide Spuren lokal mit Parakeet transkribieren, Gegenseite entlang der Sprecherwechsel.
/// 4. Namen: bekannte Profile, sonst der Name, den die Meeting-App als Sprecher zeigte.
/// 5. Rohprotokoll schreiben, dann Zusammenfassung ergänzen. Scheitert die, bleibt das Transkript.
@MainActor
final class MeetingController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recording(startedAt: Date)
        case importing
        case diarizing
        case transcribing(done: Int, total: Int)
        case summarizing
        case finished(folder: URL, warning: String?, unnamedSpeakers: Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Konferenz-Apps, die gerade im Gespräch sind (Mikrofon aktiv).
    @Published private(set) var activeSources: [MeetingSource] = []
    /// Hinweis ausgeblendet, bis das erkannte Meeting endet.
    @Published private(set) var noticeDismissed = false
    @Published private(set) var lastFolder: URL?
    /// Notizen zur laufenden Aufnahme; wandern beim Stopp ins Meeting.
    @Published var liveNotes = ""
    /// Vorschau-Transkript während der Aufnahme.
    let live = LiveTranscriber()
    /// Mitschnitt mit kaum Sprache, wohl versehentlich gestartet. Die Pille fragt dann wie
    /// Wispr Flow: „Versehentlich gestartet? Verwerfen / Behalten“.
    @Published private(set) var accidentalFolder: URL?
    /// Die Meeting-App nutzt das Mikrofon nicht mehr: Pille fragt, ob die Aufnahme enden soll.
    @Published private(set) var meetingEndSuggested = false
    private var endWatch = MeetingEndWatch()

    /// Unter dieser Wortzahl gilt ein Mitschnitt als versehentlich.
    static let accidentalWordLimit = 12

    /// Wird nach jedem fertigen Protokoll gerufen (Bibliothek neu laden, Fenster öffnen).
    var onMeetingSaved: ((URL) -> Void)?
    var onOpenLibrary: ((URL?) -> Void)?

    private let recorder: MeetingRecorder
    let archive: MeetingArchive
    private let makeTranscriber: () -> TranscriptionService
    private let makeSummarizer: () -> MeetingSummarizing
    private let diarizer: MeetingDiarizing?
    private let language: () -> String?
    private let makeExporter: () -> VaultExporter?
    private let speakerPoller = ActiveSpeakerPoller()
    private var pollTimer: Timer?
    private var processingTask: Task<Void, Never>?

    /// Pollintervall der Meeting-Erkennung.
    static let pollInterval: TimeInterval = 5

    init(
        recorder: MeetingRecorder,
        archive: MeetingArchive = MeetingArchive(),
        makeTranscriber: @escaping () -> TranscriptionService,
        makeSummarizer: @escaping () -> MeetingSummarizing,
        diarizer: MeetingDiarizing? = nil,
        makeExporter: @escaping () -> VaultExporter? = { nil },
        language: @escaping () -> String?
    ) {
        self.makeExporter = makeExporter
        self.recorder = recorder
        self.archive = archive
        self.makeTranscriber = makeTranscriber
        self.makeSummarizer = makeSummarizer
        self.diarizer = diarizer
        self.language = language
    }

    var microphoneLevel: Float { recorder.microphoneLevel }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isProcessing: Bool {
        switch phase {
        case .importing, .diarizing, .transcribing, .summarizing: return true
        default: return false
        }
    }

    /// Soll der Hinweis „Meeting erkannt" sichtbar sein?
    var showsDetectionNotice: Bool {
        guard !activeSources.isEmpty, !noticeDismissed else { return false }
        switch phase {
        case .idle, .finished, .failed: return true
        default: return false
        }
    }

    // MARK: - Erkennung

    func startMonitoring() {
        guard pollTimer == nil else { return }
        refreshDetection()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshDetection() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshDetection() {
        guard !isRecording else {
            checkMeetingEnd()
            return
        }
        let sources = recorder.activeMeetingSources()
        if sources.isEmpty { noticeDismissed = false }
        if sources.map(\.bundleIdentifier) != activeSources.map(\.bundleIdentifier) {
            Log.write("MeetingController: aktive Quellen \(sources.map(\.displayName))")
        }
        activeSources = sources
    }

    /// Nur für Aufnahmen, die einer erkannten Meeting-App gelten.
    private func checkMeetingEnd() {
        guard !recorder.activeSources.isEmpty else { return }
        let stillActive = !recorder.activeMeetingSources().isEmpty
        let suggest = endWatch.update(appActive: stillActive, at: Date())
        if suggest != meetingEndSuggested {
            meetingEndSuggested = suggest
            if suggest { Log.write("MeetingController: Meeting-App ohne Mikrofon seit \(Int(MeetingEndWatch.grace)) s — schlage Stopp vor") }
        }
    }

    /// „Weiter aufnehmen“: nicht erneut fragen, bis die App wieder aktiv war.
    func keepRecording() {
        endWatch.dismiss()
        meetingEndSuggested = false
    }

    func dismissNotice() {
        noticeDismissed = true
        switch phase {
        case .finished, .failed: phase = .idle
        default: break
        }
    }

    // MARK: - Aufnahme

    func start() {
        guard !isRecording, !isProcessing else { return }
        do {
            liveNotes = ""
            endWatch = MeetingEndWatch()
            meetingEndSuggested = false
            try recorder.start(restrictToDetectedApps: true)
            if case .recording(let startedAt) = recorder.state {
                phase = .recording(startedAt: startedAt)
                speakerPoller.start(pids: recorder.activeSources.map(\.pid), startedAt: startedAt)
                let buffers = recorder.attachLiveBuffers()
                if !buffers.isEmpty {
                    let poller = speakerPoller
                    live.start(tracks: buffers, transcriber: makeTranscriber(),
                               nameForOthers: { poller.recentName() })
                }
            }
            noticeDismissed = true
        } catch {
            phase = .failed("Aufnahme nicht gestartet: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRecording else { return }
        meetingEndSuggested = false
        let hints = speakerPoller.stop()
        live.stop()
        recorder.detachLiveBuffers()
        guard let recording = recorder.stop() else { return }
        process(recording, hints: hints)
    }

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func openLibrary() {
        onOpenLibrary?(lastFolder)
    }

    func openLastMeeting() {
        onOpenLibrary?(lastFolder)
    }

    func revealArchive() {
        let root = archive.root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    // MARK: - Import

    /// Zeigt den Dateidialog und importiert eine Mischspur oder ein Spurpaar.
    func chooseAndImport() {
        guard !isRecording, !isProcessing else { return }
        let panel = NSOpenPanel()
        panel.title = "Aufnahme importieren"
        panel.message = "Eine Mischspur, oder zwei Dateien: Mikrofon und Gegenseite (z. B. mic-audio und app-audio aus MacWhisper)."
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Audio, .mpeg4Movie]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    func importFiles(_ urls: [URL]) {
        guard !isRecording, !isProcessing else { return }
        let plan: MeetingImport.Plan
        do { plan = try MeetingImport.plan(for: urls) } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        phase = .importing
        let archive = self.archive
        Task { [weak self] in
            do {
                let created = (try? plan.others.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let name = plan.others.deletingPathExtension().lastPathComponent
                let result = try await Task.detached(priority: .userInitiated) {
                    try archive.storeImport(plan, startedAt: created, label: "Import")
                }.value
                Log.write("MeetingController: Import \(plan.isMixed ? "Mischspur" : "Spurpaar") — \(String(format: "%.0f", result.duration)) s")
                let document = MeetingDocument(
                    startedAt: created,
                    duration: result.duration,
                    sourceNames: ["Import"],
                    lines: [],
                    summary: nil,
                    notes: ["Importiert aus „\(name)“."],
                    diarizedTrack: plan.isMixed ? MeetingArchive.mixedTrackFile : MeetingArchive.othersTrackFile
                )
                self?.runPipeline(
                    document: document, folder: result.folder,
                    microphone: result.microphone, others: result.others,
                    othersSide: .others, hints: []
                )
            } catch {
                self?.phase = .failed("Import fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Verarbeitung

    private func process(_ recording: MeetingRecording, hints: [SpeakerHint]) {
        let stored: (folder: URL, microphone: URL?, systemAudio: URL?)
        do {
            stored = try archive.store(recording)
        } catch {
            phase = .failed("Spuren nicht gespeichert: \(error.localizedDescription)")
            return
        }

        var notes: [String] = []
        if recording.systemAudioWasSilent {
            notes.append("Die Gegenseite kam stumm an. Meist fehlt die Berechtigung für Systemaudio-Aufnahme.")
        } else if stored.systemAudio == nil {
            notes.append("Die Gegenseite wurde nicht aufgenommen, nur das eigene Mikrofon.")
        }
        if stored.microphone == nil {
            notes.append("Auf dem Mikrofon wurde nichts gesprochen.")
        }

        let document = MeetingDocument(
            startedAt: recording.startedAt,
            duration: recording.duration,
            sourceNames: recording.sources.map(\.displayName),
            lines: [],
            summary: nil,
            notes: notes
        )
        var withNotes = document
        let typed = liveNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        withNotes.userNotes = typed.isEmpty ? nil : liveNotes
        liveNotes = ""
        runPipeline(document: withNotes, folder: stored.folder, microphone: stored.microphone,
                    others: stored.systemAudio, othersSide: .others, hints: hints)
    }

    private func runPipeline(
        document initial: MeetingDocument,
        folder: URL,
        microphone: URL?,
        others: URL?,
        othersSide: TranscriptLine.Speaker,
        hints: [SpeakerHint]
    ) {
        // Sofort umschalten, nicht erst im Hintergrund-Task: sonst zeigt die Oberfläche nach dem
        // Stopp noch kurz „Aufnahme läuft“, und ein neuer Start würde verschluckt.
        phase = (others != nil && diarizer != nil) ? .diarizing : .transcribing(done: 0, total: 0)
        let transcriber = MeetingTranscriber(transcriber: makeTranscriber(), language: language())
        let summarizer = makeSummarizer()
        let diarizer = self.diarizer
        let archive = self.archive
        let exporter = makeExporter()

        let report: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in
                guard let self, self.isProcessing else { return }
                self.phase = .transcribing(done: done, total: total)
            }
        }

        processingTask = Task { [weak self] in
            var document = initial
            do {
                // 2. Stimmen der Gegenseite trennen.
                var othersTrack = others.map { MeetingTranscriber.Track(url: $0, speaker: othersSide) }
                var diarization: MeetingDiarization?
                if let others, let diarizer {
                    self?.phase = .diarizing
                    do {
                        let result = try await diarizer.diarize(track: others)
                        diarization = result
                        othersTrack?.spans = MeetingTranscriber.spans(from: result.segments)
                    } catch {
                        document.notes.append("Sprechertrennung nicht möglich: \(error.localizedDescription)")
                        Log.write("MeetingController: Diarisierung fehlgeschlagen — \(error.localizedDescription)")
                    }
                }

                // 3. Transkribieren.
                self?.phase = .transcribing(done: 0, total: 0)
                var tracks: [MeetingTranscriber.Track] = []
                if let microphone { tracks.append(.init(url: microphone, speaker: .me)) }
                if let othersTrack { tracks.append(othersTrack) }
                let raw = try await transcriber.transcribe(tracks, progress: report)
                document.lines = TranscriptMerger.merge(raw)

                // 4. Namen.
                if let diarization {
                    for (id, name) in diarization.knownNames {
                        document.speakerNames[id] = name
                        document.nameSources[id] = .profile
                    }
                    let suggested = SpeakerNameSuggester.suggest(segments: diarization.segments, hints: hints)
                    let usedNames = Set(document.speakerNames.values)
                    for (id, name) in suggested where document.speakerNames[id] == nil && !usedNames.contains(name) {
                        document.speakerNames[id] = name
                        document.nameSources[id] = .meetingApp
                    }
                }
                try archive.writeProtocol(document, in: folder)
                self?.lastFolder = folder

                guard !document.lines.isEmpty else {
                    self?.finish(folder: folder, warning: "Keine Sprache erkannt.", document: document)
                    return
                }

                // 5. Zusammenfassung.
                self?.phase = .summarizing
                var warning: String?
                do {
                    let split = MeetingSummarizer.splitTitle(try await summarizer.summarize(transcript: document.summaryInput))
                    document.summary = split.notes
                    if let title = split.title { document.aiTitle = title }
                } catch {
                    warning = "Zusammenfassung fehlgeschlagen: \(error.localizedDescription)"
                    Log.write("MeetingController: \(warning ?? "")")
                }
                // 6. Bereich: Stichwörter aus mw-route, sonst schlägt das Modell einen vor.
                if exporter != nil, document.projectChosenByUser != true, document.project == nil {
                    var area = VaultExporter.detectProject(for: document)
                    if area == "eingang", let suggested = await MeetingAreaSuggester.suggest(for: document, using: summarizer) {
                        area = suggested
                        Log.write("MeetingController: Bereich vom Modell vorgeschlagen — \(area)")
                    }
                    document.project = area
                }
                // 7. Speichern und in den Wissensordner spiegeln, auch ohne Zusammenfassung:
                // Das Transkript ist dort schon nützlich, die Notizen kommen bei „Neu erstellen“ nach.
                let saved = archive.persist(document, in: folder, exporter: exporter)
                document = saved.document
                if let exportError = saved.exportError {
                    warning = warning ?? "Nicht im Wissensordner: \(exportError.localizedDescription)"
                    Log.write("MeetingController: Export — \(exportError.localizedDescription)")
                } else if let file = document.vaultFile {
                    Log.write("MeetingController: im Wissensordner unter \(file)")
                }
                self?.finish(folder: folder, warning: warning, document: document)
            } catch {
                self?.phase = .failed("Transkription fehlgeschlagen: \(error.localizedDescription)")
                Log.write("MeetingController: Transkription fehlgeschlagen — \(error.localizedDescription)")
            }
        }
    }

    /// Verwirft den versehentlichen Mitschnitt (Papierkorb) oder behält ihn.
    func resolveAccidental(keep: Bool) {
        guard let folder = accidentalFolder else { return }
        accidentalFolder = nil
        if !keep {
            if let document = archive.load(folder: folder) { makeExporter()?.remove(document) }
            try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            Log.write("MeetingController: versehentlichen Mitschnitt verworfen")
            onMeetingSaved?(folder)
            phase = .idle
        }
    }

    private func finish(folder: URL, warning: String?, document: MeetingDocument) {
        let words = document.lines.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let imported = document.sourceNames == ["Import"]
        accidentalFolder = (!imported && words < Self.accidentalWordLimit) ? folder : nil
        lastFolder = folder
        phase = .finished(folder: folder, warning: warning, unnamedSpeakers: document.unconfirmedSpeakerIDs.count)
        onMeetingSaved?(folder)
        Log.write("MeetingController: Protokoll fertig — \(folder.lastPathComponent), \(document.speakerIDs.count) Sprecher")
    }
}

/// Erkennt das Ende eines Meetings: Die Meeting-App hat das Mikrofon `grace` Sekunden lang
/// nicht mehr offen. Kurze Lücken (Gerätewechsel, Neuverbindung) lösen nichts aus.
struct MeetingEndWatch {
    static let grace: TimeInterval = 15

    private var inactiveSince: Date?
    private var dismissed = false

    /// `true`, solange der Vorschlag zum Beenden gezeigt werden soll.
    mutating func update(appActive: Bool, at now: Date) -> Bool {
        if appActive {
            inactiveSince = nil
            dismissed = false
            return false
        }
        let since = inactiveSince ?? now
        inactiveSince = since
        return !dismissed && now.timeIntervalSince(since) >= Self.grace
    }

    mutating func dismiss() { dismissed = true }
}
