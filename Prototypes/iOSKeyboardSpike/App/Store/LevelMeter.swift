import AVFoundation

/// Pegelmessung und Dateiaufnahme im Audio-Thread. Kein MainActor, deshalb eigenes Lock.
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var isRecording = false
    private var frames: Int = 0
    private var peak: Float = 0
    private var file: AVAudioFile?

    /// Startet die Aufnahme in eine Datei. Ohne `fileSettings` im Format des Mikrofons (CAF),
    /// sonst z. B. AAC für lange Meetings.
    func begin(writingTo url: URL, format: AVAudioFormat, fileSettings: [String: Any]? = nil) throws {
        let newFile = try AVAudioFile(forWriting: url, settings: fileSettings ?? format.settings,
                                      commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        lock.withLock { isRecording = true; frames = 0; peak = 0; file = newFile }
    }

    /// Beendet die Aufnahme; die Datei wird mit dem Freigeben geschlossen.
    func end() -> (frames: Int, peak: Float) {
        lock.withLock { isRecording = false; file = nil; return (frames, peak) }
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
            try? file?.write(from: buffer)
        }
    }
}
