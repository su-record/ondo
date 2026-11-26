import CSensors
import Foundation

/// Reads temperature sensors. Not thread-safe: use one instance from one queue.
public final class SensorReader: @unchecked Sendable {
    /// Enough for every HID temperature service seen so far (77 on M5 Pro).
    private static let maxHIDReadings = 256
    /// SMC keys found by the first scan that can stand for CPU or battery temperature.
    private var candidateKeys: [UInt32]?

    public init() {}

    /// CPU and battery temperatures from the sensors chosen by `SensorSelection`.
    public func temperatures() -> Temperatures {
        SensorSelection.temperatures(from: hidReadings() + smcReadings(keys: smcCandidateKeys()))
    }

    /// Every readable temperature sensor, for the debug view and `ondo sensors`. Slower: walks all SMC keys.
    public func allReadings() -> [SensorReading] {
        hidReadings() + smcReadings(keys: allSMCKeys().filter { fourCharacterString($0).hasPrefix("T") })
    }

    private func hidReadings() -> [SensorReading] {
        var buffer = [ondo_hid_reading](repeating: ondo_hid_reading(), count: Self.maxHIDReadings)
        let count = Int(ondo_hid_read(&buffer, Int32(buffer.count)))
        guard count > 0 else { return [] }
        return buffer.prefix(count).map { reading in
            var raw = reading
            let name = withUnsafeBytes(of: &raw.name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return SensorReading(source: .hid, name: name, celsius: reading.celsius)
        }
    }

    private func smcCandidateKeys() -> [UInt32] {
        if let candidateKeys { return candidateKeys }
        let keys = allSMCKeys().filter { SensorSelection.isCandidateSMCKey(fourCharacterString($0)) }
        candidateKeys = keys
        return keys
    }

    private func allSMCKeys() -> [UInt32] {
        var count: UInt32 = 0
        guard ondo_smc_key_count(&count) == 0 else { return [] }
        return (0..<count).compactMap { index in
            var key: UInt32 = 0
            return ondo_smc_key_at(index, &key) == 0 ? key : nil
        }
    }

    private func smcReadings(keys: [UInt32]) -> [SensorReading] {
        keys.compactMap { key in
            var type: UInt32 = 0, size: UInt32 = 0
            var bytes = [UInt8](repeating: 0, count: 32)
            guard ondo_smc_read(key, &type, &size, &bytes) == 0,
                  let celsius = SMCValue.celsius(type: fourCharacterString(type), bytes: Array(bytes.prefix(Int(size))))
            else { return nil }
            return SensorReading(source: .smc, name: fourCharacterString(key), celsius: celsius)
        }
    }
}

func fourCharacterString(_ code: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
    return String(decoding: bytes, as: UTF8.self)
}
