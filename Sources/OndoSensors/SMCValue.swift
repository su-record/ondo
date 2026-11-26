import Foundation

/// Decodes SMC temperature values. Apple silicon uses little-endian 32-bit floats ('flt ');
/// Intel uses signed 8.8 fixed point, big-endian ('sp78').
public enum SMCValue {
    public static func celsius(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "sp78" where bytes.count == 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }
}
