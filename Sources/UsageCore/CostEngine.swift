import Foundation

/// Aggregates token usage from Claude Code JSONL transcripts and computes a
/// notional API-equivalent dollar figure per model, scoped to a time window.
///
/// An actor with a per-file cache: each poll only re-parses transcript files
/// whose modification date changed, so steady-state polling is cheap even with
/// a large history. Window filtering is applied in-memory over cached entries.
public actor CostEngine {
    /// One usage record parsed from a transcript line.
    public struct Entry: Sendable {
        public let date: Date
        public let model: String
        public let tokens: TokenCounts
        public let uuid: String?
    }

    private struct FileCache {
        let mtime: Date
        let entries: [Entry]
    }

    private let projectsDir: URL
    private var cache: [String: FileCache] = [:]

    public init(projectsDir: URL? = nil) {
        if let projectsDir {
            self.projectsDir = projectsDir
        } else {
            self.projectsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        }
    }

    /// Per-model breakdown for transcripts in `[since, now]`, newest cost first.
    /// Dedupes by `uuid` across all files (a resumed session can write the same
    /// message into more than one transcript).
    public func breakdown(since: Date, now: Date = Date()) -> [ModelUsage] {
        var tallies: [String: TokenCounts] = [:]
        var seen = Set<String>()
        for e in collectEntries(since: since) where e.date >= since && e.date <= now {
            if let uuid = e.uuid {
                if seen.contains(uuid) { continue }
                seen.insert(uuid)
            }
            tallies[e.model, default: TokenCounts()] = tallies[e.model, default: TokenCounts()] + e.tokens
        }
        return CostEngine.makeRows(from: tallies)
    }

    /// Gather entries from all recent transcript files, using the cache where
    /// the file is unchanged. Files older than the window are dropped.
    private func collectEntries(since: Date) -> [Entry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var all: [Entry] = []
        var liveKeys = Set<String>()

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            // Don't follow symlinks — a planted link could point outside the tree.
            if rv?.isSymbolicLink == true { continue }
            let key = url.path
            let mtime = rv?.contentModificationDate ?? .distantPast
            if mtime < since { cache[key] = nil; continue }
            liveKeys.insert(key)

            if let cached = cache[key], cached.mtime == mtime {
                all.append(contentsOf: cached.entries)
            } else {
                let entries = CostEngine.parseFile(url)
                cache[key] = FileCache(mtime: mtime, entries: entries)
                all.append(contentsOf: entries)
            }
        }

        // Evict caches for files no longer present / now out of window.
        // Collect first, then remove — mutating while iterating `cache.keys` is unsafe.
        let stale = cache.keys.filter { !liveKeys.contains($0) }
        for key in stale { cache[key] = nil }
        return all
    }

    /// Reads a transcript file line-by-line in bounded chunks instead of loading
    /// the whole thing into memory — a cold scan over a multi-hundred-MB history
    /// would otherwise spike memory (full contents plus a copy of every line).
    /// Splitting on the `\n` byte is UTF-8-safe: 0x0A never appears inside a
    /// multi-byte sequence, so no line is ever cut mid-character.
    private static func parseFile(_ url: URL) -> [Entry] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        var out: [Entry] = []
        var seen = Set<String>()
        var buffer = Data()

        func consume<S: Sequence>(_ lineBytes: S) where S.Element == UInt8 {
            guard let line = String(bytes: lineBytes, encoding: .utf8),
                  !line.isEmpty,
                  let entry = parseLine(line, seen: &seen)
            else { return }
            out.append(entry)
        }

        while case let chunk = handle.readData(ofLength: 1 << 20), !chunk.isEmpty {
            buffer.append(chunk)
            // Split out complete lines; keep the trailing partial line in buffer.
            var pieces = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
            buffer = Data(pieces.removeLast())
            for piece in pieces { consume(piece) }
        }
        consume(buffer)   // final line with no trailing newline
        return out
    }

    // MARK: - Pure helpers (unit tested)

    /// Parse transcript lines into usage entries. Dedupes by `uuid`, skips
    /// synthetic/zero-usage and malformed lines. No time filtering here.
    public static func parseEntries(lines: [String]) -> [Entry] {
        var out: [Entry] = []
        var seen = Set<String>()
        for line in lines {
            if let entry = parseLine(line, seen: &seen) { out.append(entry) }
        }
        return out
    }

    /// Parse one transcript line into an `Entry`, or nil if it's not a
    /// usage-bearing assistant line (or a `uuid` already in `seen`). Shared by
    /// the streaming reader and the pure `parseEntries(lines:)`.
    private static func parseLine(_ line: String, seen: inout Set<String>) -> Entry? {
        // Cheap pre-filter: the token usage object only appears on assistant
        // lines, so skip the (often very large) tool/user lines before the
        // full JSON parse. This is the difference between a fast and a slow
        // cold scan over a big transcript history.
        guard line.contains("\"usage\"") else { return nil }

        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let uuid = obj["uuid"] as? String
        if let uuid {
            if seen.contains(uuid) { return nil }
            seen.insert(uuid)
        }

        guard let tsString = obj["timestamp"] as? String,
              let date = ISO8601DateParser.parse(tsString)
        else { return nil }

        guard let message = obj["message"] as? [String: Any],
              let model = message["model"] as? String,
              model != "<synthetic>",
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        let counts = TokenCounts(
            input: intValue(usage["input_tokens"]),
            output: intValue(usage["output_tokens"]),
            cacheWrite: intValue(usage["cache_creation_input_tokens"]),
            cacheRead: intValue(usage["cache_read_input_tokens"]))

        if counts.total == 0 { return nil }
        return Entry(date: date, model: model, tokens: counts, uuid: uuid)
    }

    /// Tally parsed lines into per-model token counts within `[since, now]`.
    /// Convenience pure entry point for tests.
    public static func aggregate(lines: [String], since: Date, now: Date = Date()) -> [String: TokenCounts] {
        var tallies: [String: TokenCounts] = [:]
        for e in parseEntries(lines: lines) where e.date >= since && e.date <= now {
            tallies[e.model, default: TokenCounts()] = tallies[e.model, default: TokenCounts()] + e.tokens
        }
        return tallies
    }

    /// Build sorted breakdown rows from raw per-model tallies. Pure + testable.
    public static func makeRows(from tallies: [String: TokenCounts]) -> [ModelUsage] {
        tallies.compactMap { (modelID, tokens) -> ModelUsage? in
            guard let price = PriceTable.price(forModelID: modelID) else { return nil }
            return ModelUsage(
                modelID: modelID,
                displayName: PriceTable.displayName(forModelID: modelID),
                tokens: tokens,
                costUSD: PriceTable.cost(price: price, tokens: tokens))
        }
        .sorted { $0.costUSD > $1.costUSD }
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return 0
    }
}
