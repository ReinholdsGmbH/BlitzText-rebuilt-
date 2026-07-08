import Foundation
import AVFoundation

/// Test-Seam: minimaler Recorder-Vertrag, an dem ModeProcessor und Tests andocken.
/// Production: AudioRecorder konformiert via Extension, kein Verhaltensbruch.
/// Tests: FakeAudioRecorder konformiert ohne AVAudioEngine-Abhaengigkeit.
protocol RecorderProtocol: AnyObject {
    func start() throws -> URL
    func stop() -> URL?
}

/// Nimmt Mikrofon nach `start()` auf, schreibt eine 16 kHz mono 16-bit WAV. Stoppt mit `stop()` und liefert die URL.
final class AudioRecorder: ObservableObject, @unchecked Sendable {

    /// Aktueller Pegel (0…1, RMS-basiert mit weichem Decay) — für Live-Visualisierung im Recording-HUD.
    @MainActor @Published private(set) var currentLevel: Float = 0

    /// Im Normalbetrieb langlebig — NICHT pro Aufnahme neu erzeugen (rasches Neu-Erzeugen verwirrt
    /// die CoreAudio-HAL → Folgeaufnahmen liefern Stille). NUR wenn der Eingang „stale" ist
    /// (degeneriertes Format / ObjC-Exception, typisch nach Sleep/Wake) wird sie EINMAL neu
    /// erzeugt und der Start wiederholt (siehe `start()`). Kein ConfigurationChange-Observer —
    /// der feuert auch beim normalen Start und würde die laufende Aufnahme killen.
    private var engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var startedAt: Date?
    private var peakAmplitude: Float = 0

    /// Pegel-Schwelle (Peak): unter diesem Wert gilt die Aufnahme als Stille.
    private let silenceThreshold: Float = 0.005
    /// Mindestlänge der Aufnahme in Sekunden, sonst verworfen.
    private let minDuration: TimeInterval = 0.3

    /// Drosselung der Pegel-Updates auf die Main-Queue. Der Audio-Tap feuert ~86×/s
    /// (4096 Frames @ 48 kHz); ein `Task { @MainActor }` pro Buffer flutete die Main-Queue
    /// (jedes Update = SwiftUI-Re-Render des HUD). Bei einer im Hintergrund gedrosselten
    /// Menubar-App wuchs der Rückstau schneller als er abgearbeitet wurde → Main-Queue-
    /// Starvation: Stop-Trigger, Klicks und Heartbeat kamen nicht mehr durch (App-Freeze).
    /// Deckel: höchstens ~20 Pegel-Updates/s. Reicht für ein flüssiges Level-Meter.
    private let levelThrottleLock = NSLock()
    private var lastLevelEmitAt = Date.distantPast
    private static let levelEmitInterval: TimeInterval = 0.05

    /// Letzte Aufnahme zu kurz oder zu leise — Pipeline soll überspringen.
    private(set) var lastRecordingWasSilence: Bool = false

    func start() throws -> URL {
        try ensureMicrophonePermissionSync()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-\(UUID().uuidString).wav")
        self.fileURL = url

        do {
            try configureAndStart(url: url)
        } catch RecorderError.audioUnavailable {
            // Stale/degenerierter Eingang (typisch nach Sleep/Wake): die langlebige Engine hat ein
            // ungültiges Hardware-Format und erholt sich nicht von selbst. Genau HIER — und nur
            // hier, nicht bei jeder Aufnahme — die Engine EINMAL neu erzeugen und erneut versuchen.
            // Der frisch erzeugte Engine bleibt auch bei erneutem Fehlschlag erhalten, sodass der
            // nächste Aufnahmeversuch ihn nutzt und sich heilt, sobald die Hardware bereit ist.
            Log.write("AudioRecorder: Audio-Eingang stale — Engine neu erzeugen, zweiter Versuch.")
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine = AVAudioEngine()
            try configureAndStart(url: url)
        }
        return url
    }

    /// Konfiguriert Tap/Format/Datei auf der aktuellen `engine` und startet sie. Wirft
    /// `RecorderError.audioUnavailable`, wenn der Eingang „stale"/ungültig ist (degeneriertes
    /// Format oder ObjC-Exception) — der Aufrufer erzeugt die Engine dann neu und wiederholt.
    private func configureAndStart(url: URL) throws {
        // Defensiv sauberer Ausgangszustand: falls die Engine noch läuft oder ein Tap hängt,
        // zurücksetzen. removeTap ohne Tap und stop() ohne Lauf sind No-Ops.
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)

