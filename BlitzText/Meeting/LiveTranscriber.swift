import AVFoundation
import Combine
import Foundation

/// Sammelt während der Aufnahme die 16-kHz-Samples einer Spur für das Live-Transkript.
/// Abgeholte Samples werden verworfen, damit ein langes Meeting den Speicher nicht füllt.
final class LiveAudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Float] = []
    private var consumed = 0

    func append(_ buffer: AVAudioPCMBuffer) {
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

/// Live-Transkript während der Aufnahme, wie in Wispr Flows Meeting Recorder.
///
/// Alle `interval` Sekunden geht der neue Abschnitt jeder Spur durch Parakeet. Das ist eine
/// Vorschau: Schnitte können Wörter teilen, und es gibt nur „Ich“ und „Andere“. Das
/// endgültige Transkript mit Sprechertrennung entsteht wie bisher nach dem Stopp.
@MainActor
final class LiveTranscriber: ObservableObject {
    @Published private(set) var lines: [TranscriptLine] = []
    @Published private(set) var isRunning = false

    static let interval: TimeInterval = 10
    /// Abschnitte unter diesem Pegel sind Stille und werden übersprungen.
    static let silenceRMS: Float = 0.008

    private var tracks: [(buffer: LiveAudioBuffer, speaker: TranscriptLine.Speaker)] = []
    private var transcriber: TranscriptionService?
    private var timer: Timer?
    private var working = false

    func start(tracks: [(LiveAudioBuffer, TranscriptLine.Speaker)], transcriber: TranscriptionService) {
        stop()
        self.tracks = tracks.map { (buffer: $0.0, speaker: $0.1) }
        self.transcriber = transcriber
        lines = []
        isRunning = true
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        tracks = []
    }

    private func tick() {
        // Läuft der vorige Durchgang noch, die Samples liegen lassen und beim nächsten mitnehmen.
        guard !working, let transcriber, isRunning else { return }
        let chunks = tracks.map { (take: $0.buffer.take(), speaker: $0.speaker) }
        working = true
        Task { [weak self] in
            var fresh: [TranscriptLine] = []
            for chunk in chunks {
                guard let line = await Self.transcribe(chunk.take.samples, start: chunk.take.start,
                                                       speaker: chunk.speaker, with: transcriber) else { continue }
                fresh.append(line)
            }
            guard let self else { return }
            if self.isRunning {
                self.lines = TranscriptMerger.merge(self.lines + fresh, echoSimilarity: 0.6, joinGap: 12)
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
