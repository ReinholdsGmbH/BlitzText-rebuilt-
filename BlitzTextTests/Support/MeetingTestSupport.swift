import AVFoundation
import Foundation
@testable import BlitzText

struct FakeAudioProcessList: AudioProcessListing {
    var list: [AudioProcessInfo] = []
    func processes() -> [AudioProcessInfo] { list }
}

/// Liefert der Reihe nach vorgegebene Texte, danach leere Strings.
final class SequenceTranscriber: TranscriptionService, @unchecked Sendable {
    private var queue: [String]
    private(set) var callCount = 0
    var error: Error?

    init(_ texts: [String]) { queue = texts }

    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String {
        callCount += 1
        if let error { throw error }
        return queue.isEmpty ? "" : queue.removeFirst()
    }
}

struct FakeSummarizer: MeetingSummarizing {
    var result: Result<String, Error>
    var titleResult: Result<String, Error> = .success("Neuer Titel")
    func summarize(transcript: String) async throws -> String { try result.get() }
    func title(for transcript: String) async throws -> String { try titleResult.get() }
    var askResult: Result<String, Error> = .success("Antwort")
    func ask(system: String, user: String) async throws -> String { try askResult.get() }
}

enum TestAudio {
    /// 16-kHz-Mono-WAV: Stille mit Sinus-Abschnitten an den angegebenen Stellen (Sekunden).
    static func wav(duration: TimeInterval, bursts: [ClosedRange<TimeInterval>], at url: URL) throws -> URL {
        let rate = 16_000.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(duration * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let loud = bursts.contains { $0.contains(t) }
            channel[i] = loud ? Float(sin(2 * .pi * 220 * t) * 0.3) : 0
        }
        try file.write(from: buffer)
        return url
    }

    static func tempURL(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-\(name).wav")
    }
}

final class FakeDiarizer: MeetingDiarizing, @unchecked Sendable {
    var result: MeetingDiarization
    var error: Error?
    private(set) var learned: [(name: String, spans: [SpeechSpan])] = []

    init(_ result: MeetingDiarization) { self.result = result }

    func diarize(track: URL) async throws -> MeetingDiarization {
        if let error { throw error }
        return result
    }

    var profileNames: [String] = []

    func learnProfile(name: String, from track: URL, spans: [SpeechSpan]) async throws {
        learned.append((name, spans))
    }

    func knownSpeakerNames() -> [String] { profileNames }
}
