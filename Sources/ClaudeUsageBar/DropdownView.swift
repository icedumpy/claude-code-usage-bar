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
                ForEach(snap.limitRows) { LimitRowView(row: $0) }
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
        HStack(spacing: 8) {
            if let u = store.lastUpdated {
                Text("updated \(u.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings…") { SettingsWindowController.shared.show(store: store) }
            Button(store.isRefreshing ? "Refreshing…" : "Refresh") { store.refreshNow() }
                .disabled(store.isRefreshing)
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
    }
}

private struct LimitRowView: View {
    let row: LimitRow

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
            // Usage racing the clock: labeled usage bar over a red time bar.
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
