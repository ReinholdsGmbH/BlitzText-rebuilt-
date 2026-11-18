import AVFoundation
import Combine
import FluidAudio
import Foundation

/// Hülle für Audiopuffer auf dem Weg zum Streaming. Jeder Puffer wird in der Aufnahme frisch
/// angelegt und danach nicht mehr verändert; deshalb ist die Weitergabe sicher.
struct AudioBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Sammelt während der Aufnahme die 16-kHz-Samples einer Spur für das Live-Transkript.
/// Abgeholte Samples werden verworfen, damit ein langes Meeting den Speicher nicht füllt.
final class LiveAudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Float] = []
    private var consumed = 0

    /// Streaming-Abnehmer: bekommt jeden Puffer sofort, in Aufnahme-Reihenfolge.
    private var stream: AsyncStream<AudioBufferBox>.Continuation?

    func attachStream(_ continuation: AsyncStream<AudioBufferBox>.Continuation) {
        lock.withLock { stream = continuation }
    }

    func detachStream() {
        lock.withLock { stream?.finish(); stream = nil }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        if let stream = lock.withLock({ stream }) {
            stream.yield(AudioBufferBox(buffer: buffer))
            return
        }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var samples = [Float](repeating: 0, count: count)
        if let floats = buffer.floatChannelData?[0] {
            for i in 0..<count { samples[i] = floats[i] }
        } else if let ints = buffer.int16ChannelData?[0] {
            for i in 0..<count { samples[i] = Float(ints[i]) / 32_768 }
        } else { return }
        lock.withLock { pending += samples }
    }

    /// Alle neuen Samples seit dem letzten Abholen, mit ihrer Startposition in der Spur.
    func take() -> (start: Int, samples: [Float]) {
        lock.withLock {
            let result = (consumed, pending)
            consumed += pending.count
            pending = []
            return result
        }
    }
}

/// Ein Beitrag im Live-Transkript, mit Namen sobald bekannt.
struct LiveLine: Equatable {
    let speaker: TranscriptLine.Speaker
    var name: String?
    let start: TimeInterval
    var text: String

    var label: String {
        if speaker == .me { return TranscriptLine.Speaker.me.rawValue }
        return name ?? TranscriptLine.Speaker.others.rawValue
    }
}

/// Live-Transkript während der Aufnahme, gestreamt wie bei MacWhisper.
///
/// Weg: FluidAudios `SlidingWindowAsrManager` (Parakeet, lokal) je Spur, mit kurzem Fenster
/// (`streamConfig`). Jedes Update enthält den neuen Text eines Fensters und wird sofort an die
/// Sprechblase gehängt; so erscheint Gesprochenes nach rund vier Sekunden. FluidAudios eigene
/// `.streaming`-Einstellung rechnet nur alle 11 s und kennt keine echten Zwischenhypothesen.
/// Namen der Gegenseite kommen aus der Sprecheranzeige der Meeting-App (`nameForOthers`).
///
/// Lädt das Streaming-Modell nicht, fällt es auf Abschnitte alle `interval` Sekunden zurück.
/// Das endgültige Transkript mit Sprechertrennung entsteht in jedem Fall nach dem Stopp.
@MainActor
final class LiveTranscriber: ObservableObject {
    @Published private(set) var lines: [LiveLine] = []
    /// Vorläufige Hypothese je Spur. Bleibt beim kurzen Fenster leer; die Ansicht zeigt sie, falls
    /// ein späteres Streaming-Modell echte Zwischenstände liefert.
    @Published private(set) var volatile: [TranscriptLine.Speaker: String] = [:]
    @Published private(set) var isRunning = false
    @Published private(set) var isStreaming = false

    static let interval: TimeInterval = 10

    /// 2,5 s neues Audio je Fenster, 5 s Rückblick für den Zusammenhang, 1,5 s Vorschau.
    /// Verzögerung bis zur Anzeige also etwa Fenster plus Vorschau plus Rechenzeit.
    static let streamConfig = SlidingWindowAsrConfig(
        chunkSeconds: 2.5,
        hypothesisChunkSeconds: 1.0,
        leftContextSeconds: 5.0,
        rightContextSeconds: 1.5,
        minContextForConfirmation: 0,
        confirmationThreshold: 0
    )
    static let silenceRMS: Float = 0.008
    /// Gleiche Seite mit kürzerer Pause wird an die vorige Blase angehängt.
    static let joinGap: TimeInterval = 4

    private var tracks: [(buffer: LiveAudioBuffer, speaker: TranscriptLine.Speaker)] = []
    private var transcriber: TranscriptionService?
    private var nameForOthers: () -> String? = { nil }
    private var startedAt = Date()
    private var timer: Timer?
    private var working = false
    private var streamTasks: [Task<Void, Never>] = []
    private var lastConfirmed: [TranscriptLine.Speaker: Date] = [:]

    /// Einmal geladenes Modell für alle Streams, damit nicht jede Aufnahme neu lädt.
    nonisolated(unsafe) private static var cachedModels: AsrModels?

