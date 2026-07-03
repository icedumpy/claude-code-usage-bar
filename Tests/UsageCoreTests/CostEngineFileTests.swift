import Testing
import Foundation
@testable import UsageCore

/// Exercises the streaming file reader (`parseFile`) end-to-end through the
/// actor, which the pure `parseEntries` tests don't cover.
@Suite struct CostEngineFileTests {
    let since = ISO8601DateParser.parse("2026-06-14T00:00:00Z")!
    let now = ISO8601DateParser.parse("2026-06-20T00:00:00Z")!

    private func line(uuid: String, model: String, inp: Int, out: Int) -> String {
        #"{"uuid":"\#(uuid)","timestamp":"2026-06-16T10:00:00Z","type":"assistant","message":{"model":"\#(model)","usage":{"input_tokens":\#(inp),"output_tokens":\#(out),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
    }

    /// Writes `contents` to a fresh temp projects dir and returns a CostEngine
    /// pointed at it. Caller must not rely on cleanup — temp dirs are fine.
    private func engine(withFile contents: String) throws -> CostEngine {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cost-file-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dir.appendingPathComponent("session.jsonl"))
        return CostEngine(projectsDir: dir)
    }

    @Test func readsMultipleLinesAndDedupesWithinFile() async throws {
        // Three lines, last with NO trailing newline; the middle uuid repeats.
        let contents = [
            line(uuid: "a", model: "claude-opus-4-8", inp: 100, out: 50),
            line(uuid: "b", model: "claude-opus-4-8", inp: 100, out: 50),
            line(uuid: "b", model: "claude-opus-4-8", inp: 999, out: 999),
        ].joined(separator: "\n")   // no trailing "\n"

        let rows = try await engine(withFile: contents).breakdown(since: since, now: now)
        let opus = try #require(rows.first { $0.modelID == "claude-opus-4-8" })
        #expect(opus.tokens.input == 200)   // a + b once; the duplicate b is dropped
        #expect(opus.tokens.output == 100)
    }

    @Test func readsFileLargerThanReadChunk() async throws {
        // Enough unique lines to exceed the 1 MB read chunk, so the reader must
        // stitch lines across chunk boundaries correctly.
        var lines: [String] = []
        var expected = 0
        for i in 0..<8000 {
            lines.append(line(uuid: "u\(i)", model: "claude-opus-4-8", inp: 10, out: 0))
            expected += 10
        }
        let contents = lines.joined(separator: "\n") + "\n"
        #expect(contents.utf8.count > (1 << 20))   // guard: actually crosses a chunk

        let rows = try await engine(withFile: contents).breakdown(since: since, now: now)
        let opus = try #require(rows.first { $0.modelID == "claude-opus-4-8" })
        #expect(opus.tokens.input == expected)
    }
}
