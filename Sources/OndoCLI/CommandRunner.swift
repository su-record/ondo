import Foundation
import OndoCore
import OndoSensors
import OndoShared

enum CommandRunner {
    /// How long to wait for the app after launching it.
    static let launchWait: TimeInterval = 5

    static func run(_ request: ControlRequest, json: Bool) {
        let response: ControlResponse
        do { response = try sendLaunchingApp(request) } catch { fail("\(error)", .unreachable) }
        if json { printJSON(response) } else { print(Describe.response(response, for: request.command)) }
        if response.refusal != nil { exit(Exit.refused.rawValue) }
        if !response.ok { exit(Exit.error.rawValue) }
    }

    /// Temperatures as the running app sees them; read directly when the app is not running.
    static func temperatures(json: Bool) {
        if let response = try? ControlSocket.send(ControlRequest(command: .status)), let status = response.status {
            if json { printJSON(["cpu": status.cpu, "battery": status.battery]) } else { print(Describe.temperatures(cpu: status.cpu, battery: status.battery)) }
            return
        }
        let t = SensorReader().temperatures()
        if json { printJSON(["cpu": t.cpu, "battery": t.battery]) } else { print(Describe.temperatures(cpu: t.cpu, battery: t.battery)) }
    }

    /// Reads every sensor in this process: works without the app and shows what it would see.
    static func sensors(json: Bool) {
        let reader = SensorReader()
        let readings = reader.allReadings()
        let chosen = SensorSelection.temperatures(from: readings)
        if json {
            printJSON(["readings": AnyEncodable(readings), "chosen": AnyEncodable(chosen)])
            return
        }
        print(Describe.sensors(readings, chosen: chosen))
    }

    static func sendLaunchingApp(_ request: ControlRequest) throws -> ControlResponse {
        if let response = try? ControlSocket.send(request) { return response }
        launchApp()
        let deadline = Date().addingTimeInterval(launchWait)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            if let response = try? ControlSocket.send(request) { return response }
        }
        return try ControlSocket.send(request)
    }

    private static func launchApp() {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-b", Identity.appBundleID]
        open.standardError = FileHandle.nullDevice
        try? open.run()
        open.waitUntilExit()
    }

    static func printJSON<T: Encodable>(_ value: T) {
        let encoder = ControlCoding.encoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(value) else { fail("cannot encode output") }
        print(String(decoding: data, as: UTF8.self))
    }
}

/// Lets a dictionary hold values of different encodable types.
struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