    func start(
        tracks: [(LiveAudioBuffer, TranscriptLine.Speaker)],
        transcriber: TranscriptionService,
        nameForOthers: @escaping () -> String? = { nil }
    ) {
        stop()
        self.tracks = tracks.map { (buffer: $0.0, speaker: $0.1) }
        self.transcriber = transcriber
        self.nameForOthers = nameForOthers
        startedAt = Date()
        lines = []
        volatile = [:]
        isRunning = true
        startStreaming()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        streamTasks.forEach { $0.cancel() }
        streamTasks = []
        tracks.forEach { $0.buffer.detachStream() }
        isRunning = false
        isStreaming = false
        tracks = []
    }

    // MARK: Streaming

    private func startStreaming() {
        let tracks = self.tracks
        streamTasks.append(Task { [weak self] in
            do {
                let models: AsrModels
                if let cached = Self.cachedModels { models = cached } else {
                    models = try await AsrModels.downloadAndLoad()
                    Self.cachedModels = models
                }
                for track in tracks {
                    let manager = SlidingWindowAsrManager(config: Self.streamConfig)
                    try await manager.loadModels(models)
                    try await manager.startStreaming(source: track.speaker == .me ? .microphone : .system)
                    let (input, continuation) = AsyncStream<AudioBufferBox>.makeStream(bufferingPolicy: .bufferingNewest(400))
                    track.buffer.attachStream(continuation)
                    self?.runStream(manager: manager, input: input, speaker: track.speaker)
                }
                self?.isStreaming = true
                Log.write("LiveTranscriber: Streaming aktiv (\(tracks.count) Spur(en))")
            } catch {
                Log.write("LiveTranscriber: Streaming nicht verfügbar, Abschnitte alle \(Int(Self.interval)) s — \(error.localizedDescription)")
                self?.startChunkFallback()
            }
        })
    }

    private func runStream(manager: SlidingWindowAsrManager, input: AsyncStream<AudioBufferBox>, speaker: TranscriptLine.Speaker) {
        // Eingang: Puffer in Aufnahme-Reihenfolge an den Manager.
        streamTasks.append(Task {
            for await box in input {
                if Task.isCancelled { break }
                nonisolated(unsafe) let buffer = box.buffer
                await manager.streamAudio(buffer)
            }
            _ = try? await manager.finish()
        })
        // Ausgang: Hypothesen und bestätigter Text.
        streamTasks.append(Task { [weak self] in
            for await update in await manager.transcriptionUpdates {
                if Task.isCancelled { break }
                self?.handle(update.text, speaker: speaker, at: update.timestamp)
            }
        })
    }

    /// Jedes Update ist neuer Text: FluidAudio dedupliziert die Überlappung der Fenster über
    /// die bisherigen Tokens. Das „bestätigt“-Flag sagt nur etwas über die Konfidenz aus.
    private func handle(_ raw: String, speaker: TranscriptLine.Speaker, at time: Date) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isRunning, !text.isEmpty else { return }
        let name = speaker == .others ? nameForOthers() : nil
        let start = max(0, time.timeIntervalSince(startedAt) - Self.streamConfig.chunkSeconds - Self.streamConfig.rightContextSeconds)
        append(LiveLine(speaker: speaker, name: name, start: start, text: text), at: time)
    }

    private func append(_ line: LiveLine, at time: Date) {
        if let index = lines.lastIndex(where: { $0.speaker == line.speaker }),
           index == lines.count - 1,
           lines[index].name == line.name,
           let previous = lastConfirmed[line.speaker], time.timeIntervalSince(previous) <= Self.joinGap + Self.streamConfig.chunkSeconds {
            lines[index].text += " " + line.text
        } else {
            lines.append(line)
        }
        lastConfirmed[line.speaker] = time
    }

    // MARK: Rückfall: Abschnitte

    private func startChunkFallback() {
        isStreaming = false
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard !working, let transcriber, isRunning else { return }
        let chunks = tracks.map { (take: $0.buffer.take(), speaker: $0.speaker) }
        working = true
        Task { [weak self] in
            var fresh: [LiveLine] = []
            for chunk in chunks {
                guard let line = await Self.transcribe(chunk.take.samples, start: chunk.take.start,
                                                       speaker: chunk.speaker, with: transcriber) else { continue }
                fresh.append(LiveLine(speaker: line.speaker, name: line.speaker == .others ? self?.nameForOthers() : nil,
                                      start: line.start, text: line.text))
            }
            guard let self else { return }
            if self.isRunning {
                for line in fresh.sorted(by: { $0.start < $1.start }) {
                    self.append(line, at: self.startedAt.addingTimeInterval(line.start))
                }
            }
            self.working = false
        }
    }

    private static func transcribe(_ samples: [Float], start: Int, speaker: TranscriptLine.Speaker,
                                   with transcriber: TranscriptionService) async -> TranscriptLine? {
        guard samples.count >= 16_000 else { return nil }
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        guard rms >= silenceRMS else { return nil }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-live-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        } catch { return nil }

        guard let text = try? await transcriber.transcribe(audioURL: url, language: nil, prompt: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let begin = TimeInterval(start) / 16_000
        return TranscriptLine(speaker: speaker, start: begin, end: begin + TimeInterval(samples.count) / 16_000, text: text)
    }
}
