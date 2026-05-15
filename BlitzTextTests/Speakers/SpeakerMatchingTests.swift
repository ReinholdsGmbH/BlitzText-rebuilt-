@testable import BlitzText
import FluidAudio
import XCTest

/// TEST-03: Sprecher-Profil-Matching — Cosine-Similarity-Threshold, EMA-Update,
/// Persistierungs-Round-Trip mit Namensauflösung.
final class SpeakerMatchingTests: XCTestCase {

    // MARK: - Hilfsmethoden

    /// Erzeugt einen normierten Dummy-Embedding-Vektor der Dimension 256.
    /// `angle` dreht den Vektor im ersten 2D-Unterraum; alle anderen Komponenten = 0.
    private func embedding(angle: Double = 0) -> [Float] {
        var v = [Float](repeating: 0, count: 256)
        v[0] = Float(cos(angle))
        v[1] = Float(sin(angle))
        return v
    }

    // MARK: - Cosine-Similarity-Threshold

    func testAssignSpeaker_closeSpeaker_matchesExisting() async {
        let mgr = SpeakerManager(speakerThreshold: 0.65)
        let base = embedding(angle: 0)
        let close = embedding(angle: 0.1) // sehr nah am ersten

        // Ersten Sprecher anlegen
        _ = await mgr.assignSpeaker(base, speechDuration: 2.0)
        let before = await mgr.speakerCount
        XCTAssertEqual(before, 1)

        // Sehr ähnliches Embedding → gleicher Sprecher
        _ = await mgr.assignSpeaker(close, speechDuration: 2.0)
        let after = await mgr.speakerCount
        XCTAssertEqual(after, 1, "Naher Sprecher muss existierendem Profil zugeordnet werden")
    }

    func testAssignSpeaker_distantSpeaker_createsNew() async {
        let mgr = SpeakerManager(speakerThreshold: 0.65)
        let base = embedding(angle: 0)
        let far = embedding(angle: .pi / 2) // 90° → Cosine-Distanz ≈ 1.0

        _ = await mgr.assignSpeaker(base, speechDuration: 2.0)
        _ = await mgr.assignSpeaker(far, speechDuration: 2.0)
        let count = await mgr.speakerCount
        XCTAssertEqual(count, 2, "Weit entfernter Sprecher muss neues Profil erzeugen")
    }

    func testAssignSpeaker_belowMinDuration_returnsNil() async {
        // minSpeechDuration = 1.0 s (Standard). Bei 0.5 s + kein bestehender Sprecher → nil.
        let mgr = SpeakerManager(speakerThreshold: 0.65, minSpeechDuration: 1.0)
        let result = await mgr.assignSpeaker(embedding(), speechDuration: 0.5)
        XCTAssertNil(result, "Segment unter minSpeechDuration darf kein neues Profil anlegen")
    }

    func testFindSpeaker_withinThreshold_returnsId() async {
        let mgr = SpeakerManager(speakerThreshold: 0.65)
        _ = await mgr.assignSpeaker(embedding(angle: 0), speechDuration: 2.0)
        let ids = await mgr.speakerIds
        let id = ids.first!

        let (foundId, distance) = await mgr.findSpeaker(with: embedding(angle: 0.05))
        XCTAssertEqual(foundId, id)
        XCTAssertLessThan(distance, 0.65)
    }

    func testFindSpeaker_outsideThreshold_returnsNilId() async {
        let mgr = SpeakerManager(speakerThreshold: 0.65)
        _ = await mgr.assignSpeaker(embedding(angle: 0), speechDuration: 2.0)

        let (foundId, _) = await mgr.findSpeaker(with: embedding(angle: .pi / 2))
        XCTAssertNil(foundId)
    }

    // MARK: - EMA-Update

    func testUpdateMainEmbedding_blendsMovesTorwardNewEmbedding() async {
        let mgr = SpeakerManager(speakerThreshold: 0.65, embeddingThreshold: 0.45)
        let base = embedding(angle: 0)
        let update = embedding(angle: 0.2) // nah genug für EMA-Update (Cosine-Dist ≈ 0.02)

        _ = await mgr.assignSpeaker(base, speechDuration: 2.0)
        let ids = await mgr.speakerIds
        let id = ids.first!

        let originalEmbedding = await mgr.getSpeaker(for: id)!.currentEmbedding
        _ = await mgr.assignSpeaker(update, speechDuration: 2.0)
        let updatedEmbedding = await mgr.getSpeaker(for: id)!.currentEmbedding

        XCTAssertEqual(updatedEmbedding.count, 256)

        // EMA-Richtungstest: nach alpha=0.9-Blend muss updated näher an `update` sein als
        // das ursprüngliche `base` — beweist, dass EMA in die richtige Richtung bewegt.
        let distOriginalToUpdate = SpeakerUtilities.cosineDistance(originalEmbedding, update)
        let distUpdatedToUpdate = SpeakerUtilities.cosineDistance(updatedEmbedding, update)
        XCTAssertLessThan(distUpdatedToUpdate, distOriginalToUpdate,
            "EMA muss Embedding Richtung neue Probe bewegen")
        // Nicht vollständig ersetzt (alpha < 1.0)
        XCTAssertGreaterThan(distUpdatedToUpdate, 0,
            "EMA darf Embedding nicht vollständig durch neue Probe ersetzen")
    }

    func testUpdateCount_incrementsAfterUpdate() async {
        let mgr = SpeakerManager(speakerThreshold: 0.65, embeddingThreshold: 0.45)
        _ = await mgr.assignSpeaker(embedding(angle: 0), speechDuration: 2.0)
        let ids = await mgr.speakerIds
        let id = ids.first!

        let before = await mgr.getSpeaker(for: id)!.updateCount
        _ = await mgr.assignSpeaker(embedding(angle: 0.1), speechDuration: 2.0)
        let after = await mgr.getSpeaker(for: id)!.updateCount
        XCTAssertGreaterThan(after, before, "updateCount muss nach Match-Update steigen")
    }

