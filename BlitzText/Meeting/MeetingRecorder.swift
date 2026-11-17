import Foundation
import AVFoundation

/// Ergebnis eines Mitschnitts: zwei getrennte Spuren.
struct MeetingRecording {
    /// Eigenes Mikrofon — 16 kHz mono, wie bei jeder BlitzText-Aufnahme.
    /// `nil`, wenn durchgehend geschwiegen wurde.
    let microphoneTrack: URL?
    /// Ausgabe der Meeting-Apps, 16 kHz mono wie die Mikrofonspur.
    /// `nil`, wenn kein Systemaudio erfasst wurde.
    let systemAudioTrack: URL?
    let startedAt: Date
    let duration: TimeInterval
    let sources: [MeetingSource]
    /// Systemaudio lief, kam aber stumm zurück — fast immer eine fehlende Berechtigung.
    let systemAudioWasSilent: Bool
}

/// Schneidet ein Meeting auf zwei getrennten Spuren mit: eigenes Mikrofon und die
/// Ausgabe der Konferenz-App.
///
/// Warum zwei Spuren statt eines Mixdowns: Die Trennung „ich" gegen „alle anderen" fällt
/// damit umsonst ab. Ein Mixdown müsste dieselbe Information hinterher per Diarisierung
/// rekonstruieren, und zwar schlechter — die eigene Stimme kommt über das Mikrofon
/// trocken an, über den Rückkanal gar nicht.
///
/// Was dieser Typ bewusst NICHT tut: Er fragt niemanden um Erlaubnis. Wer in einem
/// Meeting mit anderen mitschneidet, braucht deren Einverständnis; in Deutschland ist das
/// bei vertraulich gesprochenem Wort keine Formalie, sondern § 201 StGB. Die Zustimmung
/// einzuholen gehört in die Bedienoberfläche und in den Meeting-Chat, nicht in die
/// Aufnahmeschicht. `MeetingRecorder` macht nur das, was ihm aufgetragen wird, und
/// dokumentiert in `MeetingRecording`, was tatsächlich erfasst wurde.
@MainActor
final class MeetingRecorder: ObservableObject {

    enum RecorderState: Equatable {
        case idle
        case recording(startedAt: Date)
    }

    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var detectedSources: [MeetingSource] = []

    private let microphone: RecorderProtocol
    private let systemAudio: SystemAudioCapturing
    private let detector: MeetingDetector
    private let processList: AudioProcessListing

    private var startedAt: Date?
    private(set) var activeSources: [MeetingSource] = []
    private var systemAudioURL: URL?

    init(
        microphone: RecorderProtocol = AudioRecorder(),
        systemAudio: SystemAudioCapturing = SystemAudioTap(),
        detector: MeetingDetector = MeetingDetector(),
        processList: AudioProcessListing = CoreAudioProcessList()
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.detector = detector
        self.processList = processList
    }

    /// Quellen, die gerade wirklich in einem Gespräch sind: Die App-Familie benutzt das
    /// Mikrofon, oder der Browser meldet Mikrofon/Kamera im Fenstertitel. Grundlage für
    /// den Meeting-Hinweis. Ein bloß geöffnetes Teams zählt nicht.
    func activeMeetingSources() -> [MeetingSource] {
        let sources = detector.detectSources()
        detectedSources = sources
        return MeetingAudioMatcher.activeSources(sources, in: processList.processes())
    }

    /// Aktualisiert die Liste erkannter Meeting-Quellen — für die Anzeige im Menü,
    /// bevor überhaupt aufgenommen wird.
    func refreshSources() {
        detectedSources = detector.detectSources()
    }

    /// Hängt Live-Puffer an Mikrofon und Systemton, solange aufgenommen wird. Nur echte
    /// Recorder haben einen Abzweig; Fakes in Tests liefern leere Liste.
    func attachLiveBuffers() -> [(LiveAudioBuffer, TranscriptLine.Speaker)] {
        var result: [(LiveAudioBuffer, TranscriptLine.Speaker)] = []
        if let mic = microphone as? AudioRecorder {
            let buffer = LiveAudioBuffer(); mic.liveSink = buffer; result.append((buffer, .me))
        }
        if let tap = systemAudio as? SystemAudioTap {
            let buffer = LiveAudioBuffer(); tap.liveSink = buffer; result.append((buffer, .others))
        }
        return result
    }

