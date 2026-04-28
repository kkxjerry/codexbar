import Foundation
import Combine

class TokenStore: ObservableObject {
    static let shared = TokenStore()

    @Published var accounts: [TokenAccount] = []
    @Published var relayProfiles: [RelayProfile] = []

    private let poolURL: URL
    private let relayProfilesURL: URL
    private let authURL: URL
    private let configManager = CodexConfigManager.shared

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        // 用 getpwuid 取真实 home，绕过沙盒对 HOME 的重映射
        let sandboxHome = FileManager.default.homeDirectoryForCurrentUser
        let realHome: URL
        if let pw = getpwuid(getuid()), let pwDir = pw.pointee.pw_dir {
            realHome = URL(fileURLWithPath: String(cString: pwDir))
        } else {
            realHome = sandboxHome
        }
        let realCodex = realHome.appendingPathComponent(".codex")
        try? FileManager.default.createDirectory(at: realCodex, withIntermediateDirectories: true)

        // token_pool.json 和 auth.json 都放在真实 ~/.codex/
        poolURL = realCodex.appendingPathComponent("token_pool.json")
        relayProfilesURL = realCodex.appendingPathComponent("relay_profiles.json")
        authURL = realCodex.appendingPathComponent("auth.json")

        load()
    }

    func load() {
        loadAccounts()
        loadRelayProfiles()
        markActiveAccount()
    }

    func save() {
        let pool = TokenPool(accounts: accounts)
        guard let data = try? encoder.encode(pool) else { return }
        try? data.write(to: poolURL, options: .atomic)
    }

    func saveRelayProfiles() {
        let pool = RelayProfilePool(profiles: relayProfiles)
        guard let data = try? encoder.encode(pool) else { return }
        try? data.write(to: relayProfilesURL, options: .atomic)
    }

    func addOrUpdate(_ account: TokenAccount) {
        let normalized = normalize(account)
        if let idx = accounts.firstIndex(where: { $0.identityKey == normalized.identityKey }) {
            var merged = normalized
            // 保留 store 里的 isActive，防止异步刷新快照覆盖 activate() 的结果
            merged.isActive = accounts[idx].isActive
            accounts[idx] = merged
        } else {
            accounts.append(normalized)
        }
        save()
    }

    func remove(_ account: TokenAccount) {
        accounts.removeAll { $0.identityKey == account.identityKey }
        save()
    }

    func clearAllAccounts() {
        accounts = []
        save()
    }

    func clearAllRelayProfiles() {
        relayProfiles = []
        saveRelayProfiles()
    }

    /// 将指定账号写入 ~/.codex/auth.json，激活为当前 Codex 使用账号
    func activate(_ account: TokenAccount) throws {
        try configManager.restoreManagedConfigIfNeeded()
        let authDict = buildAuthJSON(account)
        guard JSONSerialization.isValidJSONObject(authDict),
              let data = try? JSONSerialization.data(withJSONObject: authDict, options: [.prettyPrinted, .sortedKeys]) else {
            throw TokenStoreError.encodingFailed
        }
        try data.write(to: authURL, options: .atomic)
        markActiveAccount()
        objectWillChange.send()
    }

    func addOrUpdateRelayProfile(_ profile: RelayProfile) {
        let normalized = normalize(profile)

        if let idx = relayProfiles.firstIndex(where: {
            $0.id == normalized.id || $0.name.localizedCaseInsensitiveCompare(normalized.name) == .orderedSame
        }) {
            var merged = normalized
            merged.isActive = relayProfiles[idx].isActive
            merged.lastActivatedAt = relayProfiles[idx].lastActivatedAt
            relayProfiles[idx] = merged
        } else {
            relayProfiles.append(normalized)
        }

        saveRelayProfiles()
        markActiveAccount()
    }

    func removeRelayProfile(_ profile: RelayProfile) throws {
        guard !profile.isActive else {
            throw TokenStoreError.cannotDeleteActiveRelay
        }
        relayProfiles.removeAll { $0.id == profile.id }
        saveRelayProfiles()
    }

    func activateRelay(_ profile: RelayProfile) throws {
        let normalized = normalize(profile)
        try configManager.activateRelay(normalized)

        let authDict: [String: Any] = [
            "auth_mode": "apikey",
            "OPENAI_API_KEY": normalized.apiKey
        ]

        guard JSONSerialization.isValidJSONObject(authDict),
              let data = try? JSONSerialization.data(withJSONObject: authDict, options: [.prettyPrinted, .sortedKeys]) else {
            throw TokenStoreError.encodingFailed
        }

        try data.write(to: authURL, options: .atomic)

        if let idx = relayProfiles.firstIndex(where: { $0.id == normalized.id }) {
            relayProfiles[idx].lastActivatedAt = Date()
        } else {
            relayProfiles.append(RelayProfile(
                id: normalized.id,
                name: normalized.name,
                baseURL: normalized.baseURL,
                apiKey: normalized.apiKey,
                model: normalized.model,
                isActive: false,
                lastActivatedAt: Date()
            ))
        }

        markActiveAccount()
        objectWillChange.send()
    }

    func activeAccount() -> TokenAccount? {
        accounts.first { $0.isActive }
    }

    func activeRelayProfile() -> RelayProfile? {
        relayProfiles.first { $0.isActive }
    }

    // MARK: - Private

    func markActiveAccount() {
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            clearActiveStates()
            return
        }

        let authMode = (json["auth_mode"] as? String) ?? "chatgpt"

        if authMode == "apikey" {
            markActiveRelay(json: json)
            save()
            saveRelayProfiles()
            return
        }

        guard let tokens = json["tokens"] as? [String: Any] else {
            clearActiveStates()
            save()
            saveRelayProfiles()
            return
        }

        for idx in relayProfiles.indices {
            relayProfiles[idx].isActive = false
        }

        let activeAccountUserId = resolveAccountUserId(from: tokens)
        let activeAccountId = tokens["account_id"] as? String
        var matchedActive = false

        for idx in accounts.indices {
            if !activeAccountUserId.isEmpty {
                accounts[idx].isActive = (accounts[idx].identityKey == activeAccountUserId)
                matchedActive = matchedActive || accounts[idx].isActive
            } else {
                accounts[idx].isActive = false
            }
        }

        if !matchedActive, let activeAccountId, !activeAccountId.isEmpty {
            for idx in accounts.indices {
                accounts[idx].isActive = (accounts[idx].accountId == activeAccountId)
            }
        }
        save()
        saveRelayProfiles()
    }

    private func buildAuthJSON(_ account: TokenAccount) -> [String: Any] {
        let tokens: [String: Any] = [
            "access_token": account.accessToken,
            "refresh_token": account.refreshToken,
            "id_token": account.idToken,
            "account_id": account.accountId,
        ]
        return [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": NSNull(),
            "last_refresh": ISO8601DateFormatter().string(from: Date()),
            "tokens": tokens
        ]
    }

    private func normalize(_ account: TokenAccount) -> TokenAccount {
        guard account.accountUserId.isEmpty else { return account }

        var normalized = account
        normalized.accountUserId = AccountBuilder.accountUserId(fromAccessToken: account.accessToken)
        return normalized
    }

    private func normalize(_ profile: RelayProfile) -> RelayProfile {
        RelayProfile(
            id: profile.id,
            name: profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: RelayProfile.normalizeBaseURL(profile.baseURL),
            apiKey: profile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: profile.model.trimmingCharacters(in: .whitespacesAndNewlines),
            isActive: profile.isActive,
            lastActivatedAt: profile.lastActivatedAt
        )
    }

    private func resolveAccountUserId(from tokens: [String: Any]) -> String {
        if let accountUserId = tokens["account_user_id"] as? String, !accountUserId.isEmpty {
            return accountUserId
        }
        if let accessToken = tokens["access_token"] as? String {
            return AccountBuilder.accountUserId(fromAccessToken: accessToken)
        }
        return ""
    }

    private func loadAccounts() {
        guard let data = try? Data(contentsOf: poolURL) else {
            accounts = []
            return
        }
        do {
            let pool = try decoder.decode(TokenPool.self, from: data)
            accounts = pool.accounts.map(normalize)
        } catch {
            accounts = []
        }
    }

    private func loadRelayProfiles() {
        guard let data = try? Data(contentsOf: relayProfilesURL) else {
            relayProfiles = []
            return
        }
        do {
            let pool = try decoder.decode(RelayProfilePool.self, from: data)
            relayProfiles = pool.profiles.map(normalize)
        } catch {
            relayProfiles = []
        }
    }

    private func clearActiveStates() {
        for idx in accounts.indices {
            accounts[idx].isActive = false
        }
        for idx in relayProfiles.indices {
            relayProfiles[idx].isActive = false
        }
    }

    private func markActiveRelay(json: [String: Any]) {
        let apiKey = (json["OPENAI_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activeBaseURL = RelayProfile.normalizeBaseURL(configManager.currentRelayBaseURL() ?? "")
        let activeProvider = configManager.currentModelProvider()

        clearActiveStates()

        guard activeProvider == "codexbar_relay" else { return }

        var matched = false
        for idx in relayProfiles.indices {
            let keyMatches = relayProfiles[idx].apiKey == apiKey
            let urlMatches = activeBaseURL.isEmpty || relayProfiles[idx].normalizedBaseURL == activeBaseURL
            relayProfiles[idx].isActive = keyMatches && urlMatches
            matched = matched || relayProfiles[idx].isActive
        }

        if !matched, !apiKey.isEmpty,
           let idx = relayProfiles.firstIndex(where: { $0.apiKey == apiKey }) {
            relayProfiles[idx].isActive = true
        }
    }
}

enum TokenStoreError: LocalizedError {
    case encodingFailed
    case cannotDeleteActiveRelay

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "写入 auth.json 失败"
        case .cannotDeleteActiveRelay:
            return L.relayDeleteActiveError
        }
    }
}
