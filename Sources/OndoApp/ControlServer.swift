import Darwin
import Foundation
import OndoCore

/// Serves the CLI and MCP requests on the control socket: one JSON line in, one JSON line out.
final class ControlServer: @unchecked Sendable {
    typealias Handler = @Sendable (ControlRequest) async -> ControlResponse

    /// A client that stops sending or reading is dropped after this long.
    static let clientTimeoutSeconds = 5

    private let queue = DispatchQueue(label: "dev.torylabs.ondo.control")
    private var source: DispatchSourceRead?

    func start(handler: @escaping Handler) throws {
        let path = ControlSocket.path
        let fd = try UnixSocket.listen(path: path)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            UnixSocket.setTimeout(client, seconds: Self.clientTimeoutSeconds)
            self?.serve(client, handler: handler)
        }
        source.setCancelHandler {
            close(fd)
            unlink(path)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func serve(_ client: Int32, handler: @escaping Handler) {
        let request: ControlRequest
        do {
            let line = try UnixSocket.readLine(client, limit: ControlSocket.maxMessageBytes)
            request = try ControlCoding.decoder().decode(ControlRequest.self, from: line)
        } catch {
            reply(ControlResponse(ok: false, error: "bad request: \(error)"), to: client)
            return
        }
        Task {
            let response = await handler(request)
            self.queue.async { self.reply(response, to: client) }
        }
    }

    private func reply(_ response: ControlResponse, to client: Int32) {
        defer { close(client) }
        guard var data = try? ControlCoding.encoder().encode(response) else { return }
        data.append(0x0a)
        try? UnixSocket.write(client, data)
    }
}
