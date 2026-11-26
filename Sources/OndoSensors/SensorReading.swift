import Foundation

public struct SensorReading: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case hid, smc }

    public let source: Source
    public let name: String
    public let celsius: Double

    public init(source: Source, name: String, celsius: Double) {
        self.source = source
        self.name = name
        self.celsius = celsius
    }

    /// Unread or broken sensors report values such as -9201 or 0.
    public var isPlausible: Bool { (1.0...150.0).contains(celsius) }
}

/// The readings ondo acts on: the hottest CPU sensor and the hottest battery sensor.
public struct Temperatures: Codable, Equatable, Sendable {
    public let cpu: Double?
    public let battery: Double?
    /// Which sensors the values came from, for the debug view.
    public let cpuSensors: [SensorReading]
    public let batterySensors: [SensorReading]

    public init(cpu: Double?, battery: Double?, cpuSensors: [SensorReading], batterySensors: [SensorReading]) {
        self.cpu = cpu
        self.battery = battery
        self.cpuSensors = cpuSensors
        self.batterySensors = batterySensors
    }
}
