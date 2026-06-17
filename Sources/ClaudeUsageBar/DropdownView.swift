import SwiftUI
import UsageCore

struct DropdownView: View {
    @ObservedObject var store: UsageStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

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
                Label("No usage to show", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Sign in to Claude Code with a Claude subscription, then Refresh. Pay-as-you-go API-key usage isn't reported here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .ok(let snap):
            snapshotView(snap)
        case .error:
            // No scary banner — just keep showing the last-known data.
            if let snap = store.lastSnapshot {
                snapshotView(snap)
            } else {
                HStack { ProgressView().controlSize(.small); Text("Updating…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
            }
        }
    }

    private func snapshotView(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox).font(.caption)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLogin.set(newValue)
                        // Reconcile with the real status; if register/unregister
                        // failed, the checkbox snaps back to the true state.
                        let actual = LaunchAtLogin.isEnabled
                        if actual != newValue { launchAtLogin = actual }
                    }
                Toggle("Alerts", isOn: $store.alertsEnabled)
                    .toggleStyle(.checkbox).font(.caption)
                    .help("Notify at 80% and 95% of a limit")
                Spacer()
                Button(store.isRefreshing ? "Refreshing…" : "Refresh") { store.refreshNow() }
                    .disabled(store.isRefreshing)
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
