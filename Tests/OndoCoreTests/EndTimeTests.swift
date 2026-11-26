import XCTest
@testable import OndoCore

final class EndTimeTests: XCTestCase {
    func testParsesDurationsInMinutes() {
        XCTAssertEqual(EndTime.minutes(from: "90"), 90)
        XCTAssertEqual(EndTime.minutes(from: "90m"), 90)
        XCTAssertEqual(EndTime.minutes(from: "2h"), 120)
        XCTAssertEqual(EndTime.minutes(from: "1h30m"), 90)
        XCTAssertEqual(EndTime.minutes(from: "1h30"), 90)
        XCTAssertEqual(EndTime.minutes(from: " 1H5M "), 65)
        XCTAssertEqual(EndTime.minutes(from: "24h"), 1440)
    }

    func testRejectsDurationsOutsideOneMinuteToOneDay() {
        for text in ["0", "0m", "24h1m", "1441", "-5", "h", "m", "", "abc", "1.5h"] {
            XCTAssertNil(EndTime.minutes(from: text), text)
        }
    }

    func testParsesClockTimes() {
        XCTAssertEqual(EndTime.clock(from: "07:30"), .at(hour: 7, minute: 30))
        XCTAssertEqual(EndTime.clock(from: "7:05"), .at(hour: 7, minute: 5))
        for text in ["24:00", "7:5", "07:60", "0730", "7:30pm"] {
            XCTAssertNil(EndTime.clock(from: text), text)
        }
    }

    func testClockTimeMeansTheNextOccurrence() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 22, minute: 0)))
        let later = try XCTUnwrap(EndTime.at(hour: 23, minute: 15).date(from: now, calendar: calendar))
        XCTAssertEqual(later.timeIntervalSince(now), 75 * 60)
        let tomorrow = try XCTUnwrap(EndTime.at(hour: 7, minute: 30).date(from: now, calendar: calendar))
        XCTAssertEqual(tomorrow.timeIntervalSince(now), 9.5 * 3600)
    }

    func testDurationAndUnlimited() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(EndTime.after(minutes: 90).date(from: now), now.addingTimeInterval(5400))
        XCTAssertNil(EndTime.unlimited.date(from: now))
    }
}
