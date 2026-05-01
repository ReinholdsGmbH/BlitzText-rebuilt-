@testable import BlitzText
import XCTest

final class ETAEstimatorTests: XCTestCase {

    func testFirstTick_returnsNil_becauseNotEnoughSamples() {
        var est = ETAEstimator(windowSeconds: 5)
        let now = Date()
        XCTAssertNil(est.tick(fraction: 0.1, now: now))
    }

    func testTwoTicksWithinHalfSecond_returnsNil_becauseElapsedTooShort() {
        var est = ETAEstimator(windowSeconds: 5)
        let t0 = Date()
        _ = est.tick(fraction: 0.1, now: t0)
        // < 0.5 s elapsed
        XCTAssertNil(est.tick(fraction: 0.15, now: t0.addingTimeInterval(0.3)))
    }

    func testSteadyProgress_returnsExpectedSeconds() {
        var est = ETAEstimator(windowSeconds: 5)
        let t0 = Date()
        // 0.0 → 0.5 über 5 s → rate = 0.1/s, remaining = 0.5, eta ≈ 5.0
        _ = est.tick(fraction: 0.0, now: t0)
        _ = est.tick(fraction: 0.1, now: t0.addingTimeInterval(1))
        _ = est.tick(fraction: 0.2, now: t0.addingTimeInterval(2))
        _ = est.tick(fraction: 0.3, now: t0.addingTimeInterval(3))
        _ = est.tick(fraction: 0.4, now: t0.addingTimeInterval(4))
        let eta = est.tick(fraction: 0.5, now: t0.addingTimeInterval(5))
        XCTAssertNotNil(eta)
        XCTAssertEqual(eta!, 5.0, accuracy: 1.5,
            "Erwartet ~5 s Restzeit bei 0.1/s rate und 0.5 verbleibend")
    }

    func testReset_clearsSamples_nextTickReturnsNil() {
        var est = ETAEstimator(windowSeconds: 5)
        let t0 = Date()
        _ = est.tick(fraction: 0.1, now: t0)
        _ = est.tick(fraction: 0.2, now: t0.addingTimeInterval(1))
        est.reset()
        XCTAssertNil(est.tick(fraction: 0.3, now: t0.addingTimeInterval(2)))
    }

    func testStagnatedProgress_returnsNil_whenDeltaBelowThreshold() {
        var est = ETAEstimator(windowSeconds: 5)
        let t0 = Date()
        _ = est.tick(fraction: 0.5, now: t0)
        _ = est.tick(fraction: 0.5, now: t0.addingTimeInterval(1))
        // Compile-Phase-Stagnation: progressDelta ≈ 0 < 0.001 → nil
        XCTAssertNil(est.tick(fraction: 0.5005, now: t0.addingTimeInterval(2)))
    }
}
