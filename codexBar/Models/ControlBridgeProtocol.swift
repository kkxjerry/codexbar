import Foundation

enum ControlBridgePaths {
    static func homeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let pwDir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: pwDir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func rootURL() -> URL {
        homeDirectory().appendingPathComponent(".codex/codexbar", isDirectory: true)
    }

    static func commandsURL() -> URL {
        rootURL().appendingPathComponent("commands", isDirectory: true)
    }

    static func resultsURL() -> URL {
        rootURL().appendingPathComponent("results", isDirectory: true)
    }

    static func statusURL() -> URL {
        rootURL().appendingPathComponent("status.json")
    }
}

enum ControlBridgeJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum ControlCommandAction: String, Codable {
    case switchWhenIdle = "switch_when_idle"
    case cancelPendingSwitch = "cancel_pending_switch"
    case refreshNow = "refresh_now"
}

struct ControlCommand: Codable {
    var id: String
    var action: ControlCommandAction
    var identityKey: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        action: ControlCommandAction,
        identityKey: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.identityKey = identityKey
        self.createdAt = createdAt
    }
}

enum ControlResultStatus: String, Codable {
    case accepted
    case success
    case error
}

struct ControlResult: Codable {
    var id: String
    var action: ControlCommandAction
    var status: ControlResultStatus
    var message: String
    var finishedAt: Date
}

enum ControlPendingSwitchSource: String, Codable {
    case manual
    case automaticSuggestion = "automatic_suggestion"
    case bridgeAuto = "bridge_auto"
}

struct ControlPendingSwitch: Codable {
    var identityKey: String
    var email: String
    var workspace: String
    var ready: Bool
    var source: ControlPendingSwitchSource
}

struct ControlAccountSummary: Codable {
    var identityKey: String
    var email: String
    var workspace: String
    var planType: String
    var isActive: Bool
    var usageStatus: String
    var primaryUsedPercent: Double
    var secondaryUsedPercent: Double
    var tokenExpired: Bool
    var isSuspended: Bool
}

struct ControlStatus: Codable {
    var updatedAt: Date
    var appRunning: Bool
    var codexRunning: Bool
    var codexBusy: Bool
    var fullDiskAccessGranted: Bool
    var activeIdentityKey: String?
    var activeEmail: String?
    var pendingSwitch: ControlPendingSwitch?
    var lastSuccess: String?
    var lastError: String?
    var accounts: [ControlAccountSummary]
}