    func detachLiveBuffers() {
        (microphone as? AudioRecorder)?.liveSink = nil
        (systemAudio as? SystemAudioTap)?.liveSink = nil
    }

    /// Mikrofonpegel 0…1 für die Pegelbalken der Pille.
    var microphoneLevel: Float { (microphone as? AudioRecorder)?.currentLevel ?? 0 }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// Startet den Mitschnitt.
    ///
    /// `restrictToDetectedApps` entscheidet über die Reichweite des Taps: `true` nimmt nur
    /// die erkannten Konferenz-Apps auf, `false` alles, was das System ausgibt. Die
    /// Beschränkung ist der Normalfall — sie hält Musik, Benachrichtigungstöne und andere
    /// Gespräche aus der Aufnahme heraus.
    ///
    /// Schlägt nur das Systemaudio fehl, läuft die Mikrofonspur trotzdem weiter: ein
    /// Mitschnitt der eigenen Wortmeldungen ist mehr wert als gar keiner. Der Fehler wird
    /// geworfen, sobald das Mikrofon nicht startet, denn dann bleibt nichts übrig.
    func start(restrictToDetectedApps: Bool = true) throws {
        guard !isRecording else { return }

        // Nur Apps, die gerade wirklich im Gespräch sind (Mikrofon aktiv oder Browser mit
        // Mikrofon-Zusatz). Früher fiel die Aufnahme ohne aktives Gespräch auf alle laufenden
        // Konferenz-Apps zurück; ein im Hintergrund offenes Teams machte so aus jeder Aufnahme
        // ein „Microsoft Teams-Meeting“. Ohne aktive Quelle heißt sie jetzt „Meeting“, und der
        // Tap nimmt den gesamten Systemton.
        let processes = processList.processes()
        let detected = detector.detectSources()
        let sources = MeetingAudioMatcher.activeSources(detected, in: processes)
        detectedSources = detected
        activeSources = sources

        let micURL = try microphone.start()

        let tapURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-meeting-\(UUID().uuidString).wav")
        // Hilfsprozesse einbeziehen: Chrome und Teams geben Ton nicht über die Haupt-PID aus.
        // Leere Liste heißt globaler Tap — der Rückfall, wenn keine Quelle erkannt wurde.
        let pids = restrictToDetectedApps
            ? MeetingAudioMatcher.tapPIDs(for: sources, in: processes)
            : []
        Log.write("MeetingRecorder: Tap auf \(pids.isEmpty ? "alle Prozesse" : "PIDs \(pids)")")
        do {
            try systemAudio.start(writingTo: tapURL, processes: pids)
            systemAudioURL = tapURL
        } catch {
            // Kein Abbruch: die Mikrofonspur läuft bereits und bleibt brauchbar.
            systemAudioURL = nil
            Log.write("MeetingRecorder: Systemaudio nicht gestartet — \(error.localizedDescription). Mitschnitt läuft nur über das Mikrofon.")
        }

        let now = Date()
        startedAt = now
        state = .recording(startedAt: now)
        Log.write("MeetingRecorder: gestartet — \(sources.count) Quelle(n), Mikro=\(micURL.lastPathComponent)")
        _ = micURL
    }

    /// Beendet den Mitschnitt und liefert beide Spuren.
    @discardableResult
    func stop() -> MeetingRecording? {
        guard isRecording, let began = startedAt else { return nil }

        let micURL = microphone.stop()
        let tapOutcome = systemAudio.stop()

        let duration = Date().timeIntervalSince(began)
        state = .idle
        startedAt = nil

        let recording = MeetingRecording(
            microphoneTrack: micURL,
            systemAudioTrack: tapOutcome?.wasSilent == true ? nil : tapOutcome?.url,
            startedAt: began,
            duration: duration,
            sources: activeSources,
            systemAudioWasSilent: tapOutcome?.wasSilent ?? false
        )
        activeSources = []
        systemAudioURL = nil

        Log.write("MeetingRecorder: gestoppt — \(String(format: "%.1f", duration))s, Mikro=\(micURL != nil), System=\(recording.systemAudioTrack != nil)")
        return recording
    }
}
