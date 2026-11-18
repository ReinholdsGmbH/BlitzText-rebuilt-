import Foundation
import AVFoundation
import CoreAudio

/// Test-Seam: Vertrag für die Systemaudio-Aufnahme. Produktion: `SystemAudioTap`.
/// Tests docken an `FakeSystemAudioTap` an, ohne CoreAudio-HAL zu berühren.
protocol SystemAudioCapturing: AnyObject {
    /// Startet die Aufnahme und schreibt nach `url`. `processes` leer = gesamtes System.
    func start(writingTo url: URL, processes: [pid_t]) throws
    /// Beendet die Aufnahme. `nil`, wenn gar nicht lief.
    @discardableResult
    func stop() -> SystemAudioOutcome?
    var isRunning: Bool { get }
}

/// Ergebnis einer beendeten Systemaudio-Aufnahme.
///
/// `wasSilent` ist der wichtige Teil: Fehlt der Info.plist-Key oder wurde die Berechtigung
/// entzogen, laeuft der Tap scheinbar normal und liefert nur Nullsamples. Von aussen ist
/// das nicht von echter Stille zu unterscheiden, deshalb wird der Fakt hier transportiert
/// statt verschluckt.
struct SystemAudioOutcome {
    let url: URL
    let duration: TimeInterval
    let peak: Float
    let wasSilent: Bool
}

/// Nimmt die Audio-AUSGABE anderer Prozesse auf (das, was aus den Lautsprechern käme) —
/// also die Gegenseite eines Meetings, nicht das eigene Mikrofon.
///
/// Weg: Core Audio Process Tap (macOS 14.2+). Bewusst NICHT ScreenCaptureKit:
///  - Taps fallen unter die enge TCC-Kategorie „Systemaudio-Aufnahme“, ohne Zugriff auf
///    Bildschirminhalte. ScreenCaptureKit zieht „Bildschirm- & Systemaudioaufnahme“ nach sich,
///    fragt periodisch neu nach und zeigt den Capture-Indikator in der Menüleiste.
///  - Taps lassen sich auf einzelne Prozesse begrenzen (nur Zoom/Teams statt alles, was spielt).
///
/// Kette: PID → AudioObjectID → CATapDescription → Tap → privates Aggregate-Device → IOProc.
/// Der Tap allein liefert keine Samples; erst ein Aggregate-Device, das ihn einbindet, tut das.
///
/// Fehlt `NSAudioCaptureUsageDescription` in der Info.plist, verweigert TCC den Zugriff
/// still: `AudioHardwareCreateProcessTap` meldet weiter Erfolg, es kommen aber nur
/// Null-Samples. Deshalb prüft `stop()` die Stille und meldet sie als eigenen Zustand,
/// statt eine leere Datei als Erfolg durchzureichen.
final class SystemAudioTap: SystemAudioCapturing, @unchecked Sendable {

    enum TapError: LocalizedError {
        case processNotFound(pid_t)
        case tapCreationFailed(OSStatus)
        case tapFormatUnavailable(OSStatus)
        case aggregateCreationFailed(OSStatus)
        case ioProcFailed(OSStatus)
        case startFailed(OSStatus)
        case unsupportedOS

        var errorDescription: String? {
            switch self {
            case .processNotFound(let pid):
                return "Kein Audio-Prozess für PID \(pid) gefunden — die App gibt gerade nichts aus."
            case .tapCreationFailed(let status):
                return "Systemaudio-Tap konnte nicht angelegt werden (Status \(status))."
            case .tapFormatUnavailable(let status):
                return "Audioformat des Taps nicht lesbar (Status \(status))."
            case .aggregateCreationFailed(let status):
                return "Aggregate-Device für den Tap konnte nicht angelegt werden (Status \(status))."
            case .ioProcFailed(let status):
                return "Audio-Callback konnte nicht registriert werden (Status \(status))."
            case .startFailed(let status):
                return "Systemaudio-Aufnahme ließ sich nicht starten (Status \(status))."
            case .unsupportedOS:
                return "Systemaudio-Aufnahme braucht macOS 14.2 oder neuer."
            }
        }
    }

    private(set) var isRunning = false
    private(set) var lastOutcome: SystemAudioOutcome?

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    /// Optionaler Abzweig der 16-kHz-Daten für das Live-Transkript im Meeting.
    var liveSink: LiveAudioBuffer?
    private var startedAt: Date?
    private var peakAmplitude: Float = 0

    /// Eigene Queue für den IOProc-Callback. Nicht der Cooperative-Pool: ein hängender
    /// HAL-Callback soll nur diesen Thread treffen, nicht die App-weite Nebenläufigkeit.
    /// Gleiche Begründung wie bei `AudioRecorder.halQueue`.
    private let callbackQueue = DispatchQueue(
        label: "de.reinholds.blitztext.systemaudiotap.io",
        qos: .userInitiated
    )

