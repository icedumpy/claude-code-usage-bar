import Foundation

public enum UsageError: Error, Equatable {
    case unauthorized          // 401 — token expired / logged out
    case http(Int)
    case network
    case decoding
}

public protocol UsageFetching: Sendable {
    func fetch() async throws -> UsageResponse
}

/// Calls `GET /api/oauth/usage` with the OAuth bearer token + beta header,
/// exactly as Claude Code's own `/usage` does.
public struct UsageClient: UsageFetching {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let credentials: CredentialReading
    private let session: URLSession

    public init(credentials: CredentialReading, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func fetch() async throws -> UsageResponse {
        let creds = try credentials.read()
        var req = URLRequest(url: UsageClient.endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("ClaudeUsageBar/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw UsageError.network
        }
        guard let http = response as? HTTPURLResponse else { throw UsageError.network }
        if http.statusCode == 401 || http.statusCode == 403 { throw UsageError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw UsageError.http(http.statusCode) }

        do {
            return try UsageResponse.decoder().decode(UsageResponse.self, from: data)
        } catch {
            throw UsageError.decoding
        }
    }
}
