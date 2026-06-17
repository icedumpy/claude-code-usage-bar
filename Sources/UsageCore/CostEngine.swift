import Foundation

/// Aggregates token usage from Claude Code JSONL transcripts and computes a
/// notional API-equivalent dollar figure per model, scoped to a time window.
public struct CostEngine {
    private let projectsDir: URL
    private let fm = FileManager.default

    public init(projectsDir: URL? = nil) {
        if let projectsDir {
            self.projectsDir = projectsDir
        } else {
            self.projectsDir = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        }
    }

    /// Per-model breakdown for transcripts since `since`, newest cost first.
    public func breakdown(since: Date, now: Date = Date()) -> [ModelUsage] {
        let tallies = aggregateFiles(since: since, now: now)
        return CostEngine.makeRows(from: tallies)
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

    /// Read recent transcript files and aggregate. Files untouched since before
    /// the window are skipped via modification date for efficiency.
    private func aggregateFiles(since: Date, now: Date) -> [String: TokenCounts] {
        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var tallies: [String: TokenCounts] = [:]
        var seen = Set<String>()

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mod = values?.contentModificationDate, mod < since { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            CostEngine.aggregate(lines: content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init),
                                 since: since, now: now,
                                 into: &tallies, seen: &seen)
        }
        return tallies
    }

    /// Pure aggregation over JSONL lines. Dedupes by `uuid`, filters by
    /// timestamp window, skips synthetic/unpriced models and malformed lines.
    public static func aggregate(lines: [String],
                                 since: Date,
                                 now: Date = Date(),
                                 into tallies: inout [String: TokenCounts],
                                 seen: inout Set<String>) {
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }

            // dedup
            if let uuid = obj["uuid"] as? String {
                if seen.contains(uuid) { continue }
                seen.insert(uuid)
            }

            // time window
            if let ts = obj["timestamp"] as? String, let date = ISO8601DateParser.parse(ts) {
                if date < since || date > now { continue }
            } else {
                continue // no usable timestamp -> can't scope, skip
            }

            guard let message = obj["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  model != "<synthetic>",
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            let counts = TokenCounts(
                input: intValue(usage["input_tokens"]),
                output: intValue(usage["output_tokens"]),
                cacheWrite: intValue(usage["cache_creation_input_tokens"]),
                cacheRead: intValue(usage["cache_read_input_tokens"]))

            if counts.total == 0 { continue }
            tallies[model, default: TokenCounts()] = tallies[model, default: TokenCounts()] + counts
        }
    }

    /// Convenience pure entry point for tests.
    public static func aggregate(lines: [String], since: Date, now: Date = Date()) -> [String: TokenCounts] {
        var t: [String: TokenCounts] = [:]
        var seen = Set<String>()
        aggregate(lines: lines, since: since, now: now, into: &t, seen: &seen)
        return t
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return 0
    }
}
