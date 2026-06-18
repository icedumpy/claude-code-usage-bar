import SwiftUI
import UsageCore

struct DropdownView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if let update = store.updateInfo {
                updateBanner(update)
                Divider()
            }
            content
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private func updateBanner(_ update: UpdateInfo) -> some View {
        Button {
            if let url = URL(string: update.url) { NSWorkspace.shared.open(url) }
        } label: {
            Label("Update available — v\(update.version)", systemImage: "arrow.down.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            Text("Claude Usage").font(.headline)
            Spacer()
            if case .ok(let snap) = store.phase, let sub = snap.subscriptionType {
                Text(sub.capitalized)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .loading:
            centeredNote("Loading…")
        case .signedOut:
            VStack(alignment: .leading, spacing: 4) {
                Label("No usage to show", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Sign in to Claude Code with a Claude subscription, then Refresh. Pay-as-you-go API-key usage isn't reported here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .ok(let snap):
            snapshotView(snap)
        case .error:
            if let snap = store.lastSnapshot { snapshotView(snap) }
            else { centeredNote("Updating…") }
        }
    }

    private func centeredNote(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
    }

    private func snapshotView(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 11) {
                ForEach(snap.limitRows) { LimitRowView(row: $0, style: store.vizStyle) }
            }
            if !snap.models.isEmpty {
                Divider()
                Text("THIS WEEK — BY MODEL")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                VStack(spacing: 5) {
                    ForEach(snap.models) { m in
                        modelRow(m.displayName, tokens: m.tokens.total, cost: m.costUSD, bold: false)
                    }
                    Divider().padding(.vertical, 1)
                    modelRow("Total", tokens: snap.totalTokens, cost: snap.totalCostUSD, bold: true)
                }
            }
        }
    }

    private func modelRow(_ name: String, tokens: Int, cost: Double, bold: Bool) -> some View {
        HStack {
            Text(name).font(bold ? .callout.weight(.semibold) : .callout)
            Spacer()
            Text(Formatting.tokens(tokens)).font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(Formatting.dollars(cost))
                .font(bold ? .callout.weight(.semibold).monospacedDigit() : .callout.monospacedDigit())
                .frame(width: 58, alignment: .trailing)
        }
    }

    private var footer: some View {
        // The timestamp gets its own line so it never gets squeezed/truncated
        // by the button row below it.
        VStack(alignment: .leading, spacing: 6) {
            if let u = store.lastUpdated {
                Text("updated \(u.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button(store.isPinned ? "Unpin" : "Pin") {
                    store.isPinned.toggle()
                    if store.isPinned { PinnedPanelController.shared.show(store: store) }
                    else { PinnedPanelController.shared.hide() }
                }
                Button("Settings…") { SettingsWindowController.shared.show(store: store) }
                Spacer()
                Button(store.isRefreshing ? "Refreshing…" : "Refresh") { store.refreshNow() }
                    .disabled(store.isRefreshing)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
    }
}

struct LimitRowView: View {
    let row: LimitRow
    let style: VisualizationStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(row.label)
                    .font(.callout.weight(row.isHero ? .semibold : .regular))
                if row.isHero {
                    Text("now")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(SeverityStyle.color(row.severity).opacity(0.18), in: Capsule())
                        .foregroundStyle(SeverityStyle.color(row.severity))
                }
                Spacer()
                Text(Formatting.percent(row.percent))
                    .font(.callout.monospacedDigit().weight(.semibold))
            }
            switch style {
            case .bars: bars
            case .race:
                RaceTrackView(percent: row.percent,
                              elapsedFraction: row.elapsedFraction,
                              severity: row.severity)
            }
            HStack(spacing: 4) {
                Text(Formatting.reset(to: row.resetsAt)).foregroundStyle(.tertiary)
                if !pace.text.isEmpty {
                    Spacer()
                    Text(pace.text).foregroundStyle(pace.color)
                }
            }
            .font(.caption2)
        }
    }

    // Usage racing the clock: labeled usage bar over a red time bar.
    @ViewBuilder private var bars: some View {
        HStack(spacing: 6) {
            Text("used").frame(width: 26, alignment: .leading)
            CapsuleBar(value: row.percent, color: SeverityStyle.color(row.severity), height: 6)
        }
        .font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
        if let elapsed = row.elapsedFraction {
            HStack(spacing: 6) {
                Text("time").frame(width: 26, alignment: .leading)
                CapsuleBar(value: elapsed * 100, color: .red.opacity(0.65), height: 3)
            }
            .font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
        }
    }

    /// Is usage outrunning the clock? Colored so the verdict is unmistakable:
    /// orange = burning faster than time, green = comfortably behind.
    private var pace: (text: String, color: Color) {
        guard let elapsed = row.elapsedFraction else { return ("", .secondary) }
        let usage = row.percent / 100
        if usage > elapsed + 0.08 { return ("ahead of pace", .orange) }
        if usage < elapsed - 0.08 { return ("behind pace", .green) }
        return ("on pace", .secondary)
    }
}

/// Two SF Symbol racers on a shared lane: a rabbit (= usage) and a turtle
/// (= time-elapsed). Horizontal position carries the data; a gentle idle wobble
/// keeps them alive. Stateless — purely a function of the current snapshot, so
/// there is nothing to retain between refreshes. Rabbit ahead of turtle means
/// usage is outrunning the clock. Rows without a time window (e.g. weekly) have
/// no turtle and just show the lone rabbit.
private struct RaceTrackView: View {
    let percent: Double            // 0...100, usage
    let elapsedFraction: Double?   // 0...1, fraction of the window elapsed
    let severity: Severity

    @State private var wobble = false

    private let glyph: CGFloat = 13
    private let trackHeight: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            // Inset so the glyph centers never clip at the lane ends.
            let inset = glyph / 2 + 2
            let usable = max(1, geo.size.width - inset * 2)
            let midY = geo.size.height / 2
            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 2)
                    .position(x: geo.size.width / 2, y: midY)

                if let elapsed = elapsedFraction {
                    racer("tortoise.fill", color: .red.opacity(0.65))
                        .accessibilityLabel(Text("Time elapsed: \(Int((elapsed * 100).rounded()))%"))
                        .position(x: inset + usable * clamp01(elapsed), y: midY + 5)
                        // Slide to the new spot when a refresh lands.
                        .animation(.easeOut(duration: 0.6), value: elapsed)
                }
                racer("hare.fill", color: SeverityStyle.color(severity))
                    .accessibilityLabel(Text("Usage: \(Int(percent.rounded()))%"))
                    .position(x: inset + usable * clamp01(percent / 100), y: midY - 5)
                    .animation(.easeOut(duration: 0.6), value: percent)
            }
            // Suppress the first-layout flash when GeometryReader reports zero width.
            .opacity(geo.size.width > 1 ? 1 : 0)
        }
        .frame(height: trackHeight)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                wobble = true
            }
        }
    }

    private func racer(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: glyph))
            .foregroundStyle(color)
            .rotationEffect(.degrees(wobble ? 4 : -4), anchor: .bottom)
    }

    private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
}

/// A rounded bar (nicer than the default ProgressView at this size).
private struct CapsuleBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(color)
                    .frame(width: max(3, geo.size.width * min(value, 100) / 100))
            }
        }
        .frame(height: height)
    }
}
