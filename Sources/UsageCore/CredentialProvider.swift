import Foundation

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

    /// Parse the Claude Code credential JSON blob. Pure + testable.
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

public enum CredentialError: Error, Equatable {
    case notFound    // no keychain item — user never logged into Claude Code
    case malformed
}

/// Reads the Claude Code OAuth credential. The app uses `ShellCredentialProvider`
/// (which invokes `/usr/bin/security`) rather than the Security framework,
/// because a freshly ad-hoc-signed app is not in the Keychain item's trust list
/// and a direct `SecItemCopyMatching` would pop a blocking ACL dialog.
public protocol CredentialReading: Sendable {
    func read() throws -> Credentials
}
