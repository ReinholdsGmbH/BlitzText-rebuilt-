@testable import BlitzText
import FluidAudio
import XCTest

final class SpeakerProfileStoreTests: XCTestCase {

    private var tmpURL: URL!
    private var store: SpeakerProfileStore!

    override func setUp() {
        super.setUp()
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bt-speaker-test-\(UUID().uuidString).json")
        store = SpeakerProfileStore(url: tmpURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpURL)
        super.tearDown()
    }

    // MARK: - Leer-Laden

    func testLoad_whenFileAbsent_returnsEmpty() {
        XCTAssertEqual(store.loadSpeakers(), [])
    }

    func testLoad_whenFileCorrupt_returnsEmpty() throws {
        try "not valid json".write(to: tmpURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.loadSpeakers(), [])
    }

    // MARK: - Round-Trip

    func testRoundTrip_singleSpeaker_preservesAllFields() throws {
        let embedding = (0..<256).map { Float($0) / 256.0 }
        let speaker = Speaker(
            id: "42",
            name: "Thomas",
            currentEmbedding: embedding,
            duration: 12.5,
            isPermanent: true
        )

        store.saveSpeakers([speaker])
        let loaded = store.loadSpeakers()

        XCTAssertEqual(loaded.count, 1)
        let s = try XCTUnwrap(loaded.first)
        XCTAssertEqual(s.id, "42")
        XCTAssertEqual(s.name, "Thomas")
        XCTAssertEqual(s.duration, 12.5, accuracy: 0.001)
        XCTAssertTrue(s.isPermanent)
        XCTAssertEqual(s.currentEmbedding.count, 256)
    }

    func testRoundTrip_multipleSpeakers_allPreserved() {
        let embed1 = [Float](repeating: 0.1, count: 256)
        let embed2 = [Float](repeating: 0.9, count: 256)
        let speakers = [
            Speaker(id: "1", name: "Speaker 1", currentEmbedding: embed1),
            Speaker(id: "2", name: "Anna", currentEmbedding: embed2, isPermanent: true),
        ]

        store.saveSpeakers(speakers)
        let loaded = store.loadSpeakers()

        XCTAssertEqual(loaded.count, 2)
        let names = Set(loaded.map { $0.name })
        XCTAssertTrue(names.contains("Speaker 1"))
        XCTAssertTrue(names.contains("Anna"))
    }

    func testRoundTrip_emptySpeakers_writesAndLoadsEmpty() {
        store.saveSpeakers([Speaker(id: "1", name: "A", currentEmbedding: [Float](repeating: 0.5, count: 256))])
        store.saveSpeakers([])
        XCTAssertEqual(store.loadSpeakers(), [])
    }

    // MARK: - Atomic write

    func testSave_fileExistsAfterSave() {
        let embed = [Float](repeating: 0.3, count: 256)
        store.saveSpeakers([Speaker(id: "1", name: "Test", currentEmbedding: embed)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpURL.path))
    }

    func testSave_overwritesPreviousContent() {
        let embed = [Float](repeating: 0.5, count: 256)
        store.saveSpeakers([Speaker(id: "1", name: "Erster", currentEmbedding: embed)])
        store.saveSpeakers([Speaker(id: "2", name: "Zweiter", currentEmbedding: embed)])

        let loaded = store.loadSpeakers()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Zweiter")
    }

    // MARK: - Benannte vs. unbenannte Sprecher

    func testBuildSpeakerNames_defaultName_excluded() {
        let embed = [Float](repeating: 0.5, count: 256)
        let speakers = [Speaker(id: "1", name: "Speaker 1", currentEmbedding: embed)]
        let names = SpeakerProfileStore.buildSpeakerNames(from: speakers)
        XCTAssertNil(names["1"], "Standardname 'Speaker 1' soll nicht als benannt gelten")
    }

    func testBuildSpeakerNames_customName_included() {
        let embed = [Float](repeating: 0.5, count: 256)
        let speakers = [Speaker(id: "1", name: "Thomas", currentEmbedding: embed)]
        let names = SpeakerProfileStore.buildSpeakerNames(from: speakers)
        XCTAssertEqual(names["1"], "Thomas")
    }

    func testBuildSpeakerNames_mixedSpeakers_onlyCustomIncluded() {
        let embed = [Float](repeating: 0.5, count: 256)
        let speakers = [
            Speaker(id: "1", name: "Speaker 1", currentEmbedding: embed),
            Speaker(id: "2", name: "Anna", currentEmbedding: embed),
            Speaker(id: "3", name: "Speaker 3", currentEmbedding: embed),
        ]
        let names = SpeakerProfileStore.buildSpeakerNames(from: speakers)
        XCTAssertNil(names["1"])
        XCTAssertEqual(names["2"], "Anna")
        XCTAssertNil(names["3"])
    }
}

// MARK: - Helpers

extension SpeakerProfileStore {
    static func buildSpeakerNames(from speakers: [Speaker]) -> [String: String] {
        ParakeetClient.buildSpeakerNames(from: speakers)
    }
}
