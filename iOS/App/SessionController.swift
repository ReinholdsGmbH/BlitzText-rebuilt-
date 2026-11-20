import AVFoundation
import UIKit

/// Die "Session": Audio-Engine läuft durchgehend (orange Punkt an), damit die App im
/// Hintergrund lebt und die Tastatur Start/Stopp ohne App-Wechsel auslösen kann.
/// Dieselbe Engine nimmt auch Meetings auf.
@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var state: Blitz.State = .off
    @Published private(set) var log: [String] = []
    @Published private(set) var batteryAtStart: Float?
    @Published private(set) var sessionStart: Date?
    @Published private(set) var appGroupOK = Blitz.defaults != nil
    @Published private(set) var modelStatus = "nicht geladen"
    @Published private(set) var activeMeetingID: UUID?
    /// Beginn des laufenden Aufnahmeteils (für die Uhr; bei „Fortsetzen“ ab dem neuen Teil).
    @Published private(set) var meetingRecordingSince: Date?

    /// Diktat nach den Regeln zusätzlich mit Apple Intelligence formatieren (Listen, Absätze).
    @Published var aiFormatting: Bool = UserDefaults.standard.object(forKey: "aiFormatting") as? Bool ?? true {
        didSet { UserDefaults.standard.set(aiFormatting, forKey: "aiFormatting") }
    }

    /// Auto-Stop nach so viel Leerlauf in Minuten; 0 = aus. Standard 5 min wie bei Wispr.
    @Published var idleLimitMinutes: Int = UserDefaults.standard.object(forKey: "idleLimitMinutes") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(idleLimitMinutes, forKey: "idleLimitMinutes") }
    }

    let history: DictationHistory
    let meetings: MeetingStore
    let sharedFolder: SharedFolder
    private let parakeet = ParakeetEngine()
    private lazy var processor = MeetingProcessor(store: meetings, history: history, parakeet: parakeet,
                                                  sharedFolder: sharedFolder) { [weak self] in
        self?.add($0)
    }

    private let engine = AVAudioEngine()
    private let meter = LevelMeter()
    private var inputFormat: AVAudioFormat?
    private let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("diktat.caf")
    private var heartbeat: Timer?
    private var lastActivity = Date()
    private var observers: [DarwinObserver] = []

    init(history: DictationHistory, meetings: MeetingStore, sharedFolder: SharedFolder) {
        self.history = history
        self.meetings = meetings
        self.sharedFolder = sharedFolder
        UIDevice.current.isBatteryMonitoringEnabled = true
        observers = [
            DarwinObserver(Blitz.Note.start) { [weak self] in self?.startRecording() },
            DarwinObserver(Blitz.Note.stop) { [weak self] in self?.stopRecording() },
        ]
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(raw) }
        }
        // Mikrofon gewechselt (CarPlay, AirPods, Kabel): iOS hält die Engine dann still an.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in self?.restartEngine(reason: "Audiogerät gewechselt") }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated { [weak self] in self?.logRouteChange(raw) }
        }
        publishState()
    }

    var batteryNow: Float { UIDevice.current.batteryLevel }

    func handle(url: URL) {
        add("URL geöffnet: \(url.absoluteString)")
        startSession()
        if url.query?.contains("record=1") == true { startRecording() }
    }

    // MARK: - Session

    func startSession() {
        guard state == .off else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            try configureEngine()
        } catch {
            add("Session-Start fehlgeschlagen: \(error.localizedDescription)")
            engine.inputNode.removeTap(onBus: 0)
            return
        }
        sessionStart = Date()
        batteryAtStart = batteryNow
        lastActivity = Date()
        lastBatteryLog = Date()
        state = .idle
        add("Session gestartet, Akku \(percent(batteryNow))")
        preloadModel()
        if aiFormatting { DictationAI.prewarm() }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        publishState()
    }

    /// Tap im aktuellen Format des Mikrofons anlegen und Engine starten. Auch nach Gerätewechsel.
    private func configureEngine() throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "BlitzText", code: 1, userInfo: [NSLocalizedDescriptionKey: "kein Mikrofon verfügbar"])
        }
        inputFormat = format
        // Der Tap läuft im Audio-Thread. Closure darf nicht MainActor-isoliert sein,
        // sonst bricht Swift 6 zur Laufzeit ab (dispatch_assert_queue).
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.makeTap(meter))
        engine.prepare()
        try engine.start()
    }

    /// Nach Gerätewechsel oder Unterbrechung: Engine mit dem jetzt aktiven Mikrofon neu aufbauen.
    /// Eine laufende Aufnahme schreibt weiter in dieselbe Datei (der LevelMeter rechnet um).
    @discardableResult
    private func restartEngine(reason: String) -> Bool {
        guard state != .off else { return false }
        engine.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try configureEngine()
            let name = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "?"
            let rate = inputFormat.map { String(format: "%.0f Hz", $0.sampleRate) } ?? "?"
            add("\(reason): Engine neu gestartet, Mikrofon \(name), \(rate)")
            return true
        } catch {
            add("\(reason): Neustart fehlgeschlagen (\(error.localizedDescription))")
            return false
        }
    }

    private func logRouteChange(_ raw: UInt?) {
        guard let raw, let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        let input = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "kein Eingang"
        let text = switch reason {
        case .newDeviceAvailable: "neues Gerät"
        case .oldDeviceUnavailable: "Gerät getrennt"
        case .categoryChange: "Kategorie geändert"
        case .override: "Umleitung"
        default: "Grund \(raw)"
        }
        add("Audioweg geändert (\(text)), Eingang: \(input)")
        // Nicht jeder Wechsel löst eine Konfigurationsänderung aus; steht die Engine, neu starten.
        if state != .off, !engine.isRunning { restartEngine(reason: "Audioweg geändert") }
    }

    /// Läuft die Engine nicht (etwa nach unbemerktem Gerätewechsel), vor der Aufnahme neu starten.
    private func ensureEngineRunning() -> Bool {
        engine.isRunning || restartEngine(reason: "Engine stand vor der Aufnahme")
    }

    nonisolated private static func makeTap(_ meter: LevelMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in meter.process(buffer) }
    }

    func endSession(reason: String) {
        guard state != .off else { return }
        if state == .meeting { stopMeeting() }
        heartbeat?.invalidate()
        heartbeat = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .off
        add("Session beendet (\(reason)), Akku \(percent(batteryNow))")
        publishState()
    }

    // MARK: - Diktat

    private func startRecording() {
        guard state == .idle else {
            add("Start ignoriert, Zustand \(state.rawValue)")
            return
        }
        guard ensureEngineRunning(), let inputFormat else {
            publishResult("[Mikrofon nicht verfügbar, Session in der App neu starten] ")
            return
        }
        do {
            try meter.begin(writingTo: recordingURL, format: inputFormat)
        } catch {
            add("Aufnahmedatei nicht anlegbar: \(error.localizedDescription)")
            return
        }
        state = .recording
        lastActivity = Date()
        add("Aufnahme läuft")
        publishState()
    }

    private func stopRecording() {
        guard state == .recording else { return }
        let (seconds, peak) = meter.end()
        state = .processing
        lastActivity = Date()
        publishState()
        let db = peak > 0 ? 20 * log10(peak) : -160
        add(String(format: "Aufnahme fertig: %.1f s, Spitze %.0f dB", seconds, db))
        Task { await transcribeRecording(seconds: seconds) }
    }

    /// Unter 0,3 s nimmt Parakeet nichts an. Kurzer Tipper: nichts einfügen; gar kein Ton: Hinweis.
    private static let minimumSeconds = 0.3

    private func transcribeRecording(seconds: Double) async {
        guard seconds >= Self.minimumSeconds else {
            add(seconds == 0 ? "Kein Ton aufgenommen" : "Aufnahme zu kurz, verworfen")
            try? FileManager.default.removeItem(at: recordingURL)
            if state == .processing { state = .idle }
            publishResult(seconds == 0 ? "[Kein Ton aufgenommen, Mikrofon prüfen] " : "")
            return
        }
        let background = UIApplication.shared.applicationState != .active
        let started = Date()
        let text: String
        do {
            let transcript = try await parakeet.transcribe(recordingURL)
            let asrSeconds = Date().timeIntervalSince(started)
            // Regeln (Satzzeichen, Emojis, Listen), danach optional Apple Intelligence.
            var raw = DictationFormatter.apply(transcript)
            if aiFormatting {
                let aiStarted = Date()
                if let formatted = await DictationAI.format(raw) {
                    raw = DictationFormatter.fixListStart(formatted)
                    add(String(format: "KI-Formatierung übernommen (%.1f s)", Date().timeIntervalSince(aiStarted)))
                } else if DictationAI.isAvailable, raw.split(separator: " ").count >= DictationAI.minimumWords {
                    add(String(format: "KI-Formatierung verworfen oder zu langsam (%.1f s)", Date().timeIntervalSince(aiStarted)))
                }
            }
            // Listen beginnen mit einem Umbruch, sonst klebt der erste Punkt am Text davor.
            text = raw.isEmpty ? "" : raw + (raw.contains("\n") ? "\n" : " ")
            if !raw.isEmpty { history.add(text: raw, seconds: seconds) }
            add(String(format: "Parakeet: %.1f s für %.1f s Audio (%@), %d Zeichen",
                       asrSeconds, seconds,
                       background ? "Hintergrund" : "Vordergrund", raw.count))
        } catch {
            text = "[Fehler: \(error.localizedDescription)] "
            add("Parakeet-Fehler (\(background ? "Hintergrund" : "Vordergrund")): \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: recordingURL)
        if state == .processing { state = .idle }
        publishResult(text)
    }

    /// Ergebnis an die Tastatur geben (auch Hinweise statt Text).
    private func publishResult(_ text: String) {
        Blitz.defaults?.set(text, forKey: Blitz.Key.result)
        Blitz.defaults?.set(UUID().uuidString, forKey: Blitz.Key.resultID)
        lastActivity = Date()
        publishState()
        Blitz.post(Blitz.Note.resultReady)
    }

    // MARK: - Meeting

    func startMeeting() {
        if state == .off { startSession() }
        guard state == .idle, ensureEngineRunning(), let inputFormat else {
            add("Meeting-Start nicht möglich, Zustand \(state.rawValue)")
            return
        }
        let meeting = meetings.create()
        beginMeetingPart(meeting.id, part: 1, format: inputFormat)
    }

    /// Nimmt ein beendetes Meeting wieder auf; der neue Teil wird bei der Verarbeitung angehängt.
    func resumeMeeting(_ id: UUID) {
        if state == .off { startSession() }
        guard state == .idle, ensureEngineRunning(), let inputFormat, let meeting = meetings.meeting(id), !meeting.status.isBusy else {
            add("Fortsetzen nicht möglich, Zustand \(state.rawValue)")
            return
        }
        let part = meeting.partCount + 1
        meetings.update(id) { $0.parts = part; $0.status = .recording }
        beginMeetingPart(id, part: part, format: inputFormat)
    }

    private func beginMeetingPart(_ id: UUID, part: Int, format: AVAudioFormat) {
        // AAC statt PCM: eine Stunde sind so rund 30 MB statt fast 700 MB.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 64_000,
        ]
        do {
            try meter.begin(writingTo: meetings.audioURL(for: id, part: part), format: format, fileSettings: settings)
        } catch {
            meetings.update(id) { $0.status = .failed("Aufnahme nicht möglich"); $0.end = $0.end ?? Date() }
            add("Meeting-Aufnahme nicht anlegbar: \(error.localizedDescription)")
            return
        }
        activeMeetingID = id
        meetingRecordingSince = Date()
        state = .meeting
        add(part == 1 ? "Meeting-Aufnahme läuft" : "Meeting fortgesetzt (Teil \(part))")
        publishState()
    }

    func stopMeeting() {
        guard state == .meeting, let id = activeMeetingID else { return }
        let (seconds, _) = meter.end()
        activeMeetingID = nil
        meetingRecordingSince = nil
        state = .idle
        lastActivity = Date()
        publishState()
        meetings.update(id) { $0.end = Date(); $0.status = .transcribing }
        add(String(format: "Meeting beendet: %.0f s Audio", seconds))
        Task { await processor.process(id) }
    }

    /// Meeting von Hand in die gemeinsame Ablage legen.
    func share(_ id: UUID) async {
        await sharedFolder.deliver(id, store: meetings) { [weak self] in self?.add($0) }
    }

    func reprocess(_ id: UUID) {
        Task { await processor.process(id) }
    }

    // MARK: - Modell, Takt, Unterbrechungen

    private func preloadModel() {
        modelStatus = "lädt …"
        let started = Date()
        Task {
            do {
                _ = try await parakeet.load()
                let secs = Date().timeIntervalSince(started)
                modelStatus = String(format: "bereit (%.1f s)", secs)
                add(String(format: "Parakeet-Modell geladen in %.1f s", secs))
            } catch {
                modelStatus = "Fehler"
                add("Parakeet-Modell nicht ladbar: \(error.localizedDescription)")
            }
        }
    }

    /// Alle 10 min Akkustand ins Protokoll, mit Hinweis, ob das Kabel steckt.
    private let batteryLogInterval: TimeInterval = 10 * 60
    private var lastBatteryLog = Date()

    private func logBatteryIfDue() {
        guard let start = sessionStart, Date().timeIntervalSince(lastBatteryLog) >= batteryLogInterval else { return }
        lastBatteryLog = Date()
        let minutes = Int(Date().timeIntervalSince(start) / 60)
        let plugged = UIDevice.current.batteryState == .unplugged ? "ohne Kabel" : "am Kabel"
        let startText = batteryAtStart.map(percent) ?? "?"
        add("Akku nach \(minutes) min: \(percent(batteryNow)) (Start \(startText), \(plugged))")
    }

    private func tick() {
        publishState()
        logBatteryIfDue()
        guard idleLimitMinutes > 0 else { return }
        if state == .idle, Date().timeIntervalSince(lastActivity) > TimeInterval(idleLimitMinutes * 60) {
            endSession(reason: "Auto-Stop nach \(idleLimitMinutes) min")
        }
    }

    private func handleInterruption(_ raw: UInt?) {
        guard let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            add("Unterbrechung begonnen")
        case .ended:
            if !restartEngine(reason: "Unterbrechung beendet") {
                endSession(reason: "Neustart nach Unterbrechung fehlgeschlagen")
            }
        @unknown default:
            break
        }
    }

    private func publishState() {
        guard let defaults = Blitz.defaults else { return }
        defaults.set(state.rawValue, forKey: Blitz.Key.state)
        defaults.set(state == .off ? 0 : Date().timeIntervalSince1970, forKey: Blitz.Key.heartbeat)
    }

    private func add(_ line: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        log.insert("\(time)  \(line)", at: 0)
    }

    private func percent(_ level: Float) -> String {
        level < 0 ? "unbekannt" : "\(Int(level * 100)) %"
    }
}
