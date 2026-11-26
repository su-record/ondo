import Darwin
import Foundation

/// Minimal Unix domain socket helpers for the control channel.
public enum UnixSocket {
    public static func connect(path: String) throws -> Int32 {
        let fd = try makeSocket()
        var address = try makeAddress(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw ControlError.unreachable("cannot connect to ondo (\(reason))")
        }
        return fd
    }

    /// Listens on `path`, replacing a stale socket file. Only the current user can connect (mode 0600).
    public static func listen(path: String) throws -> Int32 {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        unlink(path)
        let fd = try makeSocket()
        var address = try makeAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw ControlError.unreachable("cannot listen on \(path) (\(reason))")
        }
        return fd
    }

    public static func write(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                guard sent > 0 else { throw ControlError.unreachable("write failed (\(String(cString: strerror(errno))))") }
                offset += sent
            }
        }
    }

    /// Reads until a newline or end of stream.
    public static func readLine(_ fd: Int32, limit: Int) throws -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while data.count <= limit {
            let count = read(fd, &chunk, chunk.count)
            if count < 0 { throw ControlError.unreachable("read failed (\(String(cString: strerror(errno))))") }
            if count == 0 { return data }
            if let newline = chunk[..<count].firstIndex(of: 0x0a) {
                data.append(contentsOf: chunk[..<newline])
                return data
            }
            data.append(contentsOf: chunk[..<count])
        }
        throw ControlError.invalid("message longer than \(limit) bytes")
    }

    /// Bounds how long a read or write may block, so one stuck peer cannot hold the server.
    public static func setTimeout(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError.unreachable("cannot create socket (\(String(cString: strerror(errno))))") }
        return fd
    }

    private static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw ControlError.invalid("socket path too long: \(path)") }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }
}
