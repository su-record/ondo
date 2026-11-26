import Foundation
import OndoCore
import OndoSensors

enum Exit: Int32 {
    case ok = 0, error = 1, unreachable = 2, refused = 3
}

let usage = """
usage: ondo <command> [options]

  status [--json]                  staying awake, time left, temperatures, power
  on [--for 90m|1h30m|2h] [--until HH:mm]
                                   keep the Mac awake with the lid closed
  off                              stop keeping it awake
  temp [--json]                    CPU and battery temperature
  sensors [--json]                 every temperature sensor (debug)
  display-off                      turn off the display only
  wake --in 30m | --at HH:mm | --cancel
                                   wake the Mac later and keep it awake again
  mcp                              run as an MCP server on stdin/stdout
  version

Exit codes: 0 ok, 1 error, 2 ondo app not reachable, 3 refused by protection.
"""

func fail(_ message: String, _ code: Exit = .error) -> Never {
    FileHandle.standardError.write(Data("ondo: \(message)\n".utf8))
    exit(code.rawValue)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let json = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }
guard let command = arguments.first else { print(usage); exit(Exit.ok.rawValue) }
let options = Array(arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = options.firstIndex(of: name) else { return nil }
    guard index + 1 < options.count else { fail("\(name) needs a value") }
    return options[index + 1]
}

func onRequest() -> ControlRequest {
    if let text = option("--for") {
        guard let minutes = EndTime.minutes(from: text) else { fail("--for takes minutes such as 90m, 1h30m or 2h (1 minute to 24 hours)") }
        return ControlRequest(command: .on, minutes: minutes)
    }
    if let text = option("--until") {
        guard EndTime.clock(from: text) != nil else { fail("--until takes a 24-hour time such as 07:30") }
        return ControlRequest(command: .on, until: text)
    }
    return ControlRequest(command: .on)
}

func wakeRequest() -> ControlRequest {
    if options.contains("--cancel") { return ControlRequest(command: .wake, cancel: true) }
    if let text = option("--in") {
        guard let minutes = EndTime.minutes(from: text) else { fail("--in takes minutes such as 30m or 1h30m (up to 24 hours)") }
        return ControlRequest(command: .wake, minutes: minutes)
    }
    if let text = option("--at") {
        guard EndTime.clock(from: text) != nil else { fail("--at takes a 24-hour time such as 07:00") }
        return ControlRequest(command: .wake, until: text)
    }
    fail("wake needs --in, --at or --cancel")
}

switch command {
case "status": CommandRunner.run(ControlRequest(command: .status), json: json)
case "on": CommandRunner.run(onRequest(), json: json)
case "off": CommandRunner.run(ControlRequest(command: .off), json: json)
case "temp": CommandRunner.temperatures(json: json)
case "sensors": CommandRunner.sensors(json: json)
case "display-off": CommandRunner.run(ControlRequest(command: .displayOff), json: json)
case "wake": CommandRunner.run(wakeRequest(), json: json)
case "mcp": MCPServer.run()
case "version", "--version": print(AppVersion.current)
case "help", "--help", "-h": print(usage)
default: fail("unknown command \(command)\n\n\(usage)")
}
exit(Exit.ok.rawValue)
