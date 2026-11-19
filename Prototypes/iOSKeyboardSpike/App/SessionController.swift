import AVFoundation
import UIKit

/// Die "Session": Audio-Engine läuft durchgehend (orange Punkt an), damit die App im
/// Hintergrund lebt und die Tastatur Start/Stopp ohne App-Wechsel auslösen kann.
/// Dieselbe Engine nimmt auch Meetings auf.
@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var state: Spike.State = .off
    @Published private(set) var log: [String] = []
    @Published private(set) var batteryAtStart: Float?
    @Published private(set) var sessionStart: Date?
    @Published private(set) var appGroupOK = Spike.defaults != nil
    @Published private(set) var modelStatus = "nicht geladen"
    @Published private(set) var activeMeetingID: UUID?

    /// Auto-Stop nach so viel Leerlauf in Minuten; 0 = aus. Standard 5 min wie bei Wispr.
    @Published var idleLimitMinutes: Int = UserDefaults.standard.object(forKey: "idleLimitMinutes") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(idleLimitMinutes, forKey: "idleLimitMinutes") }
    }

    let history: DictationHistory
    let meetings: MeetingStore
    private let parakeet = ParakeetEngine()
    private lazy var processor = MeetingProcessor(store: meetings, history: history, parakeet: parakeet) { [weak self] in
        self?.add($0)
    }

    private let engine = AVAudioEngine()
    private let meter = LevelMeter()
    private var inputFormat: AVAudioFormat?
    private let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("diktat.caf")
    private var heartbeat: Timer?
    private var lastActivity = Date()
    private var sampleRate: Double = 48_000
    private var observers: [DarwinObserver] = []

    init(history: DictationHistory, meetings: MeetingStore) {
        self.history = history
        self.meetings = meetings
        UIDevice.current.isBatteryMonitoringEnabled = true
        observers = [
            DarwinObserver(Spike.Note.start) { [weak self] in self?.startRecording() },
            DarwinObserver(Spike.Note.stop) { [weak self] in self?.stopRecording() },
        ]
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(raw) }
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
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            sampleRate = format.sampleRate
            inputFormat = format
            // Der Tap läuft im Audio-Thread. Closure darf nicht MainActor-isoliert sein,
            // sonst bricht Swift 6 zur Laufzeit ab (dispatch_assert_queue).
            input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.makeTap(meter))
            try engine.start()
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
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        publishState()
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
        guard let inputFormat else { return }
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
        let (frames, peak) = meter.end()
        state = .processing
        lastActivity = Date()
        publishState()
        let seconds = Double(frames) / sampleRate
        let db = peak > 0 ? 20 * log10(peak) : -160
        add(String(format: "Aufnahme fertig: %.1f s, Spitze %.0f dB", seconds, db))
        Task { await transcribeRecording(seconds: seconds) }
    }

    private func transcribeRecording(seconds: Double) async {
        let background = UIApplication.shared.applicationState != .active
        let started = Date()
        let text: String
        do {
            let raw = try await parakeet.transcribe(recordingURL)
            text = raw.isEmpty ? "" : raw + " "
            if !raw.isEmpty { history.add(text: raw, seconds: seconds) }
            add(String(format: "Parakeet: %.1f s für %.1f s Audio (%@), %d Zeichen",
                       Date().timeIntervalSince(started), seconds,
                       background ? "Hintergrund" : "Vordergrund", raw.count))
        } catch {
            text = "[Fehler: \(error.localizedDescription)] "
            add("Parakeet-Fehler (\(background ? "Hintergrund" : "Vordergrund")): \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: recordingURL)
        Spike.defaults?.set(text, forKey: Spike.Key.result)
        Spike.defaults?.set(UUID().uuidString, forKey: Spike.Key.resultID)
        if state == .processing { state = .idle }
        lastActivity = Date()
        publishState()
        Spike.post(Spike.Note.resultReady)
    }

    // MARK: - Meeting

    func startMeeting() {
        if state == .off { startSession() }
        guard state == .idle, let inputFormat else {
            add("Meeting-Start nicht möglich, Zustand \(state.rawValue)")
            return
        }
        let meeting = meetings.create()
        // AAC statt PCM: eine Stunde sind so rund 30 MB statt fast 700 MB.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderBitRateKey: 64_000,
        ]
        do {
            try meter.begin(writingTo: meetings.audioURL(for: meeting.id), format: inputFormat, fileSettings: settings)
        } catch {
            meetings.update(meeting.id) { $0.status = .failed("Aufnahme nicht möglich"); $0.end = Date() }
            add("Meeting-Aufnahme nicht anlegbar: \(error.localizedDescription)")
            return
        }
        activeMeetingID = meeting.id
        state = .meeting
        add("Meeting-Aufnahme läuft")
        publishState()
    }

    func stopMeeting() {
        guard state == .meeting, let id = activeMeetingID else { return }
        let (frames, _) = meter.end()
        activeMeetingID = nil
        state = .idle
        lastActivity = Date()
        publishState()
        meetings.update(id) { $0.end = Date(); $0.status = .transcribing }
        add(String(format: "Meeting beendet: %.0f s Audio", Double(frames) / sampleRate))
        Task { await processor.process(id) }
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
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
                add("Unterbrechung beendet, Engine läuft wieder")
            } catch {
                endSession(reason: "Neustart nach Unterbrechung fehlgeschlagen")
            }
        @unknown default:
            break
        }
    }

    private func publishState() {
        guard let defaults = Spike.defaults else { return }
        defaults.set(state.rawValue, forKey: Spike.Key.state)
        defaults.set(state == .off ? 0 : Date().timeIntervalSince1970, forKey: Spike.Key.heartbeat)
    }

    private func add(_ line: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        log.insert("\(time)  \(line)", at: 0)
    }

    private func percent(_ level: Float) -> String {
        level < 0 ? "unbekannt" : "\(Int(level * 100)) %"
    }
}