        // Direkt nach Sleep/Wake bzw. Gerätewechsel liefert der InputNode kurzzeitig ein
        // degeneriertes Format (Sample-Rate/Kanäle == 0). installTap/engine.start() würden damit
        // die ObjC-Exception werfen. Hier als sauberen Swift-Fehler abfangen → kein Freeze,
        // stattdessen sichtbarer Fehlerzustand; der nächste Versuch hat i. d. R. ein gültiges Format.
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw RecorderError.audioUnavailable
        }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "BlitzText", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Kann Ziel-Audio-Format nicht erstellen."])
        }
        self.targetFormat = target

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: target.sampleRate,
            AVNumberOfChannelsKey: target.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        self.file = try AVAudioFile(forWriting: url, settings: settings,
                                    commonFormat: .pcmFormatInt16, interleaved: true)
        self.converter = AVAudioConverter(from: inFormat, to: target)

        // installTap/engine.start() können bei stale Hardware-Format eine ObjC-NSException werfen
        // ("required condition is false…"). Ungefangen wird sie aus dem Hotkey-Event-Dispatch
        // verschluckt und tötet die Main-Queue → App-Freeze. In ObjC-@try/@catch kapseln, damit
        // daraus ein sauberer Swift-Fehler wird (RecorderError.audioUnavailable) statt eines Freezes.
        var startError: Error?
        let caught = ExceptionCatcher.run {
            input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
                self?.measurePeak(buffer: buffer)
                self?.write(buffer: buffer)
            }
            self.engine.prepare()
            do { try self.engine.start() } catch { startError = error }
        }
        if let caught {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            Log.write("AudioRecorder: AVAudioEngine-Exception gefangen — \(caught.localizedDescription)")
            throw RecorderError.audioUnavailable
        }
        if let startError {
            engine.inputNode.removeTap(onBus: 0)
            throw startError
        }
        self.startedAt = Date()
        self.peakAmplitude = 0
        self.lastRecordingWasSilence = false
        Task { @MainActor in self.currentLevel = 0 }
    }

    @discardableResult
    func stop() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let url = fileURL
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let peak = peakAmplitude
        self.file = nil
        self.fileURL = nil
        self.converter = nil
        self.startedAt = nil

        let tooShort = duration < minDuration
        let tooQuiet = peak < silenceThreshold
        Task { @MainActor in self.currentLevel = 0 }
        if tooShort || tooQuiet {
            Log.write("Aufnahme verworfen — duration=\(String(format: "%.2f", duration))s peak=\(String(format: "%.3f", peak)) (silenceThreshold=\(silenceThreshold))")
            self.lastRecordingWasSilence = true
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        Log.write("Aufnahme ok — duration=\(String(format: "%.2f", duration))s peak=\(String(format: "%.3f", peak))")
        return url
    }

    private func measurePeak(buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        var localPeak: Float = 0
        var sumSquares: Float = 0
        var count: Int = 0
        for ch in 0..<Int(buffer.format.channelCount) {
            let data = channels[ch]
            for i in 0..<frames {
                let v = data[i]
                let absV = abs(v)
                if absV > localPeak { localPeak = absV }
                sumSquares += v * v
                count += 1
            }
        }
        if localPeak > peakAmplitude { peakAmplitude = localPeak }

        let rms = count > 0 ? sqrtf(sumSquares / Float(count)) : 0
        // Logarithmische Skalierung auf 0…1 für UI-tauglichen Pegel.
        // Floor bei -50 dB, Ceiling bei -10 dB → mappt aus realistischer Sprach-Range.
        let db = 20 * log10f(max(rms, 0.0001))
        let normalized = max(0, min(1, (db + 50) / 40))

        // Drosseln: höchstens alle 50 ms ein Main-Queue-Update — NICHT pro Buffer.
        // Verhindert die Main-Queue-Flut, die den App-Freeze während der Aufnahme auslöste.
        let shouldEmit: Bool = levelThrottleLock.withLock {
            let now = Date()
            guard now.timeIntervalSince(lastLevelEmitAt) >= Self.levelEmitInterval else { return false }
            lastLevelEmitAt = now
            return true
        }
        guard shouldEmit else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Schneller Anstieg, langsames Abklingen
            if normalized > self.currentLevel {
                self.currentLevel = normalized
            } else {
                self.currentLevel = self.currentLevel * 0.85 + normalized * 0.15
            }
        }
    }

    private func write(buffer: AVAudioPCMBuffer) {
        guard let target = targetFormat,
              let converter,
              let file else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || error != nil { return }
        guard outBuffer.frameLength > 0 else { return }
        do { try file.write(from: outBuffer) } catch {
            NSLog("[BlitzText] AudioFile write failed: \(error)")
        }
    }

    // MARK: - Permission

    /// Prüft nur den aktuellen Permission-Status — fordert NICHT an. Das proaktive
    /// `AVCaptureDevice.requestAccess` passiert beim App-Start (AppDelegate.bootstrap),
    /// damit hier nichts den Main-Thread blockiert (vorher: `DispatchSemaphore.wait()` →
    /// einfrierende Menüleiste während des System-Dialogs).
    private func ensureMicrophonePermissionSync() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .notDetermined, .denied, .restricted: throw RecorderError.micDenied
        @unknown default: throw RecorderError.micDenied
        }
    }

    enum RecorderError: Error { case micDenied, audioUnavailable }
}

/// Konformanz-Deklaration: `AudioRecorder.start()` und `AudioRecorder.stop()` erfuellen
/// `RecorderProtocol` bereits — diese Extension ist eine reine Naht fuer DI.
extension AudioRecorder: RecorderProtocol {}
