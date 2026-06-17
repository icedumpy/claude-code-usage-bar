import SwiftUI
import UsageCore

struct DropdownView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Claude Usage").font(.headline)
            Spacer()
            if case .ok(let snap) = store.phase, let sub = snap.subscriptionType {
                Text(sub.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .loading:
            HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
        case .signedOut:
            VStack(alignment: .leading, spacing: 4) {
                Label("Not signed in", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Open Claude Code and log in, then hit Refresh.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .ok(let snap):
            snapshotView(snap, stale: nil)
        case .error(let msg):
            if let snap = store.lastSnapshot {
                snapshotView(snap, stale: msg)
            } else {
                Label(msg, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
            }
        }
    }

    private func snapshotView(_ snap: UsageSnapshot, stale: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let stale {
                Text("\(stale) · showing last known")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(snap.limitRows) { row in
                    LimitRowView(row: row)
                }
            }

            if !snap.models.isEmpty {
                Divider()
                Text("This week — by model")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    ForEach(snap.models) { m in
                        HStack {
                            Text(m.displayName).font(.callout)
                            Spacer()
                            Text(Formatting.tokens(m.tokens.total)).font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(Formatting.dollars(m.costUSD)).font(.callout.monospacedDigit())
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    Divider().padding(.vertical, 1)
                    HStack {
                        Text("Total").font(.callout.weight(.semibold))
                        Spacer()
                        Text(Formatting.tokens(snap.totalTokens)).font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(Formatting.dollars(snap.totalCostUSD)).font(.callout.weight(.semibold).monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Refresh", selection: $store.refreshInterval) {
                    Text("15s").tag(TimeInterval(15))
                    Text("30s").tag(TimeInterval(30))
                    Text("60s").tag(TimeInterval(60))
                    Text("5m").tag(TimeInterval(300))
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
                Spacer()
                if let u = store.lastUpdated {
                    Text("updated \(u.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.set($0) }))
                    .toggleStyle(.checkbox).font(.caption)
                Spacer()
                Button("Refresh") { store.refreshNow() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}

private struct LimitRowView: View {
    let row: LimitRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(row.label)
                    .font(.callout.weight(row.isHero ? .semibold : .regular))
                if row.isHero {
                    Text("now").font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(SeverityStyle.color(row.severity).opacity(0.2), in: Capsule())
                }
                Spacer()
                Text(Formatting.percent(row.percent))
                    .font(.callout.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: min(row.percent, 100), total: 100)
                .tint(SeverityStyle.color(row.severity))
                .controlSize(.small)
            Text(Formatting.reset(to: row.resetsAt))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
