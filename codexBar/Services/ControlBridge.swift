import Foundation

final class ControlBridge {
    static let shared = ControlBridge()

    struct CommandHandle {
        let url: URL
        let command: ControlCommand
    }

    private let fileManager = FileManager.default
    private let rootURL = ControlBridgePaths.rootURL()
    private let commandsURL = ControlBridgePaths.commandsURL()
    private let resultsURL = ControlBridgePaths.resultsURL()
    private let statusURL = ControlBridgePaths.statusURL()

    private init() {
        ensureDirectories()
    }

    func writeStatus(_ status: ControlStatus) {
        ensureDirectories()
        guard let data = try? ControlBridgeJSON.encoder.encode(status) else { return }
        try? data.write(to: statusURL, options: .atomic)
    }

    func nextCommand() -> CommandHandle? {
        ensureDirectories()

        guard let files = try? fileManager.contentsOfDirectory(
            at: commandsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let sorted = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in sorted {
            guard let data = try? Data(contentsOf: url) else {
                try? fileManager.removeItem(at: url)
                continue
            }

            guard let command = try? ControlBridgeJSON.decoder.decode(ControlCommand.self, from: data) else {
                try? fileManager.removeItem(at: url)
                continue
            }

            return CommandHandle(url: url, command: command)
        }

        return nil
    }

    func finish(_ handle: CommandHandle, status: ControlResultStatus, message: String) {
        let result = ControlResult(
            id: handle.command.id,
            action: handle.command.action,
            status: status,
            message: message,
            finishedAt: Date()
        )
        writeResult(result)
        try? fileManager.removeItem(at: handle.url)
    }

    private func writeResult(_ result: ControlResult) {
        ensureDirectories()
        let url = resultsURL.appendingPathComponent("\(result.id).json")
        guard let data = try? ControlBridgeJSON.encoder.encode(result) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: commandsURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: resultsURL, withIntermediateDirectories: true)
    }
}
