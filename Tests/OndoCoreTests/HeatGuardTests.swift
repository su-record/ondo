import XCTest
@testable import OndoCore

final class HeatGuardTests: XCTestCase {
    let limit = 85.0
    let sustain: TimeInterval = 60

    /// Feeds `celsius` every 2 seconds for `seconds` and returns the events in order.
    private func feed(_ guard_: inout HeatGuard, _ celsius: Double, for seconds: Int) -> [HeatGuard.Event] {
        stride(from: 0, to: seconds, by: 2).compactMap { _ in
            guard_.update(celsius: celsius, limit: limit, sustain: sustain, elapsed: 2)
        }
    }

    func testWarnsAfterSustainAndStopsAfterTwiceSustain() {
        var g = HeatGuard()
        XCTAssertEqual(feed(&g, 90, for: 58), [])
        XCTAssertEqual(feed(&g, 90, for: 2), [.warn])
        XCTAssertEqual(g.secondsUntilStop(sustain: sustain), 60)
        XCTAssertEqual(feed(&g, 90, for: 58), [])
        XCTAssertEqual(feed(&g, 90, for: 2), [.stop])
    }

    func testReadingAtTheLimitCountsAsHot() {
        var g = HeatGuard()
        XCTAssertEqual(feed(&g, 85, for: 60), [.warn])
    }

    func testBandBetweenLimitAndHysteresisPausesTheCount() {
        var g = HeatGuard()
        _ = feed(&g, 90, for: 40)
        XCTAssertEqual(feed(&g, 83, for: 100), [], "83°C is inside the 3°C band: no reset, no progress")
        XCTAssertEqual(g.hotSeconds, 40)
        XCTAssertEqual(feed(&g, 90, for: 20), [.warn])
    }

    func testCoolingBelowTheBandResetsAndReportsCooledOnlyAfterAWarning() {
        var g = HeatGuard()
        _ = feed(&g, 90, for: 40)
        XCTAssertEqual(feed(&g, 81.9, for: 2), [], "not warned yet, so no cooled event")
        XCTAssertEqual(g.hotSeconds, 0)
        _ = feed(&g, 90, for: 60)
        XCTAssertEqual(feed(&g, 81.9, for: 2), [.cooled])
        XCTAssertFalse(g.warned)
    }

    func testUnreadableTemperatureChangesNothing() {
        var g = HeatGuard()
        _ = feed(&g, 90, for: 30)
        XCTAssertNil(g.update(celsius: nil, limit: limit, sustain: sustain, elapsed: 600))
        XCTAssertEqual(g.hotSeconds, 30)
    }
}
