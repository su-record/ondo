import XCTest
@testable import OndoCore

final class ProtectionTests: XCTestCase {
    let settings = Settings()
    let charger = PowerState(onAC: true, batteryPercent: 80)
    let battery = PowerState(onAC: false, batteryPercent: 80)

    func testUnplugStopsOnlyOnAChangeFromChargerToBattery() {
        XCTAssertEqual(Protection.powerStop(previous: charger, current: battery, settings: settings), .unplugged)
        XCTAssertNil(Protection.powerStop(previous: battery, current: battery, settings: settings), "started on battery")
        XCTAssertNil(Protection.powerStop(previous: nil, current: battery, settings: settings))
        var noUnplugRule = settings
        noUnplugRule.stopOnUnplug = false
        XCTAssertNil(Protection.powerStop(previous: charger, current: battery, settings: noUnplugRule))
    }

    func testBatteryFloorAppliesOnlyOnBattery() {
        let low = PowerState(onAC: false, batteryPercent: 19)
        XCTAssertEqual(Protection.powerStop(previous: low, current: low, settings: settings), .batteryLow)
        XCTAssertNil(Protection.powerStop(previous: low, current: PowerState(onAC: false, batteryPercent: 20), settings: settings))
        XCTAssertNil(Protection.powerStop(previous: nil, current: PowerState(onAC: true, batteryPercent: 5), settings: settings), "charging")
        XCTAssertNil(Protection.powerStop(previous: nil, current: PowerState(onAC: true, batteryPercent: nil), settings: settings), "no battery")
    }

    func testStartIsRefusedWhileHotOrLow() {
        XCTAssertEqual(Protection.startRefusal(cpu: 85, battery: 30, power: charger, settings: settings), .cpuHot)
        XCTAssertEqual(Protection.startRefusal(cpu: 60, battery: 45, power: charger, settings: settings), .batteryHot)
        XCTAssertEqual(Protection.startRefusal(cpu: 60, battery: 30, power: PowerState(onAC: false, batteryPercent: 10), settings: settings), .batteryLow)
        XCTAssertNil(Protection.startRefusal(cpu: 84.9, battery: 44.9, power: charger, settings: settings))
        XCTAssertNil(Protection.startRefusal(cpu: nil, battery: nil, power: charger, settings: settings), "unreadable sensors do not block")
    }

    func testResumeNeedsBothTemperaturesWellBelowTheirLimits() {
        XCTAssertTrue(Protection.cooledEnoughToResume(cpu: 75, battery: 35, settings: settings))
        XCTAssertFalse(Protection.cooledEnoughToResume(cpu: 75.1, battery: 30, settings: settings))
        XCTAssertFalse(Protection.cooledEnoughToResume(cpu: 60, battery: 35.1, settings: settings))
        XCTAssertFalse(Protection.cooledEnoughToResume(cpu: nil, battery: 30, settings: settings), "cannot judge without a CPU reading")
    }

    func testOnlyProtectiveStopsPutAClosedMacToSleep() {
        XCTAssertTrue(StopReason.timer.putsClosedMacToSleep)
        XCTAssertTrue(StopReason.cpuHot.putsClosedMacToSleep)
        XCTAssertFalse(StopReason.user.putsClosedMacToSleep)
        XCTAssertFalse(StopReason.quit.putsClosedMacToSleep)
    }
}

final class SettingsTests: XCTestCase {
    func testClampingKeepsValuesInsideTheSettingsScreenRanges() {
        var s = Settings()
        s.cpuLimit = 200
        s.batteryLimit = 10
        s.sustainSeconds = 1
        s.batteryFloor = 0
        s.resumeWaitMinutes = 10_000
        s.defaultEnd = .after(minutes: 5000)
        let c = s.clamped()
        XCTAssertEqual(c.cpuLimit, 105)
        XCTAssertEqual(c.batteryLimit, 35)
        XCTAssertEqual(c.sustainSeconds, 10)
        XCTAssertEqual(c.batteryFloor, 5)
        XCTAssertEqual(c.resumeWaitMinutes, 240)
        XCTAssertEqual(c.defaultEnd, .unlimited)
    }

    func testSettingsFromAnOlderVersionKeepDefaultsForMissingKeys() throws {
        let stored = Data(#"{"cpuLimit": 90}"#.utf8)
        let s = try JSONDecoder().decode(Settings.self, from: stored)
        XCTAssertEqual(s.cpuLimit, 90)
        XCTAssertEqual(s.batteryLimit, 45)
        XCTAssertEqual(s.sustainSeconds, 60)
        XCTAssertTrue(s.stopOnUnplug)
    }
}
