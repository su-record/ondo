import XCTest
@testable import OndoSensors

final class SensorSelectionTests: XCTestCase {
    private func hid(_ name: String, _ c: Double) -> SensorReading { SensorReading(source: .hid, name: name, celsius: c) }
    private func smc(_ name: String, _ c: Double) -> SensorReading { SensorReading(source: .smc, name: name, celsius: c) }

    func testAppleSiliconPrefersHIDDieSensorsAndIgnoresBrokenOnes() {
        // Shape measured on M5 Pro: tdie sensors, tdev sensors reporting -9201, SMC Tp keys.
        let t = SensorSelection.temperatures(from: [
            hid("PMU tdie1", 64.2), hid("PMU tdie9", 56.4), hid("PMU tdev4", -9201.1),
            smc("Tp00", 70), hid("gas gauge battery", 35), smc("TB0T", 33.5), smc("TB2T", 35.5),
        ])
        XCTAssertEqual(t.cpu, 64.2)
        XCTAssertEqual(t.cpuSensors.map(\.name), ["PMU tdie1", "PMU tdie9"])
        XCTAssertEqual(t.battery, 35.5, "SMC battery keys win over the HID gas gauge")
    }

    func testFallsBackToSMCCoreKeysWithoutHIDSensors() {
        let t = SensorSelection.temperatures(from: [smc("Tp01", 52), smc("Te05", 58), smc("Tg0f", 90), smc("TC0P", 99)])
        XCTAssertEqual(t.cpu, 58, "Tp/Te only: GPU (Tg) and Intel keys are not used when Apple keys exist")
    }

    func testIntelUsesItsCPUKeys() {
        let t = SensorSelection.temperatures(from: [smc("TC0P", 61.25), smc("TC0D", 70.5), smc("TG0P", 80)])
        XCTAssertEqual(t.cpu, 70.5)
    }

    func testBatteryFallsBackToHIDGasGauge() {
        let t = SensorSelection.temperatures(from: [hid("gas gauge battery", 33), hid("gas gauge battery", 34.5)])
        XCTAssertEqual(t.battery, 34.5)
    }

    func testNoUsableSensorsMeansUnavailable() {
        let t = SensorSelection.temperatures(from: [hid("PMU tdie1", 0), hid("PMU tdev1", -9201), smc("TA0P", 30)])
        XCTAssertNil(t.cpu)
        XCTAssertNil(t.battery)
    }

    func testDecodesSMCValueTypes() {
        let float = Float(51.5).bitPattern
        let little = [0, 8, 16, 24].map { UInt8((float >> $0) & 0xff) }
        XCTAssertEqual(SMCValue.celsius(type: "flt ", bytes: little), 51.5)
        XCTAssertEqual(SMCValue.celsius(type: "sp78", bytes: [0x3a, 0x80]), 58.5)
        XCTAssertNil(SMCValue.celsius(type: "ui8 ", bytes: [40]))
        XCTAssertNil(SMCValue.celsius(type: "flt ", bytes: [0, 0]), "wrong size")
    }
}
