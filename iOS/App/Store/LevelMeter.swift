import AVFoundation

/// Pegelmessung und Dateiaufnahme im Audio-Thread. Kein MainActor, deshalb eigenes Lock.
/// Wechselt mitten in der Aufnahme das Mikrofon (CarPlay, AirPods), kommen die Puffer in einem
/// anderen Format an; sie werden dann ins Format der Datei umgerechnet, die Aufnahme läuft weiter.
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var isRecording = false
    /// Geschriebene Frames im Format der Datei.
    private var frames: Int = 0
    private var peak: Float = 0
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?

    /// Startet die Aufnahme in eine Datei. Ohne `fileSettings` im Format des Mikrofons (CAF),
    /// sonst z. B. AAC für lange Meetings.
    func begin(writingTo url: URL, format: AVAudioFormat, fileSettings: [String: Any]? = nil) throws {
        let newFile = try AVAudioFile(forWriting: url, settings: fileSettings ?? format.settings,
                                      commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        lock.withLock { isRecording = true; frames = 0; peak = 0; file = newFile; converter = nil }
    }

    /// Beendet die Aufnahme; die Datei wird mit dem Freigeben geschlossen.
    func end() -> (seconds: Double, peak: Float) {
        lock.withLock {
            let rate = file?.processingFormat.sampleRate ?? 48_000
            let result = (Double(frames) / rate, peak)
            isRecording = false
            file = nil
            converter = nil
            return result
        }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var localPeak: Float = 0
        for i in 0..<count { localPeak = max(localPeak, abs(channel[i])) }
        lock.withLock {
            guard isRecording, let file else { return }
            peak = max(peak, localPeak)
            let written = write(buffer, to: file)
            frames += written
        }
    }

    /// Schreibt den Puffer, bei abweichendem Format über einen Konverter. Gibt die Frames zurück.
    private func write(_ buffer: AVAudioPCMBuffer, to file: AVAudioFile) -> Int {
        let target = file.processingFormat
        if buffer.format == target {
            return (try? file.write(from: buffer)) != nil ? Int(buffer.frameLength) : 0
        }
        if converter?.inputFormat != buffer.format || converter?.outputFormat != target {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return 0 }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return 0 }
        var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return 0 }
        return (try? file.write(from: output)) != nil ? Int(output.frameLength) : 0
    }
}
