import Foundation

struct CLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum OutputMode {
    case human
    case json
}

@main
struct CodexBarCtl {
    static func main() {
        do {
            try run()
        } catch {
            fputs("codexbarctl: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printHelp()
            return
        }
        args.removeFirst()

        switch command {
        case "status":
            let outputMode: OutputMode = args.contains("--json") ? .json : .human
            let status = try readStatus()
            renderStatus(status, mode: outputMode)

        case "accounts":
            let outputMode: OutputMode = args.contains("--json") ? .json : .human
            let status = try readStatus()
            renderAccounts(status.accounts, mode: outputMode)

        case "switch-auto":
            guard let identityKey = args.first, !identityKey.hasPrefix("--") else {
                throw CLIError(message: "Usage: codexbarctl switch-auto <identityKey> [--wait] [--timeout 300]")
            }
            let wait = args.contains("--wait")
            let timeout = parseTimeout(args) ?? 300
            try enqueueSwitch(identityKey: identityKey, wait: wait, timeout: timeout)

        case "cancel-switch":
            try enqueueSimple(action: .cancelPendingSwitch)

        case "refresh":
            try enqueueSimple(action: .refreshNow)

        case "paths":
            print("root: \(ControlBridgePaths.rootURL().path)")
            print("status: \(ControlBridgePaths.statusURL().path)")
            print("commands: \(ControlBridgePaths.commandsURL().path)")
            print("results: \(ControlBridgePaths.resultsURL().path)")

        case "help", "--help", "-h":
            printHelp()

        default:
            throw CLIError(message: "Unknown command: \(command)")
        }
    }

    private static func enqueueSwitch(identityKey: String, wait: Bool, timeout: Int) throws {
        let command = ControlCommand(action: .switchWhenIdle, identityKey: identityKey)
        try writeCommand(command)

        if !wait {
            print("queued \(command.id)")
            return
        }

        let result = try waitForResult(id: command.id, timeout: min(timeout, 15))
        if result.status == .error {
            throw CLIError(message: result.message)
        }

        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            if let status = try? readStatus(),
               status.activeIdentityKey == identityKey,
               status.pendingSwitch == nil {
                print("switched \(identityKey)")
                return
            }
            Thread.sleep(forTimeInterval: 1)
        }

        throw CLIError(message: "Timed out waiting for switch to finish.")
    }

    private static func enqueueSimple(action: ControlCommandAction) throws {
        let command = ControlCommand(action: action)
        try writeCommand(command)
        let result = try waitForResult(id: command.id, timeout: 15)
        if result.status == .error {
            throw CLIError(message: result.message)
        }
        print(result.message)
    }

    private static func writeCommand(_ command: ControlCommand) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: ControlBridgePaths.commandsURL(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: ControlBridgePaths.resultsURL(), withIntermediateDirectories: true)

        let filename = "\(Int(Date().timeIntervalSince1970 * 1000))-\(command.id).json"
        let url = ControlBridgePaths.commandsURL().appendingPathComponent(filename)
        let data = try ControlBridgeJSON.encoder.encode(command)
        try data.write(to: url, options: .atomic)
    }

    private static func waitForResult(id: String, timeout: Int) throws -> ControlResult {
        let resultURL = ControlBridgePaths.resultsURL().appendingPathComponent("\(id).json")
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))

        while Date() < deadline {
            if let data = try? Data(contentsOf: resultURL),
               let result = try? ControlBridgeJSON.decoder.decode(ControlResult.self, from: data) {
                return result
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        throw CLIError(message: "Timed out waiting for app response. Make sure codexAppBar is running.")
    }

    private static func readStatus() throws -> ControlStatus {
        let url = ControlBridgePaths.statusURL()
        guard let data = try? Data(contentsOf: url) else {
            throw CLIError(message: "Status file not found. Start codexAppBar first.")
        }
        return try ControlBridgeJSON.decoder.decode(ControlStatus.self, from: data)
    }

    private static func parseTimeout(_ args: [String]) -> Int? {
        guard let index = args.firstIndex(of: "--timeout"),
              index + 1 < args.count,
              let value = Int(args[index + 1]) else {
            return nil
        }
        return value
    }

    private static func renderStatus(_ status: ControlStatus, mode: OutputMode) {
        switch mode {
        case .json:
            if let data = try? ControlBridgeJSON.encoder.encode(status),
               let string = String(data: data, encoding: .utf8) {
                print(string)
            }
        case .human:
            print("updated: \(iso8601(status.updatedAt))")
            print("codex_running: \(status.codexRunning)")
            print("codex_busy: \(status.codexBusy)")
            print("full_disk_access: \(status.fullDiskAccessGranted)")
            print("active: \(status.activeEmail ?? "-")")
            if let pending = status.pendingSwitch {
                print("pending: \(pending.email) ready=\(pending.ready) source=\(pending.source.rawValue)")
            } else {
                print("pending: -")
            }
            if let lastSuccess = status.lastSuccess {
                print("last_success: \(lastSuccess)")
            }
            if let lastError = status.lastError {
                print("last_error: \(lastError)")
            }
            print("accounts: \(status.accounts.count)")
        }
    }

    private static func renderAccounts(_ accounts: [ControlAccountSummary], mode: OutputMode) {
        switch mode {
        case .json:
            if let data = try? ControlBridgeJSON.encoder.encode(accounts),
               let string = String(data: data, encoding: .utf8) {
                print(string)
            }
        case .human:
            for account in accounts {
                let activeMark = account.isActive ? "*" : "-"
                print("\(activeMark) \(account.identityKey) | \(account.email) | \(account.workspace) | \(account.usageStatus) | 5h=\(Int(account.primaryUsedPercent))% 7d=\(Int(account.secondaryUsedPercent))%")
            }
        }
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func printHelp() {
        print(
            """
            codexbarctl commands:
              status [--json]
              accounts [--json]
              switch-auto <identityKey> [--wait] [--timeout 300]
              cancel-switch
              refresh
              paths
            """
        )
    }
}
