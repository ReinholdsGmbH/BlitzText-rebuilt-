@testable import BlitzText
import XCTest

@MainActor
final class SmokeTests: XCTestCase {
    func test_smoke_targetBuildsAndRuns() {
        XCTAssertTrue(true, "BlitzTextTests target compiles and one test executes")
    }
}
