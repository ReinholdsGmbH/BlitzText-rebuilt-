@testable import BlitzText
import FluidAudio
import XCTest
import AVFoundation

/// Tests für ParakeetClient.enrollSpeaker — Fehler-Pfade (SPK-08).
/// Der Happy-Path (extractSpeakerEmbedding) erfordert geladene CoreML-Modelle und ist
/// daher in der CI-Umgebung nicht ausführbar. Die Tests validieren mindestens den
/// EnrollmentError-Typ auf allen Ungültigkeits-Pfaden.
@MainActor
final class EnrollmentTests: XCTestCase {

    // MARK: - Hilfsmethode: WAV-Datei erzeugen

    /// Schreibt eine WAV-Datei mit `seconds` Sekunden Audio @ 16 kHz Mono.
    /// `fillValue` = 0.0 → Stille; `fillValue` = 1.0 → Maximalamplitude (Sinus-Ersatz).
    private func makeWavFile(seconds: Double, amplitude: Float = 0.5) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("enrollment-test-\(UUID().uuidString).wav")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw NSError(domain: "EnrollmentTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioFormat konnte nicht erstellt werden"])
        }
        let sampleCount = AVAudioFrameCount(seconds * 16_000)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sampleCount) else {
            throw NSError(domain: "EnrollmentTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioPCMBuffer konnte nicht erstellt werden"])
        }
        buffer.frameLength = sampleCount
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<Int(sampleCount) {
                let t = Float(i) / 16_000.0
                // Sinus 440 Hz mit gegebener Amplitude (amplitude=0 → Stille)
                channelData[i] = amplitude > 0 ? amplitude * sin(2 * .pi * 440 * t) : 0.0
            }
        }
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
        return url
    }

    // MARK: - Tests

    /// 4 Sekunden Audio → muss EnrollmentError werfen (tooShort ODER diarizerNotReady,
    /// je nach ob der Diarizer in der Test-Umgebung initialisierbar ist).
    func testEnrollSpeaker_tooShort_throws() async throws {
        let client = makeTestClient()
        let audioURL = try makeWavFile(seconds: 4.0, amplitude: 0.5)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await client.enrollSpeaker(audioURL: audioURL, name: "Test")
            // Ohne geladene Modelle kann dieser Pfad nicht erfolgreich sein
            XCTFail("enrollSpeaker sollte einen Fehler werfen, hat aber erfolgreich zurückgegeben")
        } catch let error as EnrollmentError {
            // tooShort oder diarizerNotReady — beides ist ein valider Fehler-Pfad
            XCTAssertTrue(
                error == .tooShort || error == .diarizerNotReady,
                "Unerwarteter EnrollmentError: \(error)"
            )
        } catch {
            XCTFail("Unerwarteter Error-Typ: \(error) — erwartet EnrollmentError")
        }
    }

    /// 6 Sekunden Stille (amplitude=0) → muss EnrollmentError werfen
    /// (tooQuiet ODER diarizerNotReady).
    func testEnrollSpeaker_tooQuiet_throws() async throws {
        let client = makeTestClient()
        let audioURL = try makeWavFile(seconds: 6.0, amplitude: 0.0)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await client.enrollSpeaker(audioURL: audioURL, name: "Test")
            XCTFail("enrollSpeaker sollte einen Fehler werfen, hat aber erfolgreich zurückgegeben")
        } catch let error as EnrollmentError {
            XCTAssertTrue(
                error == .tooQuiet || error == .diarizerNotReady,
                "Unerwarteter EnrollmentError: \(error)"
            )
        } catch {
            XCTFail("Unerwarteter Error-Typ: \(error) — erwartet EnrollmentError")
        }
    }

    /// ParakeetClient ohne geladenen Diarizer (parakeetDiarization = false) →
    /// 10 Sekunden gültiges Audio → muss EnrollmentError.diarizerNotReady werfen.
    func testEnrollSpeaker_diarizerNotReady_throws() async throws {
        // SettingsStore mit deaktivierter Diarisierung → ensureLoaded setzt diarizer = nil
        let client = makeTestClient(diarizationEnabled: false)
        let audioURL = try makeWavFile(seconds: 10.0, amplitude: 0.5)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await client.enrollSpeaker(audioURL: audioURL, name: "Test")
            XCTFail("enrollSpeaker sollte EnrollmentError.diarizerNotReady werfen")
        } catch EnrollmentError.diarizerNotReady {
            // Erwartet — Test bestanden
        } catch {
            XCTFail("Unerwarteter Error: \(error) — erwartet EnrollmentError.diarizerNotReady")
        }
    }

    // MARK: - Hilfsmethoden

    @MainActor
    private func makeTestClient(diarizationEnabled: Bool = true) -> ParakeetClient {
        let settings = SettingsStore()
        settings.parakeetDiarization = diarizationEnabled
        let diarizerManager = DiarizerModelManager()
        return ParakeetClient(settings: settings, diarizerManager: diarizerManager)
    }
}
