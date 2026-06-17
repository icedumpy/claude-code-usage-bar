import Foundation

/// Per-million-token prices used only for the notional "API-equivalent" dollar
/// figure in the dropdown. The plan is flat-fee, so this is "value extracted",
/// not real spend. Values are public list prices and easy to update here.
public struct ModelPrice: Sendable {
    public let input: Double        // $ per 1M input tokens
    public let output: Double       // $ per 1M output tokens
    public let cacheWrite: Double   // $ per 1M cache-creation tokens
    public let cacheRead: Double    // $ per 1M cache-read tokens

    public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }
}

public enum PriceTable {
    /// Family prices (per 1M tokens). Cache-write ≈ 1.25× input, cache-read ≈ 0.1× input.
    static let opus = ModelPrice(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)
    static let sonnet = ModelPrice(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)
    static let haiku = ModelPrice(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1)

    /// Map a raw model id (e.g. "claude-opus-4-8") to a price by family.
    /// Returns nil for synthetic/unknown models so they can be skipped.
    public static func price(forModelID id: String) -> ModelPrice? {
        let m = id.lowercased()
        if m.contains("opus") { return opus }
        if m.contains("sonnet") { return sonnet }
        if m.contains("haiku") { return haiku }
        return nil
    }

    /// Friendly display name from a raw model id, best-effort.
    public static func displayName(forModelID id: String) -> String {
        let m = id.lowercased()
        func ver(_ family: String) -> String {
            // turn "claude-opus-4-8" -> "Opus 4.8"
            let digits = id.split(whereSeparator: { !$0.isNumber }).map(String.init)
            if digits.count >= 2 { return "\(family) \(digits[0]).\(digits[1])" }
            if digits.count == 1 { return "\(family) \(digits[0])" }
            return family
        }
        if m.contains("opus") { return ver("Opus") }
        if m.contains("sonnet") { return ver("Sonnet") }
        if m.contains("haiku") { return ver("Haiku") }
        return id
    }

    public static func cost(price: ModelPrice, tokens: TokenCounts) -> Double {
        (Double(tokens.input) * price.input
            + Double(tokens.output) * price.output
            + Double(tokens.cacheWrite) * price.cacheWrite
            + Double(tokens.cacheRead) * price.cacheRead) / 1_000_000.0
    }
}

/// Raw token tallies for a model.
public struct TokenCounts: Sendable, Equatable {
    public var input: Int = 0
    public var output: Int = 0
    public var cacheWrite: Int = 0
    public var cacheRead: Int = 0

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public var total: Int { input + output + cacheWrite + cacheRead }

    public static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input,
                    output: a.output + b.output,
                    cacheWrite: a.cacheWrite + b.cacheWrite,
                    cacheRead: a.cacheRead + b.cacheRead)
    }
}

/// One row of the per-model cost breakdown.
public struct ModelUsage: Sendable, Identifiable, Equatable {
    public let modelID: String
    public let displayName: String
    public let tokens: TokenCounts
    public let costUSD: Double
    public var id: String { modelID }
}
