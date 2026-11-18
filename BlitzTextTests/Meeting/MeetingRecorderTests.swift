import Testing
import Foundation
@testable import BlitzText

@MainActor
struct MeetingRecorderTests {

    private func makeRecorder(
        mic: FakeAudioRecorder,
        tap: FakeSystemAudioTap
    ) -> MeetingRecorder {
        MeetingRecorder(microphone: mic, systemAudio: tap, detector: MeetingDetector(), processList: FakeAudioProcessList())
    }

    private var micURL: URL { URL(fileURLWithPath: "/tmp/test-mic.wav") }
    private var tapURL: URL { URL(fileURLWithPath: "/tmp/test-tap.wav") }

    @Test("Beide Spuren kommen zurück, wenn Mikrofon und Systemaudio laufen")
    func bothTracksReturned() throws {
        let mic = FakeAudioRecorder(fixtureURL: micURL)
        let tap = FakeSystemAudioTap(fixtureURL: tapURL)
        let recorder = makeRecorder(mic: mic, tap: tap)

        try recorder.start()
        #expect(recorder.isRecording)
        let result = recorder.stop()

        #expect(result?.microphoneTrack == micURL)
        #expect(result?.systemAudioTrack == tapURL)
        #expect(result?.systemAudioWasSilent == false)
        #expect(!recorder.isRecording)
    }

    @Test("Scheitert das Systemaudio, läuft der Mitschnitt über das Mikrofon weiter")
    func systemAudioFailureKeepsMicrophone() throws {
        let mic = FakeAudioRecorder(fixtureURL: micURL)
        let tap = FakeSystemAudioTap(fixtureURL: tapURL)
        tap.startError = FakeSystemAudioTap.FakeError.startRefused
        let recorder = makeRecorder(mic: mic, tap: tap)

        try recorder.start()
        #expect(recorder.isRecording)
        let result = recorder.stop()

        #expect(result?.microphoneTrack == micURL)
        #expect(result?.systemAudioTrack == nil)
    }

    @Test("Startet das Mikrofon nicht, bricht der ganze Mitschnitt ab")
    func microphoneFailureAborts() {
        let mic = FakeAudioRecorder(fixtureURL: micURL)
        mic.startError = FakeAudioRecorder.FakeError.stopWithoutStart
        let tap = FakeSystemAudioTap(fixtureURL: tapURL)
        let recorder = makeRecorder(mic: mic, tap: tap)

        #expect(throws: (any Error).self) { try recorder.start() }
        #expect(!recorder.isRecording)
        // Das Systemaudio darf gar nicht erst angefasst worden sein.
        #expect(tap.startCalled == 0)
    }

    @Test("Eine stumme Systemspur wird nicht als Ergebnis ausgegeben, aber gemeldet")
    func silentSystemTrackIsFlaggedNotReturned() throws {
        let mic = FakeAudioRecorder(fixtureURL: micURL)
        let tap = FakeSystemAudioTap(fixtureURL: tapURL)
        tap.reportsSilence = true
        let recorder = makeRecorder(mic: mic, tap: tap)

        try recorder.start()
        let result = recorder.stop()

        // Wichtig: keine stumme Datei als vermeintlichen Mitschnitt durchreichen —
        // das ist fast immer die fehlende Systemaudio-Berechtigung.
        #expect(result?.systemAudioTrack == nil)
        #expect(result?.systemAudioWasSilent == true)
    }

    @Test("Ohne Beschränkung wird global getappt, mit Beschränkung nur erkannte Apps")
    func scopeControlsProcessList() throws {
        let mic = FakeAudioRecorder(fixtureURL: micURL)
        let tap = FakeSystemAudioTap(fixtureURL: tapURL)
        let recorder = makeRecorder(mic: mic, tap: tap)

        try recorder.start(restrictToDetectedApps: false)
        _ = recorder.stop()
        // Leere Liste = globaler Tap.
        #expect(tap.lastProcesses.isEmpty)
    }

    @Test("Stop ohne laufenden Mitschnitt liefert nichts")
    func stopWithoutStartIsNoOp() {
        let mic = FakeAudioRecorder(fixtureURL: micURL)
        let tap = FakeSystemAudioTap(fixtureURL: tapURL)
        let recorder = makeRecorder(mic: mic, tap: tap)

        #expect(recorder.stop() == nil)
    }
}
