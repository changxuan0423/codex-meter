import Foundation
import Darwin

/// Only starts a local stdio transport and reads quota. No inference or conversations.
enum CodexClient {
    static func executable() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["CODEX_METER_CLI"] { candidates.append(override) }
        candidates += [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            home + "/Applications/Codex.app/Contents/Resources/codex",
            home + "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex"
        ]
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    static func fetch() throws -> QuotaSnapshot {
        guard let executable = executable() else { throw MeterError.missingCLI }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        // Do not log account information, credentials, or noisy service startup messages.
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env
        do { try process.run() } catch { throw MeterError.serverStopped }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                let end = Date().addingTimeInterval(0.5)
                while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.01) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }

        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        try send(["id": 1, "method": "initialize", "params": ["clientInfo": [
            "name": "codex_meter", "title": "Codex Meter", "version": "1.0.5"
        ]]])
        let deadline = ProcessInfo.processInfo.systemUptime + 25
        var buffer = Data()
        var initialized = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 250)
            if ready < 0 {
                if errno == EINTR { continue }
                throw MeterError.serverStopped
            }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 16384)
            let count = read(descriptor.fd, &bytes, bytes.count)
            if count <= 0 { throw MeterError.serverStopped }
            buffer.append(contentsOf: bytes.prefix(count))
            if buffer.count > 4 * 1024 * 1024 { throw MeterError.protocolError }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                guard let id = message["id"] as? Int, id == 1 || id == 2 else { continue }
                if let error = message["error"] as? [String: Any] {
                    let text = (error["message"] as? String ?? "").lowercased()
                    if ["auth", "login", "sign in", "chatgpt", "401"].contains(where: text.contains) { throw MeterError.signIn }
                    throw MeterError.serverError
                }
                if id == 1 && !initialized {
                    initialized = true
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                }
                if id == 2, let result = message["result"] as? [String: Any] {
                    let data = try JSONSerialization.data(withJSONObject: result)
                    guard let snapshot = try? JSONDecoder().decode(QuotaSnapshot.self, from: data) else { throw MeterError.protocolError }
                    return snapshot
                }
            }
        }
        throw MeterError.timedOut
    }
}
