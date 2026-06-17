import Foundation
import Security

public struct Credentials: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public init(accessToken: String, refreshToken: String? = nil,
                subscriptionType: String? = nil, rateLimitTier: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }
}

public enum CredentialError: Error, Equatable {
    case notFound          // no keychain item — user never logged into Claude Code
    case unreadable(OSStatus)
    case malformed
}

public protocol CredentialReading: Sendable {
    func read() throws -> Credentials
}

/// Reads the Claude Code OAuth credential from the macOS login Keychain.
/// Claude Code keeps this token refreshed while it is used, so re-reading on
/// each poll yields a fresh access token without the app refreshing it itself.
public struct KeychainCredentialProvider: CredentialReading {
    private let service: String

    public init(service: String = "Claude Code-credentials") {
        self.service = service
    }

    public func read() throws -> Credentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw CredentialError.notFound }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialError.unreadable(status)
        }
        return try KeychainCredentialProvider.parse(data)
    }

    /// Parse the credential JSON blob. Pure + testable.
    public static func parse(_ data: Data) throws -> Credentials {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw CredentialError.malformed }
        // Token lives under "claudeAiOauth"; tolerate a flat shape too.
        let o = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = o["accessToken"] as? String, !token.isEmpty else {
            throw CredentialError.malformed
        }
        return Credentials(
            accessToken: token,
            refreshToken: o["refreshToken"] as? String,
            subscriptionType: o["subscriptionType"] as? String,
            rateLimitTier: o["rateLimitTier"] as? String)
    }
}
