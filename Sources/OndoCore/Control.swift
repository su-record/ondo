import Foundation
import OndoSensors
import OndoShared

/// Requests the CLI, the MCP server and URL links send to the running app.
/// External callers can turn staying awake on and off and read state; they cannot change settings.
public enum ControlCommand: String, Codable, Sendable {
    case status, on, off, sensors, displayOff = "display-off", wake
}

public struct ControlRequest: Codable, Sendable {
    public var command: ControlCommand
    /// `on`: how long to stay awake. `wake`: how long until the wake.
    public var minutes: Int?
    /// `on`: when to stop. `wake`: when to wake. 24-hour "HH:mm".
    public var until: String?
    /// `wake`: cancel ondo's scheduled wakes instead of adding one.
    public var cancel: Bool?

    public init(command: ControlCommand, minutes: Int? = nil, until: String? = nil, cancel: Bool? = nil) {
        self.command = command
        self.minutes = minutes
        self.until = until
        self.cancel = cancel
    }

    /// The end time an `on` request asks for; nil when the request has neither field (use the default).
    public func endTime() throws -> EndTime? {
        if let minutes {
            guard EndTime.minutesRange.contains(minutes) else { throw ControlError.invalid("minutes must be 1–1440") }
            return .after(minutes: minutes)
        }
        if let until {
            guard let end = EndTime.clock(from: until) else { throw ControlError.invalid("until must be HH:mm") }
            return end
        }
        return nil
    }
}

public struct OndoStatus: Codable, Sendable {
    public var awake: Bool
    public var endsAt: Date?
    public var cpu: Double?
    public var battery: Double?
    public var cpuLimit: Double
    public var batteryLimit: Double
    public var power: PowerState
    public var lidClosed: Bool?
    /// Set while a temperature has stayed above its limit long enough to warn.
    public var warning: StopReason?
    public var secondsUntilStop: Int?
    /// SMAppService status of the privileged helper: enabled, requiresApproval, notRegistered or notFound.
    public var helper: String
    public var wakeAt: Date?
    public var lastStop: StopReason?
    /// True while the debug temperature simulation replaces the CPU reading.
    public var simulated: Bool

    public init(awake: Bool, endsAt: Date?, cpu: Double?, battery: Double?, cpuLimit: Double, batteryLimit: Double,
                power: PowerState, lidClosed: Bool?, warning: StopReason?, secondsUntilStop: Int?, helper: String,
                wakeAt: Date?, lastStop: StopReason?, simulated: Bool) {
        self.awake = awake; self.endsAt = endsAt; self.cpu = cpu; self.battery = battery
        self.cpuLimit = cpuLimit; self.batteryLimit = batteryLimit; self.power = power; self.lidClosed = lidClosed
        self.warning = warning; self.secondsUntilStop = secondsUntilStop; self.helper = helper
        self.wakeAt = wakeAt; self.lastStop = lastStop; self.simulated = simulated
    }
}

public struct ControlResponse: Codable, Sendable {
    public var ok: Bool
    /// Set when protection refused the request.
    public var refusal: StopReason?
    public var error: String?
    public var status: OndoStatus?
    public var sensors: [SensorReading]?

    public init(ok: Bool, refusal: StopReason? = nil, error: String? = nil, status: OndoStatus? = nil, sensors: [SensorReading]? = nil) {
        self.ok = ok; self.refusal = refusal; self.error = error; self.status = status; self.sensors = sensors
    }
}

public enum ControlError: Error, CustomStringConvertible {
    case invalid(String)
    case unreachable(String)

    public var description: String {
        switch self {
        case .invalid(let message), .unreachable(let message): return message
        }
    }
}

public enum ControlCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum ControlSocket {
    public static var path: String { Identity.supportDirectory.appendingPathComponent("control.sock").path }
    /// Requests and responses are one JSON line each; this bounds a misbehaving peer.
    public static let maxMessageBytes = 1 << 20

    /// Sends one request to the running app and returns its response.
    public static func send(_ request: ControlRequest) throws -> ControlResponse {
        let fd = try UnixSocket.connect(path: path)
        defer { close(fd) }
        var line = try ControlCoding.encoder().encode(request)
        line.append(0x0a)
        try UnixSocket.write(fd, line)
        let reply = try UnixSocket.readLine(fd, limit: maxMessageBytes)
        return try ControlCoding.decoder().decode(ControlResponse.self, from: reply)
    }
}