    /// Schutz der von IOProc-Callback und Steuerthread gemeinsam genutzten Felder
    /// (`file`, `peakAmplitude`). Der Callback läuft auf `callbackQueue`, `stop()` auf dem Aufrufer.
    private let stateLock = NSLock()

    /// Unterhalb dieses Peaks gilt die Spur als stumm — derselbe Schwellwert wie beim Mikrofon.
    private let silenceThreshold: Float = 0.005

    // MARK: - Start

    func start(writingTo url: URL, processes: [pid_t]) throws {
        guard #available(macOS 14.2, *) else { throw TapError.unsupportedOS }
        if isRunning { stop() }

        let description = try makeTapDescription(for: processes)
        var tap: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr, tap != kAudioObjectUnknown else {
            throw TapError.tapCreationFailed(tapStatus)
        }
        self.tapID = tap

        do {
            let format = try tapFormat(of: tap)
            let aggregate = try makeAggregateDevice(tapUID: description.uuid.uuidString)
            self.aggregateID = aggregate
            try openFile(at: url, format: format)
            try startIOProc(on: aggregate, format: format)
        } catch {
            // Teilaufbau wieder abräumen: ein verwaister Tap oder ein verwaistes
            // Aggregate-Device bleibt sonst bis zum App-Ende im HAL stehen.
            teardown()
            throw error
        }

        self.fileURL = url
        self.startedAt = Date()
        self.peakAmplitude = 0
        self.isRunning = true
        Log.write("SystemAudioTap: gestartet — processes=\(processes.isEmpty ? "alle" : processes.map(String.init).joined(separator: ","))")
    }

    /// Baut die Tap-Beschreibung: entweder gezielt für die übergebenen Prozesse
    /// (Mixdown ihrer Ausgaben) oder global für alles, was gerade spielt.
    @available(macOS 14.2, *)
    private func makeTapDescription(for processes: [pid_t]) throws -> CATapDescription {
        let description: CATapDescription
        if processes.isEmpty {
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        } else {
            // Einzelne PIDs ohne Audio-Objekt überspringen: Die Haupt-App eines Browsers
            // gibt selbst keinen Ton aus, ihr Hilfsprozess schon. Erst wenn KEINE PID
            // auflösbar ist, gibt es nichts aufzunehmen.
            let objectIDs = processes.compactMap { try? audioObjectID(for: $0) }
            guard !objectIDs.isEmpty else { throw TapError.processNotFound(processes[0]) }
            description = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        }
        description.name = "BlitzText Meeting"
        // Privat: der Tap taucht nicht in der Geräteliste anderer Apps auf.
        description.isPrivate = true
        // Ungemutet — die Teilnehmer sollen das Meeting weiter hören, während wir mitschneiden.
        description.muteBehavior = .unmuted
        return description
    }

