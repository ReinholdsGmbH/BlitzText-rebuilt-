@testable import BlitzText
import FluidAudio
import XCTest
import Combine

@MainActor
final class SpeakerProfileViewModelTests: XCTestCase {

    private var tmpURL: URL!
    private var store: SpeakerProfileStore!
    private var vm: SpeakerProfileViewModel!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bt-spvm-test-\(UUID().uuidString).json")
        store = SpeakerProfileStore(url: tmpURL)
        vm = SpeakerProfileViewModel(store: store)
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tmpURL)
    }

    // MARK: - Initialisierung

    func testInit_loadsExistingProfiles() {
        let speaker = makeSpeaker(id: "1", name: "Thomas")
        store.saveSpeakers([speaker])
        let freshVM = SpeakerProfileViewModel(store: store)
        XCTAssertEqual(freshVM.speakers.count, 1)
        XCTAssertEqual(freshVM.speakers.first?.name, "Thomas")
    }

    func testInit_emptyWhenNoFile() {
        XCTAssertTrue(vm.speakers.isEmpty)
    }

    // MARK: - Umbenennen

    func testRename_updatesSpeakerNameAndSavesToDisk() {
        store.saveSpeakers([makeSpeaker(id: "1", name: "Speaker 1")])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.rename(id: "1", name: "Thomas")

        XCTAssertEqual(freshVM.speakers.first?.name, "Thomas")
        XCTAssertEqual(store.loadSpeakers().first?.name, "Thomas")
    }

    func testRename_emptyName_isIgnored() {
        store.saveSpeakers([makeSpeaker(id: "1", name: "Thomas")])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.rename(id: "1", name: "   ")

        XCTAssertEqual(freshVM.speakers.first?.name, "Thomas")
    }

    func testRename_unknownID_isNoOp() {
        store.saveSpeakers([makeSpeaker(id: "1", name: "Thomas")])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.rename(id: "99", name: "Niemand")

        XCTAssertEqual(freshVM.speakers.first?.name, "Thomas")
    }

    // MARK: - Löschen

    func testDelete_removesSpeakerFromMemoryAndDisk() {
        store.saveSpeakers([makeSpeaker(id: "1", name: "Thomas")])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.delete(id: "1")

        XCTAssertTrue(freshVM.speakers.isEmpty)
        XCTAssertTrue(store.loadSpeakers().isEmpty)
    }

    func testDelete_removesFromLastTranscriptIDs() async {
        let s = makeSpeaker(id: "1", name: "Speaker 1")
        store.saveSpeakers([s])
        let freshVM = SpeakerProfileViewModel(store: store)

        let expectation = XCTestExpectation(description: "Session gesetzt")
        var fulfilled = false
        freshVM.$lastTranscriptSpeakerIDs.dropFirst().sink { ids in
            if ids.contains("1") && !fulfilled { fulfilled = true; expectation.fulfill() }
        }.store(in: &cancellables)
        store.onSessionSaved?([s], ["1"])
        await fulfillment(of: [expectation], timeout: 1.0)

        freshVM.delete(id: "1")
        XCTAssertFalse(freshVM.lastTranscriptSpeakerIDs.contains("1"))
    }

    // MARK: - Permanent-Toggle

    func testTogglePermanent_setsFlag() {
        store.saveSpeakers([makeSpeaker(id: "1", name: "Thomas", permanent: false)])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.togglePermanent(id: "1")

        XCTAssertTrue(freshVM.speakers.first?.isPermanent == true)
        XCTAssertTrue(store.loadSpeakers().first?.isPermanent == true)
    }

    func testTogglePermanent_unsetsFlag() {
        store.saveSpeakers([makeSpeaker(id: "1", name: "Thomas", permanent: true)])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.togglePermanent(id: "1")

        XCTAssertFalse(freshVM.speakers.first?.isPermanent == true)
    }

    // MARK: - Zusammenführen

    func testMerge_removesSpeakerAndMergesDuration() {
        store.saveSpeakers([
            makeSpeaker(id: "1", name: "Thomas"),
            makeSpeaker(id: "2", name: "Maria")
        ])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.merge(sourceID: "1", intoID: "2")

        XCTAssertEqual(freshVM.speakers.count, 1)
        XCTAssertEqual(freshVM.speakers.first?.id, "2")
    }

    func testMerge_sameID_isNoOp() {
        store.saveSpeakers([makeSpeaker(id: "1", name: "Thomas")])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.merge(sourceID: "1", intoID: "1")

        XCTAssertEqual(freshVM.speakers.count, 1)
    }

    func testMerge_savesToDisk() {
        store.saveSpeakers([
            makeSpeaker(id: "1", name: "Thomas"),
            makeSpeaker(id: "2", name: "Maria")
        ])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.merge(sourceID: "1", intoID: "2")

        XCTAssertEqual(store.loadSpeakers().count, 1)
    }

    // MARK: - Name zuweisen (SPK-06)

    func testAssignName_setsNameAndMarksPermanent() {
        store.saveSpeakers([makeSpeaker(id: "1", name: "Speaker 1")])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.assignName(to: "1", name: "Thomas")

        XCTAssertEqual(freshVM.speakers.first?.name, "Thomas")
        XCTAssertTrue(freshVM.speakers.first?.isPermanent == true)
        let reloaded = store.loadSpeakers()
        XCTAssertEqual(reloaded.first?.name, "Thomas")
        XCTAssertTrue(reloaded.first?.isPermanent == true)
    }

    func testAssignName_emptyName_isIgnored() {
        store.saveSpeakers([makeSpeaker(id: "1", name: "Speaker 1")])
        let freshVM = SpeakerProfileViewModel(store: store)

        freshVM.assignName(to: "1", name: "  ")

        XCTAssertFalse(freshVM.speakers.first?.isPermanent == true)
        XCTAssertEqual(freshVM.speakers.first?.name, "Speaker 1")
    }

    // MARK: - isUnnamed

    func testIsUnnamed_defaultName_returnsTrue() {
        let s = makeSpeaker(id: "42", name: "Speaker 42")
        XCTAssertTrue(vm.isUnnamed(s))
    }

    func testIsUnnamed_idAsName_returnsTrue() {
        let s = makeSpeaker(id: "42", name: "42")
        XCTAssertTrue(vm.isUnnamed(s))
    }

    func testIsUnnamed_customName_returnsFalse() {
        let s = makeSpeaker(id: "42", name: "Thomas")
        XCTAssertFalse(vm.isUnnamed(s))
    }

    // MARK: - Session-Callback (SPK-06)

    func testOnSessionSaved_updatesLastTranscriptIDs() async {
        let s = makeSpeaker(id: "1", name: "Speaker 1")
        store.saveSpeakers([s])
        let freshVM = SpeakerProfileViewModel(store: store)

        let expectation = XCTestExpectation(description: "lastTranscriptSpeakerIDs aktualisiert")
        var fulfilled = false
        freshVM.$lastTranscriptSpeakerIDs.dropFirst().sink { ids in
            if ids == ["1"] && !fulfilled { fulfilled = true; expectation.fulfill() }
        }.store(in: &cancellables)

        store.onSessionSaved?([s], ["1"])

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(freshVM.lastTranscriptSpeakerIDs, ["1"])
    }

    func testOnSessionSaved_updatesSpeakersList() async {
        let s1 = makeSpeaker(id: "1", name: "Thomas")
        let s2 = makeSpeaker(id: "2", name: "Maria")
        let freshVM = SpeakerProfileViewModel(store: store)

        let expectation = XCTestExpectation(description: "Speakers aktualisiert")
        var fulfilled = false
        freshVM.$speakers.dropFirst().sink { speakers in
            if speakers.count == 2 && !fulfilled { fulfilled = true; expectation.fulfill() }
        }.store(in: &cancellables)

        store.onSessionSaved?([s1, s2], ["1", "2"])

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(freshVM.speakers.count, 2)
    }

    // MARK: - unnamedFromLastTranscript

    func testUnnamedFromLastTranscript_returnsOnlyUnnamedInSession() async {
        let unnamed = makeSpeaker(id: "1", name: "Speaker 1")
        let named   = makeSpeaker(id: "2", name: "Thomas")
        let freshVM = SpeakerProfileViewModel(store: store)

        let expectation = XCTestExpectation(description: "Session gesetzt")
        var fulfilled = false
        freshVM.$lastTranscriptSpeakerIDs.dropFirst().sink { _ in
            if !fulfilled { fulfilled = true; expectation.fulfill() }
        }.store(in: &cancellables)

        store.onSessionSaved?([unnamed, named], ["1", "2"])

        await fulfillment(of: [expectation], timeout: 1.0)
        let result = freshVM.unnamedFromLastTranscript
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "1")
    }

    func testUnnamedFromLastTranscript_emptyWhenNoSession() {
        XCTAssertTrue(vm.unnamedFromLastTranscript.isEmpty)
    }

    // MARK: - Enrollment hinzufügen (SPK-08)

    func testAddEnrolledSpeaker_appendsAndSaves() throws {
        // leerer Store, neuen Speaker enrollen
        let embedding = [Float](repeating: 0.1, count: 256)
        var speaker = Speaker(id: "enroll-1", name: "Thomas", currentEmbedding: embedding)
        speaker.isPermanent = true

        vm.addEnrolledSpeaker(speaker)

        XCTAssertEqual(vm.speakers.count, 1)
        XCTAssertEqual(vm.speakers[0].id, "enroll-1")
        XCTAssertTrue(vm.speakers[0].isPermanent)

        // Auf Disk persistiert
        let reloaded = SpeakerProfileStore(url: tmpURL).loadSpeakers()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.id, "enroll-1")
        XCTAssertTrue(reloaded.first?.isPermanent == true)
    }

    func testAddEnrolledSpeaker_replacesExistingId() {
        // Bestehenden Speaker mit id="dup" vorbereiten
        let existingSpeaker = makeSpeaker(id: "dup", name: "Alt", permanent: false)
        store.saveSpeakers([existingSpeaker])
        let freshVM = SpeakerProfileViewModel(store: store)

        // Speaker mit gleicher ID aber neuem Namen enrollen
        var updated = Speaker(id: "dup", name: "Neu", currentEmbedding: [Float](repeating: 0.5, count: 256))
        updated.isPermanent = true

        freshVM.addEnrolledSpeaker(updated)

        // kein Duplikat — nur ein Eintrag
        XCTAssertEqual(freshVM.speakers.count, 1)
        XCTAssertEqual(freshVM.speakers[0].name, "Neu")
        XCTAssertTrue(freshVM.speakers[0].isPermanent)
    }

    // MARK: - Hilfsmethoden

    private func makeSpeaker(id: String, name: String, permanent: Bool = false) -> Speaker {
        var s = Speaker(
            id: id,
            name: name,
            currentEmbedding: [Float](repeating: 0.1, count: 256)
        )
        s.isPermanent = permanent
        return s
    }
}
