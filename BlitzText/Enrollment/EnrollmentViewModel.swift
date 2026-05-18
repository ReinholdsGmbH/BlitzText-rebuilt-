import Foundation
import Combine
import FluidAudio

// MARK: - EnrollmentViewModel

/// State-Machine für den Sprecher-Enrollment-Flow.
/// Steuert Countdown, Recorder, Fehler-Mapping und DSGVO-Cleanup.
/// Spec: SPK-08, 06-CONTEXT.md §EnrollmentViewModel.
@MainActor
final class EnrollmentViewModel: ObservableObject {

    // MARK: - State

    enum State: Equatable {
        case idle
        case recording(remainingSeconds: Int)
        case processing
        case done
        case failed(String)
    }

    // MARK: - Published

    @Published private(set) var state: State = .idle
    @Published private(set) var currentLevel: Float = 0

    // MARK: - Pflicht-Fehlerstrings (06-UI-SPEC §Copywriting Contract)

    private static let errDiarizerNotReady =
        "Sprecher-Erkennungsmodell nicht bereit. Bitte kurz warten und erneut versuchen."
    private static let errTooShort =
        "Aufnahme zu kurz — bitte mindestens 5 Sekunden sprechen."
    private static let errTooQuiet =
        "Aufnahme zu leise — bitte lauter sprechen oder näher ans Mikrofon."
    private static let errGenericPrefix =
        "Profil konnte nicht angelegt werden: "
    private static let errMicFailed =
        "Mikrofon konnte nicht gestartet werden: "
    private static let errRecorderNil =
        "Aufnahme zu kurz oder zu leise — bitte erneut versuchen."
    private static let errEmptyName =
        "Bitte einen Namen eingeben."

    // MARK: - Dependencies (Closure-Injection)

    private let recorderStart: () throws -> URL
    private let recorderStop: () -> URL?
    private let enroll: (URL, String) async throws -> Speaker
    private weak var speakerVM: SpeakerProfileViewModel?

    // MARK: - Private state

    private var countdownTask: Task<Void, Never>?
    private var levelSubscription: AnyCancellable?
    private var recordingURL: URL?
    private let totalSeconds: Int

    // MARK: - Designated Init (Pflicht-Form für Testbarkeit)

    /// Designated Init mit Closure-Injection für alle externen Abhängigkeiten.
    /// Alle Tests nutzen diesen Init mit Closure-Fakes — kein Protocol, kein XCTSkip.
    init(
        recorderStart: @escaping () throws -> URL,
        recorderStop: @escaping () -> URL?,
        levelPublisher: AnyPublisher<Float, Never>,
        enroll: @escaping (URL, String) async throws -> Speaker,
        speakerVM: SpeakerProfileViewModel,
        totalSeconds: Int = 15
    ) {
        self.recorderStart = recorderStart
        self.recorderStop = recorderStop
        self.enroll = enroll
        self.speakerVM = speakerVM
        self.totalSeconds = totalSeconds

        levelSubscription = levelPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.currentLevel = level
            }
    }

    // MARK: - Convenience Init (Production-Wiring)

    /// Wrappt AudioRecorder + ParakeetClient.enrollSpeaker in Closures und delegiert an Designated-Init.
    convenience init(
        audioRecorder: AudioRecorder,
        parakeetClient: ParakeetClient,
        speakerVM: SpeakerProfileViewModel,
        totalSeconds: Int = 15
    ) {
        self.init(
            recorderStart: { try audioRecorder.start() },
            recorderStop: { audioRecorder.stop() },
            levelPublisher: audioRecorder.$currentLevel.receive(on: RunLoop.main).eraseToAnyPublisher(),
            enroll: { url, name in try await parakeetClient.enrollSpeaker(audioURL: url, name: name) },
            speakerVM: speakerVM,
            totalSeconds: totalSeconds
        )
    }

    // MARK: - Public API

    /// Startet die Aufnahme. Guard: nur aus .idle heraus.
    func startRecording(name: String) {
        guard case .idle = state else { return }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed(Self.errEmptyName)
            return
        }

        do {
            let url = try recorderStart()
            recordingURL = url
            state = .recording(remainingSeconds: totalSeconds)
            startCountdown(name: trimmed)
        } catch {
            state = .failed(Self.errMicFailed + error.localizedDescription)
        }
    }

    /// Stoppt die Aufnahme manuell und startet den Enroll-Prozess.
    func stopAndEnroll(name: String) {
        countdownTask?.cancel()
        countdownTask = nil

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = recorderStop() else {
            state = .failed(Self.errRecorderNil)
            return
        }

        state = .processing
        enrollInternal(audioURL: url, name: trimmed)
    }

    /// Setzt VM in .idle zurück und cancelt den Countdown.
    func reset() {
        countdownTask?.cancel()
        countdownTask = nil
        recordingURL = nil
        state = .idle
    }

    // MARK: - Private

    private func startCountdown(name: String) {
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: self.totalSeconds - 1, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.state = .recording(remainingSeconds: remaining)
            }
            // Countdown abgelaufen — auto-stopp
            if !Task.isCancelled {
                self.stopAndEnroll(name: name)
            }
        }
    }

    private func enrollInternal(audioURL: URL, name: String) {
        Task { [weak self] in
            guard let self else { return }
            defer {
                // DSGVO: Temp-WAV-URL nach enroll (Erfolg ODER Fehler) löschen
                try? FileManager.default.removeItem(at: audioURL)
            }
            do {
                let speaker = try await self.enroll(audioURL, name)
                self.speakerVM?.addEnrolledSpeaker(speaker)
                self.state = .done
            } catch EnrollmentError.diarizerNotReady {
                self.state = .failed(Self.errDiarizerNotReady)
            } catch EnrollmentError.tooShort {
                self.state = .failed(Self.errTooShort)
            } catch EnrollmentError.tooQuiet {
                self.state = .failed(Self.errTooQuiet)
            } catch {
                self.state = .failed(Self.errGenericPrefix + error.localizedDescription)
            }
        }
    }
}
