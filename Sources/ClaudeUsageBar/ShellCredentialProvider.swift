import Foundation
import UsageCore

/// Reads the Claude Code credential by invoking `/usr/bin/security`, which the
/// user has already granted access to (no GUI prompt). Used only by `--probe`
/// for headless verification; the GUI app uses KeychainCredentialProvider.
struct ShellCredentialProvider: CredentialReading {
    let service: String

    init(service: String = "Claude Code-credentials") {
        self.service = service
    }

    func read() throws -> Credentials {
        // Guard against a service name being interpreted as a `security` flag.
        precondition(!service.hasPrefix("-"), "service name must not start with '-'")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw CredentialError.notFound }
        let trimmed = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try KeychainCredentialProvider.parse(Data(trimmed.utf8))
    }
}
