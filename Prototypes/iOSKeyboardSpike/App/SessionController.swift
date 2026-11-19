import AVFoundation
import UIKit

/// Pegelmessung im Audio-Thread. Kein MainActor, deshalb eigenes Lock.
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var isRecording = false
    private var frames: Int = 0
    private var peak: Float = 0

    func begin() { lock.withLock { isRecording = true; frames = 0; peak = 0 } }

    func end() -> (frames: Int, peak: Float) {
        lock.withLock { isRecording = false; return (frames, peak) }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var localPeak: Float = 0
        for i in 0..<count { localPeak = max(localPeak, abs(channel[i])) }
        lock.withLock {
            guard isRecording else { return }
            frames += count
            peak = max(peak, localPeak)
        }
    }
}

/// Die "Session": Audio-Engine läuft durchgehend (orange Punkt an), damit die App im
/// Hintergrund lebt und die Tastatur Start/Stopp ohne App-Wechsel auslösen kann.
@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var state: Spike.State = .off
    @Published private(set) var log: [String] = []
    @Published private(set) var batteryAtStart: Float?
    @Published private(set) var sessionStart: Date?
    @Published private(set) var appGroupOK = Spike.defaults != nil

    /// Auto-Stop nach so viel Leerlauf, wie bei Wispr (Standard 5 min).
    let idleLimit: TimeInterval = 5 * 60

    private let engine = AVAudioEngine()
    private let meter = LevelMeter()
    private var heartbeat: Timer?
    private var lastActivity = Date()
    private var sampleRate: Double = 48_000
    private var observers: [DarwinObserver] = []

    init() {
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
        state = .idle
        add("Session gestartet, Akku \(percent(batteryNow))")
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
        heartbeat?.invalidate()
        heartbeat = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .off
        add("Session beendet (\(reason)), Akku \(percent(batteryNow))")
        publishState()
    }

    private func startRecording() {
        guard state == .idle else {
            add("Start ignoriert, Zustand \(state.rawValue)")
            return
        }
        meter.begin()
        state = .recording
        lastActivity = Date()
        add("Aufnahme läuft")
        publishState()
    }

    private func stopRecording() {
        guard state == .recording else { return }
        let (frames, peak) = meter.end()
        state = .idle
        lastActivity = Date()
        let seconds = Double(frames) / sampleRate
        let db = peak > 0 ? 20 * log10(peak) : -160
        let text = String(format: "[Spike %.1f s, Spitze %.0f dB] ", seconds, db)
        Spike.defaults?.set(text, forKey: Spike.Key.result)
        Spike.defaults?.set(UUID().uuidString, forKey: Spike.Key.resultID)
        add("Aufnahme fertig: \(text)")
        publishState()
        Spike.post(Spike.Note.resultReady)
    }

    private func tick() {
        publishState()
        if state == .idle, Date().timeIntervalSince(lastActivity) > idleLimit {
            endSession(reason: "Auto-Stop nach \(Int(idleLimit / 60)) min")
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
