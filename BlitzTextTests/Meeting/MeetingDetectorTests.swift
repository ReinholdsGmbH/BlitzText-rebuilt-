import Testing
import Foundation
@testable import BlitzText

struct MeetingDetectorTests {

    @Test("Die bekannten Konferenz-Apps sind als Meeting-Quelle hinterlegt",
          arguments: [
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.microsoft.teams2.modulehost",
            "com.cisco.webexmeetingsapp"
          ])
    func knownMeetingAppsAreListed(bundleID: String) {
        #expect(MeetingDetector.meetingAppBundleIDs.contains(bundleID))
    }

    @Test("Browser zählen nicht als Meeting-App, sondern nur über den Fenstertitel")
    func browsersAreNotMeetingAppsThemselves() {
        for browser in MeetingDetector.browserBundleIDs {
            #expect(!MeetingDetector.meetingAppBundleIDs.contains(browser))
        }
    }

    @Test("Die übliche Browser-Auswahl ist abgedeckt",
          arguments: ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac"])
    func commonBrowsersCovered(bundleID: String) {
        #expect(MeetingDetector.browserBundleIDs.contains(bundleID))
    }

    @Test("Die Erkennung läuft durch, ohne zu werfen oder zu blockieren")
    func detectionCompletes() {
        let detector = MeetingDetector()
        // Ergebnis haengt von laufenden Apps ab; geprueft wird nur, dass der
        // Accessibility-Walk auch ohne Berechtigung sauber zurueckkommt.
        _ = detector.detectSources()
        _ = detector.isMeetingLikely()
    }
}