    /// Übersetzt eine PID in das Audio-Prozessobjekt des HAL. Prozesse ohne laufende
    /// Audio-Ausgabe haben kein solches Objekt — das ist kein Fehler des Aufrufers,
    /// sondern heißt schlicht: diese App gibt gerade nichts aus.
    private func audioObjectID(for pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var inputPID = pid
        var objectID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &inputPID,
            &size,
            &objectID
        )
        guard status == noErr, objectID != kAudioObjectUnknown else {
            throw TapError.processNotFound(pid)
        }
        return objectID
    }

    /// Das Format legt der Tap fest, nicht wir — es folgt dem, was die getappten
    /// Prozesse ausgeben. Deshalb lesen statt annehmen.
    private func tapFormat(of tap: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw TapError.tapFormatUnavailable(status)
        }
        return format
    }

    /// Ein Tap liefert für sich keine Samples. Erst ein Aggregate-Device, das ihn in seiner
    /// Tap-Liste führt, lässt sich mit einem IOProc auslesen. Privat angelegt, damit es nicht
    /// in den Audio-Einstellungen des Nutzers auftaucht.
    private func makeAggregateDevice(tapUID: String) throws -> AudioObjectID {
        let uid = "de.reinholds.blitztext.tap.\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "BlitzText Meeting Capture",
            kAudioAggregateDeviceUIDKey as String: uid,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            // Keine Sub-Devices: Die Clock kommt vom Tap selbst. Ein Ausgabegerät als
            // Sub-Device aufzunehmen würde das Gerät an die Hardware koppeln und die
            // Aufnahme beim Gerätewechsel (Kopfhörer ab) abreißen lassen.
            kAudioAggregateDeviceSubDeviceListKey as String: [],
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapDriftCompensationKey as String: true,
                    kAudioSubTapUIDKey as String: tapUID
                ]
            ]
        ]
        var aggregate: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate)
        guard status == noErr, aggregate != kAudioObjectUnknown else {
            throw TapError.aggregateCreationFailed(status)
        }
        return aggregate
    }

    /// Schreibt dieselbe 16 kHz mono 16-bit WAV wie `AudioRecorder`, nicht das Rohformat
    /// des Taps. Damit ist die Spur ohne Zwischenschritt transkribierbar und beide Spuren
    /// eines Mitschnitts haben dasselbe Format.
    ///
    /// Das Tap-Format direkt zu schreiben scheiterte an `AVAudioFile` (Fehler -50): Das
    /// Format, das der Tap meldet, laesst sich nicht unveraendert als Dateiformat setzen.
    /// Die Konvertierung im Callback ist derselbe Weg, den `AudioRecorder.write` seit
    /// jeher geht, und bei 48 kHz zu 16 kHz guenstig genug fuer das Audio-Zeitraster.
    private func openFile(at url: URL, format: AVAudioFormat) throws {
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else { throw TapError.tapFormatUnavailable(noErr) }

        self.targetFormat = target
        self.converter = AVAudioConverter(from: format, to: target)
        self.file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: target.sampleRate,
                AVNumberOfChannelsKey: target.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ],
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
    }

    private func startIOProc(on aggregate: AudioObjectID, format: AVAudioFormat) throws {
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID, aggregate, callbackQueue
        ) { [weak self] _, inputData, _, _, _ in
            self?.handle(inputData: inputData, format: format)
        }
        guard status == noErr, let procID else { throw TapError.ioProcFailed(status) }
        self.ioProcID = procID

        let startStatus = AudioDeviceStart(aggregate, procID)
        guard startStatus == noErr else { throw TapError.startFailed(startStatus) }
    }

    // MARK: - Callback

    /// Läuft auf `callbackQueue` im Audio-Zeitraster. Hier nichts allozieren, was sich
    /// vermeiden lässt, und nicht auf den MainActor springen — beides würde bei langen
    /// Aufnahmen zu Aussetzern führen.
    private func handle(inputData: UnsafePointer<AudioBufferList>, format: AVAudioFormat) {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            bufferListNoCopy: inputData,
            deallocator: nil
        ) else { return }

        stateLock.lock()
        defer { stateLock.unlock() }
        guard let file, let converter, let target = targetFormat else { return }

        measurePeak(in: buffer)

        // Resampling-Verhaeltnis grosszuegig bemessen: zu kleine Kapazitaet laesst den
        // Converter mit .endOfStream abbrechen und verschluckt Frames.
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
        guard status != .error, error == nil, outBuffer.frameLength > 0 else { return }
        liveSink?.append(outBuffer)

        do { try file.write(from: outBuffer) } catch {
            Log.write("SystemAudioTap: Schreibfehler — \(error.localizedDescription)")
        }
    }

    /// Peak am Rohbuffer, vor der Konvertierung. Deckt beide Speicherlagen ab: Ein
    /// nicht-interleavter Buffer liefert `floatChannelData`, ein interleavter nicht —
    /// dort wuerde die Messung sonst stumm bleiben und echte Aufnahmen als still melden.
    private func measurePeak(in buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var localPeak: Float = 0

        if let channels = buffer.floatChannelData {
            for ch in 0..<Int(buffer.format.channelCount) {
                let data = channels[ch]
                for i in 0..<frames where abs(data[i]) > localPeak { localPeak = abs(data[i]) }
            }
        } else {
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for audioBuffer in list {
                guard let raw = audioBuffer.mData else { continue }
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = raw.bindMemory(to: Float.self, capacity: count)
                for i in 0..<count where abs(samples[i]) > localPeak { localPeak = abs(samples[i]) }
            }
        }
        if localPeak > peakAmplitude { peakAmplitude = localPeak }
    }

    // MARK: - Stop

    @discardableResult
    func stop() -> SystemAudioOutcome? {
        guard isRunning else { return nil }
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        teardown()

        stateLock.lock()
        let peak = peakAmplitude
        stateLock.unlock()

        isRunning = false
        startedAt = nil
        guard let url = fileURL else { return nil }
        fileURL = nil

        let wasSilent = peak < silenceThreshold
        if wasSilent {
            // Entweder lief wirklich nichts, oder TCC hat den Tap still ausgehebelt
            // (fehlender Info.plist-Key / entzogene Berechtigung). Beides sieht identisch aus,
            // deshalb hier nur den Fakt festhalten; die Einordnung macht der Aufrufer.
            Log.write("SystemAudioTap: Spur ist stumm (peak=\(String(format: "%.4f", peak))) — Berechtigung Systemaudio-Aufnahme pruefen.")
        } else {
            Log.write("SystemAudioTap: gestoppt — duration=\(String(format: "%.1f", duration))s peak=\(String(format: "%.3f", peak))")
        }

        let outcome = SystemAudioOutcome(url: url, duration: duration, peak: peak, wasSilent: wasSilent)
        lastOutcome = outcome
        return outcome
    }

    /// Baut HAL-Objekte in umgekehrter Reihenfolge ab. Jeder Schritt ist für sich
    /// fehlertolerant, damit ein gescheiterter Teilaufbau trotzdem vollständig aufräumt.
    private func teardown() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }

        stateLock.lock()
        file = nil
        converter = nil
        targetFormat = nil
        stateLock.unlock()
    }

    deinit { teardown() }
}
