import Foundation
import UsageCore

/// Reads the Claude Code credential by invoking `/usr/bin/security`. This is the
/// production credential path for both the GUI app and `--probe`: the `security`
/// tool is already trusted for the Keychain item, so it reads the token without
/// the blocking ACL dialog that a direct Security-framework call would trigger
/// for a freshly ad-hoc-signed app.
struct ShellCredentialProvider: CredentialReading {
    let service: String

    init(service: String = "Claude Code-credentials") {
        self.service = service
    }

    func read() throws -> Credentials {
        // `Process` with an argv array uses execve (no shell), so shell
        // metacharacters are inert. This guard only prevents a service name from
        // being misread as a `security` flag.
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
        return try Credentials.parse(Data(trimmed.utf8))
    }
}
