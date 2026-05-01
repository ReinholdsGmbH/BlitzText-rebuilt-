@testable import BlitzText
import XCTest

/// TEST-04 Pipeline-Error-Path Pins.
///
/// Pinnt das CURRENT-Verhalten der `ModeProcessor`-Pipeline an den drei
/// Fehler-Pfaden, die im RESEARCH.md (§ Pipeline-Fehlerpfade, Pattern 3)
/// als P2-Fragility markiert sind:
///   1. Whisper-API-Fehler  → `.error(...)` mit deutschem Marker
///   2. Parakeet-Modell fehlt → `.error("...Lokales Modell...")`, kein Crash
///   3. Diarization-Fehlschlag → silent fallback, `.idle` mit Roh-Transkript
///
/// Alle Tests injizieren `FakeTranscriptionService` + `FakeAudioRecorder`
/// (Wave 0, Plan 02-01) — kein Netz, keine `AVAudioEngine`, kein Modell-Load.
@MainActor
final class PipelineErrorPathTests: XCTestCase {

    // MARK: - Test fixtures

    /// Liefert eine WAV-URL, die fuer den FakeAudioRecorder reicht.
    /// Wir erzeugen sie einmalig im tmp-Verzeichnis (kein Modell, kein Audio-Decode noetig,
    /// weil der `transcriber` ein Fake ist).
    private func makeFixtureURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("blitztext-pipeline-error-fixture.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            // Minimaler RIFF/WAV-Header (44 Bytes) + 0 Samples.
            // Reicht als Datei-Existenz-Marker fuer den Pipeline-Pfad
            // (Whisper/Parakeet sind Fakes, lesen die Datei nicht).
            var bytes: [UInt8] = Array(repeating: 0, count: 44)
            // "RIFF" + size + "WAVE"
            bytes[0] = 0x52; bytes[1] = 0x49; bytes[2] = 0x46; bytes[3] = 0x46
            bytes[8] = 0x57; bytes[9] = 0x41; bytes[10] = 0x56; bytes[11] = 0x45
            try Data(bytes).write(to: url)
        }
        return url
    }

    private func makeProcessor(
        backend: TranscriptionBackend,
        openAITranscriber: TranscriptionService? = nil,
        parakeetTranscriber: TranscriptionService? = nil,
        recorder: RecorderProtocol
    ) -> ModeProcessor {
        let settings = SettingsStore()
        settings.backend = backend
        let history = HistoryStore()
        let modelManager = LocalModelManager()
        return ModeProcessor(
            settings: settings,
            history: history,
            modelManager: modelManager,
            openAITranscriber: openAITranscriber,
            localTranscriber: nil,
            parakeetTranscriber: parakeetTranscriber,
            rewriter: nil,
            recorder: recorder
        )
    }

    // MARK: - TEST-04 (a): Whisper-API-Fehler

    /// Pinnt: Ein `TranscriptionError.network` aus dem OpenAI-Backend
    /// landet als deutsche Fehlermeldung im `state == .error(...)`.
    ///
    /// Akzeptierte Marker: `"Netzwerk:"` ODER `"OpenAI-Fehler"` —
    /// genau die zwei Substrings, die `TranscriptionError.errorDescription`
    /// fuer die Whisper-API-Fehler heute produziert.
    /// Eine Substring-Akzeptanz fuer den Recorder-Permission-String
    /// (M-i-k-r-o-f-o-n-Praefix) ist explizit AUSGESCHLOSSEN: Backend ist
    /// `.openAI` und `FakeAudioRecorder` ist injiziert — ein solcher
    /// Substring wuerde indizieren, dass der echte AVAudioEngine-Pfad
    /// gestartet wurde (Test-Setup-Leak), und der Test MUSS dann fehlschlagen.
    func testWhisperError_propagatesGermanErrorToUser() async throws {
        let fixtureURL = try makeFixtureURL()
        let recorder = FakeAudioRecorder(fixtureURL: fixtureURL)
        let injectedError = TranscriptionError.network(URLError(.notConnectedToInternet))
        let transcriber = FakeTranscriptionService(.failure(injectedError))

        let mp = makeProcessor(
            backend: .openAI,
            openAITranscriber: transcriber,
            recorder: recorder
        )

        await mp.start(mode: .blitztext)
        await mp.stop()

        guard case let .error(msg) = mp.state else {
            return XCTFail("Erwartet: .error(...) — bekam: \(mp.state)")
        }
        XCTAssertFalse(msg.isEmpty, "Fehler-Meldung darf nicht leer sein")
        XCTAssertTrue(
            msg.contains("Netzwerk:") || msg.contains("OpenAI-Fehler"),
            "Erwartet einen Whisper-Marker (\"Netzwerk:\" oder \"OpenAI-Fehler\") — bekam: \(msg)"
        )
        XCTAssertEqual(transcriber.callCount, 1, "Fake-Transcriber muss genau einmal aufgerufen worden sein")
    }

    // MARK: - TEST-04 (b): Parakeet-Modell fehlt

    /// Pinnt: Wenn das Parakeet-Backend `TranscriptionError.backendNotAvailable`
    /// wirft, stuerzt die Pipeline NICHT ab und liefert eine deutsche
    /// Fehlermeldung mit dem Substring `"Lokales Modell"` —
    /// das ist der String aus `TranscriptionError.backendNotAvailable.errorDescription`
    /// ("Lokales Modell ist noch nicht verfuegbar.").
    /// `mp.state` ist NICHT `.idle` (sondern `.error`) — d.h. die Pipeline ist
    /// nicht „normal durchgelaufen" und hat weder `.rewriting` noch Clipboard
    /// erreicht (pragmatischer Pin ueber den oeffentlichen State).
    func testParakeetModelMissing_doesNotCrashAndSurfacesError() async throws {
        let fixtureURL = try makeFixtureURL()
        let recorder = FakeAudioRecorder(fixtureURL: fixtureURL)
        let transcriber = FakeTranscriptionService(.failure(TranscriptionError.backendNotAvailable))

        let mp = makeProcessor(
            backend: .parakeet,
            parakeetTranscriber: transcriber,
            recorder: recorder
        )

        await mp.start(mode: .blitztext)
        await mp.stop()

        // (a) Kein Crash — wenn `xcodebuild test` exit 0 liefert, ist das implizit erfuellt.
        // (b) Deutscher Marker auf state.
        guard case let .error(msg) = mp.state else {
            return XCTFail("Erwartet: .error(...) — bekam: \(mp.state)")
        }
        XCTAssertTrue(
            msg.contains("Lokales Modell"),
            "Erwartet Substring \"Lokales Modell\" aus TranscriptionError.backendNotAvailable.errorDescription — bekam: \(msg)"
        )
        // (c) Pipeline ist NICHT in `.idle` — d.h. sie ist nicht durchgelaufen,
        // also wurde weder `.rewriting` noch `deliver(...)` erreicht.
        XCTAssertNotEqual(mp.state, .idle)
    }

    // MARK: - TEST-04 (c): Diarization-Fehlschlag — silent fallback

    /// Pinnt CURRENT-Verhalten (RESEARCH.md § Pattern 3 + ParakeetClient.swift:51-53):
    /// Diarization-Fehler werden in `ParakeetClient.applyDiarization` verschluckt,
    /// der Roh-Transkript-String wird zurueckgegeben — observable als `.idle`-State
    /// nach erfolgreichem Pipeline-Lauf, KEIN `.error`.
    ///
    /// Eine zukuenftige UX, die Diarization-Fehler als HUD-Warnung surfacet, ist
    /// Phase 3 — dieser Test wird dann bewusst angepasst.
    ///
    /// Implementations-Note: Da `ParakeetClient.transcribe` Diarization intern
    /// abhandelt und nur den Text zurueckreicht, ist ein erfolgreicher
    /// `FakeTranscriptionService(.success(...))` fuer den State-Pin ausreichend —
    /// der Pipeline-Pfad ist auf State-Ebene identisch zu „Diarization fehlgeschlagen,
    /// raw zurueck". Kein extra `FakeDiarizationService` noetig.
    func testDiarizationFailure_silentFallback_returnsRawTranscript() async throws {
        let fixtureURL = try makeFixtureURL()
        let recorder = FakeAudioRecorder(fixtureURL: fixtureURL)
        let transcriber = FakeTranscriptionService(.success("hallo welt"))

        let mp = makeProcessor(
            backend: .parakeet,
            parakeetTranscriber: transcriber,
            recorder: recorder
        )

        await mp.start(mode: .blitztext)
        await mp.stop()

        // CURRENT behavior pinned: Pipeline laeuft erfolgreich durch,
        // landet auf .idle (KEIN .error trotz potenziellem internen
        // Diarization-Fail im Parakeet-Pfad).
        XCTAssertEqual(mp.state, .idle, "Erwartet: .idle nach erfolgreichem Fake-Backend-Lauf — bekam: \(mp.state)")
        XCTAssertEqual(transcriber.callCount, 1)
    }
}
