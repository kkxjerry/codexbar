import Foundation

struct RelayConfigBackup: Codable {
    var hadModel: Bool
    var model: String?
    var hadModelProvider: Bool
    var modelProvider: String?
}

final class CodexConfigManager {
    static let shared = CodexConfigManager()
    private let relayProviderID = "codexbar_relay"

    private let fileManager = FileManager.default
    private let codexURL: URL
    private let configURL: URL
    private let backupURL: URL

    private init() {
        let home: URL
        if let pw = getpwuid(getuid()), let pwDir = pw.pointee.pw_dir {
            home = URL(fileURLWithPath: String(cString: pwDir))
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }

        codexURL = home.appendingPathComponent(".codex", isDirectory: true)
        configURL = codexURL.appendingPathComponent("config.toml")
        backupURL = codexURL.appendingPathComponent("codexbar/relay_config_backup.json")

        try? fileManager.createDirectory(at: codexURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func currentModel() -> String? {
        topLevelValue(for: "model")
    }

    func currentModelProvider() -> String? {
        topLevelValue(for: "model_provider")
    }

    func currentRelayBaseURL() -> String? {
        value(inSection: "model_providers.\(relayProviderID)", key: "base_url")
    }

    func activateRelay(_ profile: RelayProfile) throws {
        let backup = try ensureBackup()
        let relayModel = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelToApply = relayModel.isEmpty
            ? (backup.hadModel ? backup.model : nil)
            : relayModel

        try writeManagedConfig(
            model: modelToApply,
            modelProvider: relayProviderID,
            relayBaseURL: RelayProfile.normalizeBaseURL(profile.baseURL)
        )
    }

    func restoreManagedConfigIfNeeded() throws {
        guard let backup = loadBackup() else { return }
        try writeManagedConfig(
            model: backup.hadModel ? backup.model : nil,
            modelProvider: backup.hadModelProvider ? backup.modelProvider : nil,
            relayBaseURL: nil
        )
        try? fileManager.removeItem(at: backupURL)
    }

    private func ensureBackup() throws -> RelayConfigBackup {
        if let existing = loadBackup() {
            return existing
        }

        let backup = RelayConfigBackup(
            hadModel: currentModel() != nil,
            model: currentModel(),
            hadModelProvider: currentModelProvider() != nil,
            modelProvider: currentModelProvider()
        )
        let data = try JSONEncoder().encode(backup)
        try data.write(to: backupURL, options: .atomic)
        return backup
    }

    private func loadBackup() -> RelayConfigBackup? {
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        return try? JSONDecoder().decode(RelayConfigBackup.self, from: data)
    }

    private func topLevelValue(for key: String) -> String? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            guard trimmed.hasPrefix("\(key)"),
                  let equals = trimmed.firstIndex(of: "=") else { continue }

            let rawValue = trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
            return parseTomlString(String(rawValue))
        }
        return nil
    }

    private func value(inSection sectionName: String, key: String) -> String? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        var inSection = false

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inSection = trimmed == "[\(sectionName)]"
                continue
            }

            guard inSection,
                  matchesTopLevelKey(trimmed, key: key),
                  let equals = trimmed.firstIndex(of: "=") else { continue }

            let rawValue = trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
            return parseTomlString(String(rawValue))
        }

        return nil
    }

    private func writeManagedConfig(model: String?, modelProvider: String?, relayBaseURL: String?) throws {
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let lines = existing.isEmpty ? [] : existing.components(separatedBy: .newlines)
        let strippedLines = removeSection(named: "model_providers.\(relayProviderID)", from: lines)
        let tableIndex = strippedLines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? strippedLines.count

        var topLevelLines = Array(strippedLines.prefix(tableIndex))
        var remainingLines = Array(strippedLines.dropFirst(tableIndex))

        topLevelLines = upsertTopLevelLine(topLevelLines, key: "model", value: model)
        topLevelLines = upsertTopLevelLine(topLevelLines, key: "model_provider", value: modelProvider)

        while topLevelLines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            topLevelLines.removeLast()
        }

        if !remainingLines.isEmpty {
            while remainingLines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                remainingLines.removeFirst()
            }
        }

        var combined = topLevelLines

        if let relayBaseURL {
            if !combined.isEmpty {
                combined.append("")
            }
            combined.append("[model_providers.\(relayProviderID)]")
            combined.append("name = \(encodeTomlString("CodexBar Relay"))")
            combined.append("base_url = \(encodeTomlString(relayBaseURL))")
            combined.append("wire_api = \(encodeTomlString("responses"))")
        }

        if !remainingLines.isEmpty {
            if !combined.isEmpty {
                combined.append("")
            }
            combined.append(contentsOf: remainingLines)
        }

        let result = combined.joined(separator: "\n")
        try result.data(using: .utf8)?.write(to: configURL, options: .atomic)
    }

    private func removeSection(named sectionName: String, from lines: [String]) -> [String] {
        var result: [String] = []
        var skipping = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if trimmed == "[\(sectionName)]" {
                    skipping = true
                    continue
                }
                skipping = false
            }

            if !skipping {
                result.append(line)
            }
        }

        return result
    }

    private func upsertTopLevelLine(_ lines: [String], key: String, value: String?) -> [String] {
        var result: [String] = []
        var updated = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if matchesTopLevelKey(trimmed, key: key) {
                if let value {
                    result.append("\(key) = \(encodeTomlString(value))")
                    updated = true
                }
                continue
            }
            result.append(line)
        }

        if !updated, let value {
            result.append("\(key) = \(encodeTomlString(value))")
        }

        return result
    }

    private func matchesTopLevelKey(_ line: String, key: String) -> Bool {
        guard line.hasPrefix(key) else { return false }
        guard let equals = line.firstIndex(of: "=") else { return false }
        let prefix = line[..<equals].trimmingCharacters(in: .whitespaces)
        return prefix == key
    }

    private func encodeTomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func parseTomlString(_ raw: String) -> String {
        var value = raw
        if let commentIndex = value.firstIndex(of: "#") {
            value = String(value[..<commentIndex])
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
            return value
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }

        return value
    }
}
