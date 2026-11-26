import Foundation
import OndoCore

/// A minimal MCP server over stdio (newline-delimited JSON-RPC 2.0) exposing ondo's control requests as tools.
/// It only forwards to the app, so the app's protection rules apply to every call.
enum MCPServer {
    static let fallbackProtocolVersion = "2025-06-18"

    struct Tool {
        let name: String
        let description: String
        let properties: [String: Any]
        let request: ([String: Any]) throws -> ControlRequest
    }

    static let tools: [Tool] = [
        Tool(name: "ondo_status",
             description: "Show whether ondo keeps the Mac awake with the lid closed, the end time, CPU and battery temperature, power and any overheat warning.",
             properties: [:]) { _ in ControlRequest(command: .status) },
        Tool(name: "ondo_on",
             description: "Keep the Mac awake with the lid closed. Give minutes (1–1440) or until (24-hour HH:mm), or neither to use the user's default. ondo refuses while the Mac is too hot or the battery is low, and still stops on overheat or power loss; these protections cannot be turned off from here.",
             properties: ["minutes": ["type": "integer", "minimum": 1, "maximum": 1440],
                          "until": ["type": "string", "pattern": "^[0-2]?[0-9]:[0-5][0-9]$"]]) { args in
            ControlRequest(command: .on, minutes: args["minutes"] as? Int, until: args["until"] as? String)
        },
        Tool(name: "ondo_off", description: "Stop keeping the Mac awake; normal sleep returns.",
             properties: [:]) { _ in ControlRequest(command: .off) },
        Tool(name: "ondo_temperature", description: "Read the CPU and battery temperature ondo acts on.",
             properties: [:]) { _ in ControlRequest(command: .status) },
        Tool(name: "ondo_display_off", description: "Turn off the display only; work keeps running.",
             properties: [:]) { _ in ControlRequest(command: .displayOff) },
        Tool(name: "ondo_schedule_wake",
             description: "Wake the Mac later and keep it awake again: in_minutes (1–1440) or at (HH:mm), or cancel: true to remove ondo's scheduled wakes.",
             properties: ["in_minutes": ["type": "integer", "minimum": 1, "maximum": 1440],
                          "at": ["type": "string", "pattern": "^[0-2]?[0-9]:[0-5][0-9]$"],
                          "cancel": ["type": "boolean"]]) { args in
            ControlRequest(command: .wake, minutes: args["in_minutes"] as? Int, until: args["at"] as? String, cancel: args["cancel"] as? Bool)
        },
    ]

    static func run() {
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
            guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
                continue
            }
            // Requests have an id; notifications (no id) and responses get no reply.
            guard let method = message["method"] as? String, let id = message["id"] else { continue }
            let params = message["params"] as? [String: Any] ?? [:]
            switch handle(method: method, params: params) {
            case .success(let result): send(["jsonrpc": "2.0", "id": id, "result": result])
            case .failure(let error): send(["jsonrpc": "2.0", "id": id, "error": ["code": error.code, "message": error.message]])
            }
        }
    }

    struct RPCError: Error { let code: Int; let message: String }

    static func handle(method: String, params: [String: Any]) -> Result<Any, RPCError> {
        switch method {
        case "initialize":
            return .success([
                "protocolVersion": params["protocolVersion"] as? String ?? fallbackProtocolVersion,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "ondo", "version": AppVersion.current],
            ])
        case "ping":
            return .success([:])
        case "tools/list":
            return .success(["tools": tools.map { tool in
                ["name": tool.name, "description": tool.description,
                 "inputSchema": ["type": "object", "properties": tool.properties, "additionalProperties": false]]
            }])
        case "tools/call":
            return call(name: params["name"] as? String, arguments: params["arguments"] as? [String: Any] ?? [:])
        default:
            return .failure(RPCError(code: -32601, message: "method not found: \(method)"))
        }
    }

    static func call(name: String?, arguments: [String: Any]) -> Result<Any, RPCError> {
        guard let tool = tools.first(where: { $0.name == name }) else {
            return .failure(RPCError(code: -32602, message: "unknown tool: \(name ?? "")"))
        }
        do {
            let response = try CommandRunner.sendLaunchingApp(try tool.request(arguments))
            let text = String(decoding: try ControlCoding.encoder().encode(response), as: UTF8.self)
            return .success(["content": [["type": "text", "text": text]], "isError": !response.ok])
        } catch {
            return .success(["content": [["type": "text", "text": "ondo is not reachable: \(error)"]], "isError": true])
        }
    }

    private static func send(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0a)
        FileHandle.standardOutput.write(data)
    }
}
