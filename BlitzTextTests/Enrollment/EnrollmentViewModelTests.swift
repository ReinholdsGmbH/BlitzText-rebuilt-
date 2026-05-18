import XCTest
import Combine
@testable import BlitzText
import FluidAudio

/// State-Machine-Tests für EnrollmentViewModel über Closure-Injection (Designated-Init).
/// Kein XCTSkip, kein echtes Mikrofon, kein echter ParakeetClient.
/// Spec: 06-02-PLAN.md §Task 2 <behavior>, SPK-08.
@MainActor
final class EnrollmentViewModelTests: XCTestCase {

    // MARK: - Properties

    private var cancellables = Set<AnyCancellable>()
    private var storeURL: URL!
    private var store: SpeakerProfileStore!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bt-enroll-test-\(UUID().uuidString).json")
        store = SpeakerProfileStore(url: storeURL)
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: storeURL)
    }

    // MARK: - Helpers

    private func makeSpeakerVM() -> SpeakerProfileViewModel {
        SpeakerProfileViewModel(store: store)
    }

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bt-enroll-audio-\(UUID().uuidString).wav")
    }

    /// Baut EnrollmentViewModel über Designated-Init mit Closure-Fakes.
    private func makeViewModel(
        recorderStart: @escaping () throws -> URL = {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString).wav")
        },
        recorderStop: (() -> URL?)? = nil,
        enroll: @escaping (URL, String) async throws -> Speaker = { _, _ in
            Speaker(id: "test-id", name: "Thomas",
                    currentEmbedding: Array(repeating: 0.1, count: 256),
                    isPermanent: true)
        },
        speakerVM: SpeakerProfileViewModel? = nil,
        totalSeconds: Int = 15
    ) -> EnrollmentViewModel {
        let svm = speakerVM ?? makeSpeakerVM()
        let defaultStopURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).wav")
        let stop = recorderStop ?? { defaultStopURL }
        return EnrollmentViewModel(
            recorderStart: recorderStart,
            recorderStop: stop,
            levelPublisher: Just<Float>(0).eraseToAnyPublisher(),
            enroll: enroll,
            speakerVM: svm,
            totalSeconds: totalSeconds
        )
    }

    // MARK: - Tests

    func testInitialState() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.state, .idle)
    }

    func testStartRecording_setsRecordingState() {
        let vm = makeViewModel(totalSeconds: 15)
        vm.startRecording(name: "Thomas")
        XCTAssertEqual(vm.state, .recording(remainingSeconds: 15))
    }

    func testStartRecording_emptyName_setsFailed() {
        let vm = makeViewModel()
        vm.startRecording(name: "   ")
        XCTAssertEqual(vm.state, .failed("Bitte einen Namen eingeben."))
    }

    func testStopAndEnroll_nilURL_setsFailed() {
        let vm = makeViewModel(recorderStop: { nil })
        vm.startRecording(name: "Thomas")
        vm.stopAndEnroll(name: "Thomas")
        XCTAssertEqual(vm.state, .failed("Aufnahme zu kurz oder zu leise — bitte erneut versuchen."))
    }

    func testEnrollSuccess_setsDoneAndCallsAddEnrolledSpeaker() async throws {
        let svm = makeSpeakerVM()
        let expectedSpeaker = Speaker(
            id: "abc-123", name: "Thomas",
            currentEmbedding: Array(repeating: 0.1, count: 256),
            isPermanent: true
        )
        let tempURL = makeTempURL()
        let vm = makeViewModel(
            recorderStart: { tempURL },
            recorderStop: { tempURL },
            enroll: { _, _ in expectedSpeaker },
            speakerVM: svm
        )

        let doneExpectation = XCTestExpectation(description: "state == .done")
        vm.$state
            .filter { if case .done = $0 { return true }; return false }
            .first()
            .sink { _ in doneExpectation.fulfill() }
            .store(in: &cancellables)

        vm.startRecording(name: "Thomas")
        vm.stopAndEnroll(name: "Thomas")

        await fulfillment(of: [doneExpectation], timeout: 2.0)
        XCTAssertEqual(vm.state, .done)
        XCTAssertTrue(svm.speakers.contains(where: { $0.id == "abc-123" }))
    }

    func testEnrollFails_diarizerNotReady_setsFailedWithGermanString() async throws {
        let vm = makeViewModel(
            enroll: { _, _ in throw EnrollmentError.diarizerNotReady }
        )

        let failedExpectation = XCTestExpectation(description: "state == .failed(diarizerNotReady)")
        vm.$state
            .compactMap { if case .failed(let msg) = $0 { return msg } else { return nil } }
            .first()
            .sink { _ in failedExpectation.fulfill() }
            .store(in: &cancellables)

        vm.startRecording(name: "Thomas")
        vm.stopAndEnroll(name: "Thomas")

        await fulfillment(of: [failedExpectation], timeout: 2.0)
        XCTAssertEqual(vm.state,
            .failed("Sprecher-Erkennungsmodell nicht bereit. Bitte kurz warten und erneut versuchen."))
    }

    func testEnrollFails_tooShort_setsFailedWithGermanString() async throws {
        let vm = makeViewModel(
            enroll: { _, _ in throw EnrollmentError.tooShort }
        )

        let failedExpectation = XCTestExpectation(description: "state == .failed(tooShort)")
        vm.$state
            .compactMap { if case .failed(let msg) = $0 { return msg } else { return nil } }
            .first()
            .sink { _ in failedExpectation.fulfill() }
            .store(in: &cancellables)

        vm.startRecording(name: "Thomas")
        vm.stopAndEnroll(name: "Thomas")

        await fulfillment(of: [failedExpectation], timeout: 2.0)
        XCTAssertEqual(vm.state,
            .failed("Aufnahme zu kurz — bitte mindestens 5 Sekunden sprechen."))
    }

    func testEnrollFails_tooQuiet_setsFailedWithGermanString() async throws {
        let vm = makeViewModel(
            enroll: { _, _ in throw EnrollmentError.tooQuiet }
        )

        let failedExpectation = XCTestExpectation(description: "state == .failed(tooQuiet)")
        vm.$state
            .compactMap { if case .failed(let msg) = $0 { return msg } else { return nil } }
            .first()
            .sink { _ in failedExpectation.fulfill() }
            .store(in: &cancellables)

        vm.startRecording(name: "Thomas")
        vm.stopAndEnroll(name: "Thomas")

        await fulfillment(of: [failedExpectation], timeout: 2.0)
        XCTAssertEqual(vm.state,
            .failed("Aufnahme zu leise — bitte lauter sprechen oder näher ans Mikrofon."))
    }

    func testReset_returnsToIdleAndCancelsCountdown() async throws {
        // totalSeconds: 1 damit Countdown-Ablauf während des Tests theoretisch möglich wäre
        let vm = makeViewModel(totalSeconds: 1)
        vm.startRecording(name: "Thomas")
        XCTAssertEqual(vm.state, .recording(remainingSeconds: 1))

        vm.reset()
        XCTAssertEqual(vm.state, .idle)

        // 1.5 s warten: Countdown-Task sollte gecancelt sein — kein Übergang zu .processing
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(vm.state, .idle,
            "Countdown-Task wurde nicht gecancelt — state hat sich nach reset() verändert")
    }

    func testDSGVO_tempFileRemovedAfterEnroll() async throws {
        let tempURL = makeTempURL()
        // Dummy-Datei anlegen
        try Data("test-audio".utf8).write(to: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        let vm = makeViewModel(
            recorderStart: { tempURL },
            recorderStop: { tempURL },
            enroll: { _, _ in
                Speaker(id: "dsgvo-test", name: "Anna",
                        currentEmbedding: Array(repeating: 0.2, count: 256),
                        isPermanent: true)
            }
        )

        let doneExpectation = XCTestExpectation(description: "state == .done")
        vm.$state
            .filter { if case .done = $0 { return true }; return false }
            .first()
            .sink { _ in doneExpectation.fulfill() }
            .store(in: &cancellables)

        vm.startRecording(name: "Anna")
        vm.stopAndEnroll(name: "Anna")

        await fulfillment(of: [doneExpectation], timeout: 2.0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
            "Temp-WAV wurde nach Enrollment nicht gelöscht (DSGVO-Verstoß)")
    }

    func testStartRecording_fromNonIdleState_isNoop() {
        let vm = makeViewModel()
        vm.startRecording(name: "Thomas")
        // state ist jetzt .recording — zweiter Aufruf darf nichts tun
        let stateBefore = vm.state
        vm.startRecording(name: "Thomas")
        XCTAssertEqual(vm.state, stateBefore)
    }

    func testCurrentLevel_updatesFromPublisher() {
        let subject = PassthroughSubject<Float, Never>()
        let svm = makeSpeakerVM()
        let vm = EnrollmentViewModel(
            recorderStart: { URL(fileURLWithPath: NSTemporaryDirectory() + "test.wav") },
            recorderStop: { nil },
            levelPublisher: subject.eraseToAnyPublisher(),
            enroll: { _, _ in
                Speaker(id: "x", name: "X",
                        currentEmbedding: [], isPermanent: true)
            },
            speakerVM: svm,
            totalSeconds: 15
        )
        XCTAssertEqual(vm.currentLevel, 0.0)
        subject.send(0.75)
        // RunLoop.main muss einen Zyklus laufen damit sink ausgeführt wird
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(vm.currentLevel, 0.75, accuracy: 0.001)
    }
}
