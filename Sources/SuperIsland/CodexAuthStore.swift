import Foundation

enum CodexAuthMode: String, Codable, Sendable {
    case chatgpt
    case apiKey = "apikey"
}

struct CodexAuthSnapshot: Codable, Equatable, Sendable {
    var authMode: CodexAuthMode
    var email: String?
    var planType: String?
    var chatgptAccountId: String?
    var chatgptUserId: String?
    var recordKey: String?
    var accessToken: String?
    var lastRefresh: String?
    var isConsistentAccount: Bool
}

enum CodexAuthStoreError: Error {
    case invalidFormat
}

enum CodexAuthStore {
    static func authFileURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
    }

    static func load(fileManager: FileManager = .default) -> CodexAuthSnapshot? {
        try? load(from: authFileURL(fileManager: fileManager))
    }

    static func load(from url: URL) throws -> CodexAuthSnapshot {
        try parse(data: Data(contentsOf: url))
    }

    static func parse(data: Data) throws -> CodexAuthSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAuthStoreError.invalidFormat
        }
        return parse(root: root)
    }

    private static func parse(root: [String: Any]) -> CodexAuthSnapshot {
        if let apiKey = nonEmptyString(root["OPENAI_API_KEY"]), !apiKey.isEmpty {
            return CodexAuthSnapshot(
                authMode: .apiKey,
                email: nil,
                planType: nil,
                chatgptAccountId: nil,
                chatgptUserId: nil,
                recordKey: nil,
                accessToken: nil,
                lastRefresh: nil,
                isConsistentAccount: false
            )
        }

        let lastRefresh = nonEmptyString(root["last_refresh"])
        let tokens = root["tokens"] as? [String: Any]
        let accessToken = nonEmptyString(tokens?["access_token"])
        let tokenAccountId = nonEmptyString(tokens?["account_id"])
        let jwtPayload = parseJWT(nonEmptyString(tokens?["id_token"]))

        let authClaims = jwtPayload?["https://api.openai.com/auth"] as? [String: Any]
        let profileClaims = jwtPayload?["https://api.openai.com/profile"] as? [String: Any]

        let email = normalizeEmail(
            nonEmptyString(jwtPayload?["email"]) ?? nonEmptyString(profileClaims?["email"])
        )
        let planType = normalizeField(
            nonEmptyString(authClaims?["chatgpt_plan_type"]) ?? nonEmptyString(jwtPayload?["chatgpt_plan_type"])
        )
        let jwtAccountId = normalizeField(
            nonEmptyString(authClaims?["chatgpt_account_id"]) ?? nonEmptyString(jwtPayload?["chatgpt_account_id"])
        )
        let chatgptUserId = normalizeField(
            nonEmptyString(authClaims?["chatgpt_user_id"])
                ?? nonEmptyString(authClaims?["user_id"])
                ?? nonEmptyString(jwtPayload?["chatgpt_user_id"])
                ?? nonEmptyString(jwtPayload?["user_id"])
        )

        let isConsistentAccount = {
            guard let tokenAccountId, let jwtAccountId else { return false }
            return tokenAccountId == jwtAccountId
        }()

        let chatgptAccountId = normalizeField(tokenAccountId ?? jwtAccountId)
        let recordKey: String?
        if isConsistentAccount,
           let chatgptUserId,
           let tokenAccountId
        {
            recordKey = "\(chatgptUserId)::\(tokenAccountId)"
        } else {
            recordKey = nil
        }

        return CodexAuthSnapshot(
            authMode: .chatgpt,
            email: email,
            planType: planType,
            chatgptAccountId: chatgptAccountId,
            chatgptUserId: chatgptUserId,
            recordKey: recordKey,
            accessToken: accessToken,
            lastRefresh: lastRefresh,
            isConsistentAccount: isConsistentAccount
        )
    }

    static func parseJWT(_ token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var padded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 {
            padded.append("=")
        }

        guard let data = Data(base64Encoded: padded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizeEmail(_ value: String?) -> String? {
        value?.lowercased()
    }

    private static func normalizeField(_ value: String?) -> String? {
        value
    }
}