    // MARK: - Persistierungs-Round-Trip mit Namensauflösung

    func testApplyDiarization_unnamedSpeaker_formatsAsSprecher() {
        let asr = makeASRResult(tokens: [
            ("Hallo", 0.0, 0.5),
            (" Welt", 0.5, 1.0),
        ])
        let segs = [TimedSpeakerSegment(speakerId: "1", embedding: [], startTimeSeconds: 0, endTimeSeconds: 1, qualityScore: 1)]

        let result = ParakeetClient.applyDiarization(asr: asr, segments: segs)
        XCTAssertTrue(result.hasPrefix("Sprecher 1:"), "Unbenannter Sprecher muss als 'Sprecher N:' erscheinen, war: \(result)")
    }

    func testApplyDiarization_namedSpeaker_formatsWithName() {
        let asr = makeASRResult(tokens: [
            ("Hallo", 0.0, 0.5),
            (" Welt", 0.5, 1.0),
        ])
        let segs = [TimedSpeakerSegment(speakerId: "1", embedding: [], startTimeSeconds: 0, endTimeSeconds: 1, qualityScore: 1)]

        let result = ParakeetClient.applyDiarization(asr: asr, segments: segs, speakerNames: ["1": "Thomas"])
        XCTAssertTrue(result.hasPrefix("Thomas:"), "Benannter Sprecher muss mit Name erscheinen, war: \(result)")
    }

    func testApplyDiarization_mixedSpeakers_correctLabels() {
        let asr = makeASRResult(tokens: [
            ("Hallo", 0.0, 0.5),
            (" ich", 0.5, 1.0),
            (" und", 1.5, 2.0),
            (" du", 2.0, 2.5),
        ])
        let segs = [
            TimedSpeakerSegment(speakerId: "1", embedding: [], startTimeSeconds: 0, endTimeSeconds: 1, qualityScore: 1),
            TimedSpeakerSegment(speakerId: "2", embedding: [], startTimeSeconds: 1.5, endTimeSeconds: 2.5, qualityScore: 1),
        ]

        let result = ParakeetClient.applyDiarization(asr: asr, segments: segs, speakerNames: ["1": "Anna"])
        XCTAssertTrue(result.contains("Anna:"), "Benannter Sprecher 1 muss als 'Anna:' erscheinen")
        XCTAssertTrue(result.contains("Sprecher 1:"), "Unbenannter Sprecher 2 muss als 'Sprecher 1:' erscheinen")
    }

    // MARK: - mergePersistedNames (SPK-06 Fix)

    func testMergePersistedNames_overridesDefaultName() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bt-merge-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let store = SpeakerProfileStore(url: tmpURL)
        // User hat Sprecher in der UI umbenannt → Disk-Name ist "Thomas"
        var persisted = Speaker(id: "1", name: "Thomas", currentEmbedding: embedding(angle: 0))
        persisted.isPermanent = true
        store.saveSpeakers([persisted])

        // Runtime-Diarizer kennt noch den alten Namen "Speaker 1"
        let runtime = Speaker(id: "1", name: "Speaker 1", currentEmbedding: embedding(angle: 0.1))

        let merged = ParakeetClient.mergePersistedNames([runtime], from: store)

        XCTAssertEqual(merged.first?.name, "Thomas", "Persistierter Name muss Runtime-Name überschreiben")
        XCTAssertTrue(merged.first?.isPermanent == true, "isPermanent muss vom Store übernommen werden")
    }

    func testMergePersistedNames_keepesDefaultNameIfNotRenamed() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bt-merge-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let store = SpeakerProfileStore(url: tmpURL)
        let persisted = Speaker(id: "1", name: "Speaker 1", currentEmbedding: embedding())
        store.saveSpeakers([persisted])

        let runtime = Speaker(id: "1", name: "Speaker 1", currentEmbedding: embedding(angle: 0.1))
        let merged = ParakeetClient.mergePersistedNames([runtime], from: store)

        XCTAssertEqual(merged.first?.name, "Speaker 1", "Unbenannte Sprecher sollen nicht verändert werden")
    }

    func testMergePersistedNames_nilStore_returnsRuntime() {
        let runtime = Speaker(id: "1", name: "Speaker 1", currentEmbedding: embedding())
        let merged = ParakeetClient.mergePersistedNames([runtime], from: nil)
        XCTAssertEqual(merged.first?.name, "Speaker 1")
    }

    func testPersistenceRoundTrip_namedSpeakerSurvivedSaveAndLoad() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bt-match-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let embed = (0..<256).map { Float($0) / 256.0 }
        let original = Speaker(id: "3", name: "Klaus", currentEmbedding: embed, isPermanent: true)

        let store = SpeakerProfileStore(url: tmpURL)
        store.saveSpeakers([original])

        let loaded = store.loadSpeakers()
        let names = ParakeetClient.buildSpeakerNames(from: loaded)

        XCTAssertEqual(names["3"], "Klaus", "Nach Persistierungs-Round-Trip muss Name erhalten bleiben")
    }
}

// MARK: - Test-Helpers

private func makeASRResult(tokens: [(String, Double, Double)]) -> ASRResult {
    let timings = tokens.map { TokenTiming(token: $0.0, tokenId: 0, startTime: $0.1, endTime: $0.2, confidence: 1.0) }
    let text = tokens.map { $0.0 }.joined()
    return ASRResult(
        text: text,
        confidence: 1.0,
        duration: tokens.last?.2 ?? 0,
        processingTime: 0,
        tokenTimings: timings
    )
}
