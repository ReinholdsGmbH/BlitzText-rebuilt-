import Foundation
import FluidAudio

/// Observable Wrapper um `SpeakerProfileStore`. Hält die Sprecher-Liste für die
/// Settings-UI aktuell und verfolgt die Sprecher-IDs der letzten Transkriptions-Session.
@MainActor
final class SpeakerProfileViewModel: ObservableObject {

    @Published private(set) var speakers: [Speaker] = []

    /// IDs der Sprecher, die in der letzten Diarization-Session aktiv waren.
    /// Wird genutzt, um unbekannte Sprecher in der UI benennen zu können (SPK-06).
    @Published private(set) var lastTranscriptSpeakerIDs: [String] = []

    private let store: SpeakerProfileStore

    init(store: SpeakerProfileStore) {
        self.store = store
        self.speakers = store.loadSpeakers()
        store.onSessionSaved = { [weak self] updatedSpeakers, sessionIDs in
            Task { @MainActor [weak self] in
                self?.speakers = updatedSpeakers
                self?.lastTranscriptSpeakerIDs = sessionIDs
            }
        }
    }

    // MARK: - CRUD

    func rename(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[idx].name = trimmed
        store.saveSpeakers(speakers)
    }

    func delete(id: String) {
        speakers.removeAll { $0.id == id }
        store.saveSpeakers(speakers)
        lastTranscriptSpeakerIDs.removeAll { $0 == id }
    }

    func togglePermanent(id: String) {
        guard let idx = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[idx].isPermanent.toggle()
        store.saveSpeakers(speakers)
    }

    /// Führt `sourceID` in `intoID` zusammen. Der Ziel-Sprecher behält seinen Namen.
    func merge(sourceID: String, intoID: String) {
        guard sourceID != intoID,
              let srcIdx = speakers.firstIndex(where: { $0.id == sourceID }),
              let dstIdx = speakers.firstIndex(where: { $0.id == intoID }) else { return }
        var merged = speakers[dstIdx]
        merged.mergeWith(speakers[srcIdx])
        speakers[dstIdx] = merged
        speakers.remove(at: srcIdx)
        store.saveSpeakers(speakers)
        lastTranscriptSpeakerIDs.removeAll { $0 == sourceID }
    }

    /// Weist einem bisher unbekannten Sprecher einen Namen zu und setzt ihn auf permanent (SPK-06).
    func assignName(to id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[idx].name = trimmed
        speakers[idx].isPermanent = true
        store.saveSpeakers(speakers)
    }

    // MARK: - Helpers

    /// True, wenn der Sprecher noch den FluidAudio-Standardnamen trägt (= unbekannt).
    func isUnnamed(_ speaker: Speaker) -> Bool {
        speaker.name == "Speaker \(speaker.id)" || speaker.name == speaker.id
    }

    /// Sprecher aus der letzten Session, die noch keinen benutzerdefinierten Namen haben.
    var unnamedFromLastTranscript: [Speaker] {
        lastTranscriptSpeakerIDs.compactMap { id in
            speakers.first { $0.id == id && isUnnamed($0) }
        }
    }
}
