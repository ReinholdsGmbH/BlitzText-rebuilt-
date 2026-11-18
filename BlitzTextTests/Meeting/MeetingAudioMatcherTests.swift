import Testing
@testable import BlitzText

struct MeetingAudioMatcherTests {

    private func source(_ pid: pid_t, _ bundle: String, _ kind: MeetingSource.Kind = .nativeApp) -> MeetingSource {
        MeetingSource(id: pid, kind: kind, bundleIdentifier: bundle, displayName: bundle, evidence: nil)
    }

    private func process(_ pid: pid_t, _ bundle: String, input: Bool = false) -> AudioProcessInfo {
        AudioProcessInfo(pid: pid, bundleIdentifier: bundle, isRunningInput: input)
    }

    @Test("Tap umfasst Hilfsprozesse der App, aber keine fremden Apps")
    func tapIncludesHelpers() {
        let pids = MeetingAudioMatcher.tapPIDs(
            for: [source(100, "com.google.Chrome", .browserTab), source(200, "com.microsoft.teams2")],
            in: [
                process(101, "com.google.Chrome.helper"),
                process(201, "com.microsoft.teams2.modulehost"),
                process(300, "com.spotify.client"),
                process(400, "com.google.Chromecast.fake")
            ]
        )
        #expect(pids == [100, 101, 200, 201])
    }

    @Test("Zoom-Hilfsprozesse mit anderer Bundle-ID gehören dazu")
    func zoomFamily() {
        let pids = MeetingAudioMatcher.tapPIDs(for: [source(10, "us.zoom.xos")], in: [process(11, "us.zoom.CptHost")])
        #expect(pids == [10, 11])
    }

    @Test("Native App zählt nur als Meeting, wenn ihre Familie das Mikrofon nutzt")
    func nativeNeedsMicrophone() {
        let teams = source(200, "com.microsoft.teams2")
        let idle = MeetingAudioMatcher.activeSources([teams], in: [process(201, "com.microsoft.teams2.modulehost")])
        let talking = MeetingAudioMatcher.activeSources([teams], in: [process(201, "com.microsoft.teams2.modulehost", input: true)])
        #expect(idle.isEmpty)
        #expect(talking == [teams])
    }

    @Test("Mikrofon einer fremden App macht kein Teams-Meeting")
    func foreignMicrophoneDoesNotCount() {
        let active = MeetingAudioMatcher.activeSources(
            [source(200, "com.microsoft.teams2")],
            in: [process(500, "com.apple.VoiceMemos", input: true)]
        )
        #expect(active.isEmpty)
    }

    @Test("Browser-Quellen gelten immer, ihr Titel belegt das Mikrofon bereits")
    func browserAlwaysCounts() {
        let chrome = source(100, "com.google.Chrome", .browserTab)
        #expect(MeetingAudioMatcher.activeSources([chrome], in: []) == [chrome])
    }
}
