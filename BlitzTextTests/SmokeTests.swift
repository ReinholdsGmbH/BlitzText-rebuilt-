@testable import BlitzText
import XCTest

@MainActor
final class SmokeTests: XCTestCase {
    func test_smoke_targetBuildsAndRuns() {
        XCTAssertTrue(true, "BlitzTextTests target compiles and one test executes")
    }

    func test_smoke_canConstructFakes() {
        let fakeT = FakeTranscriptionService(.success("ok"))
        let fakeR = FakeRewriter(.success("ok"))
        let fakeRec = FakeAudioRecorder(fixtureURL: URL(fileURLWithPath: "/tmp/fake.wav"))
        XCTAssertEqual(fakeT.callCount, 0)
        XCTAssertEqual(fakeR.callCount, 0)
        XCTAssertEqual(fakeRec.startCalled, 0)
    }
}
