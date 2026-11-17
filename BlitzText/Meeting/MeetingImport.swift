import AVFoundation
import Foundation

/// Import vorhandener Aufnahmen, etwa aus MacWhisper.
///
/// Zwei Fälle:
/// - Eine Datei: Mischspur mit allen Stimmen, auch der eigenen. Sie läuft komplett durch die
///   Sprechertrennung; die eigene Stimme wird über ein Profil erkannt, sobald es eines gibt.
/// - Zwei Dateien, eine davon erkennbar als Mikrofon: wie ein BlitzText-Mitschnitt, eigene
///   Spur „Ich" plus Gegenseite. MacWhisper legt solche Paare als `…_mic-audio_…` und
///   `…_app-audio_…` ab.
enum MeetingImport {

    struct Plan: Equatable {
        let microphone: URL?
        let others: URL
        /// `true`: Mischspur ohne getrennte eigene Stimme.
        var isMixed: Bool { microphone == nil }
    }

    enum ImportError: LocalizedError {
        case noFiles
        case tooManyFiles
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .noFiles: return "Keine Audiodatei ausgewählt."
            case .tooManyFiles: return "Höchstens zwei Dateien: Mikrofon und Gegenseite, oder eine Mischspur."
            case .unreadable(let name): return "„\(name)“ ließ sich nicht als Audio lesen."
            }
        }
    }

    static let microphoneMarkers = ["mic", "mikro", "microphone", "mikrofon", "ich", "me"]

    static func plan(for urls: [URL]) throws -> Plan {
        switch urls.count {
        case 0: throw ImportError.noFiles
        case 1: return Plan(microphone: nil, others: urls[0])
        case 2:
            let isMic: (URL) -> Bool = { url in
                let tokens = url.deletingPathExtension().lastPathComponent.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                return tokens.contains { microphoneMarkers.contains($0) } ||
                    url.lastPathComponent.lowercased().contains("mic-audio")
            }
            if isMic(urls[0]), !isMic(urls[1]) { return Plan(microphone: urls[0], others: urls[1]) }
            if isMic(urls[1]), !isMic(urls[0]) { return Plan(microphone: urls[1], others: urls[0]) }
            // Nicht unterscheidbar: die erste gilt als Mikrofon, wie im Dateidialog gewählt.
            return Plan(microphone: urls[0], others: urls[1])
        default: throw ImportError.tooManyFiles
        }
    }

    /// Wandelt eine beliebige von AVFoundation lesbare Datei (m4a, mp3, wav, aiff, mp4 …)
    /// blockweise in 16 kHz mono Int16-WAV. Liefert die Dauer in Sekunden.
    @discardableResult
    static func convert(_ source: URL, to destination: URL) throws -> TimeInterval {
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: source) } catch {
            throw ImportError.unreadable(source.lastPathComponent)
        }
        let inFormat = input.processingFormat
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw ImportError.unreadable(source.lastPathComponent)
        }
        let output = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ], commonFormat: .pcmFormatFloat32, interleaved: false)

        let blockFrames: AVAudioFrameCount = 65_536
        let outCapacity = AVAudioFrameCount(Double(blockFrames) * 16_000 / inFormat.sampleRate) + 1024
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: blockFrames),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            throw ImportError.unreadable(source.lastPathComponent)
        }

        var finished = false
        while !finished {
            outBuffer.frameLength = 0
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
                if input.framePosition >= input.length {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try input.read(into: inBuffer, frameCount: blockFrames)
                } catch {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = inBuffer.frameLength > 0 ? .haveData : .endOfStream
                return inBuffer
            }
            if let conversionError { throw conversionError }
            if outBuffer.frameLength > 0 { try output.write(from: outBuffer) }
            finished = status == .endOfStream || status == .error
        }
        return Double(output.length) / 16_000
    }
}
