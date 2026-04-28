import Foundation

struct RelayProfile: Codable, Identifiable {
    var id: String
    var name: String
    var baseURL: String
    var apiKey: String
    var model: String
    var isActive: Bool
    var lastActivatedAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        apiKey: String,
        model: String = "",
        isActive: Bool = false,
        lastActivatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.isActive = isActive
        self.lastActivatedAt = lastActivatedAt
    }

    var identityKey: String { "relay:\(id)" }

    var rowTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return baseURL
    }

    var normalizedBaseURL: String {
        Self.normalizeBaseURL(baseURL)
    }

    var maskedAPIKey: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return String(repeating: "•", count: max(trimmed.count, 4)) }
        return "\(trimmed.prefix(4))••••\(trimmed.suffix(4))"
    }

    var hostLabel: String {
        URL(string: normalizedBaseURL)?.host ?? normalizedBaseURL
    }

    static func normalizeBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme,
           let host = url.host,
           scheme.hasPrefix("http") {
            let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty || path == "/" {
                return "\(scheme)://\(host)\(url.port.map { ":\($0)" } ?? "")/v1"
            }
        }

        return trimmed
    }
}

struct RelayProfilePool: Codable {
    var profiles: [RelayProfile]

    init(profiles: [RelayProfile] = []) {
        self.profiles = profiles
    }
}
