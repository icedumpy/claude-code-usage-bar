import SwiftUI
import UsageCore

/// The detached picture-in-picture usage widget. Shows the same data as the
/// dropdown, trimmed to the pinned-section prefs, with hover-revealed close /
/// settings controls and a corner grip that zooms the content. Observes the one
/// shared UsageStore, so it updates every refresh alongside the menu bar.
struct PinnedPanelView: View {
    @ObservedObject var store: UsageStore

    @State private var hovering = false
    @State private var dragStartWidth: Double?

    var body: some View {
        panelBody
            .frame(width: CGFloat(store.pinWidth), alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) { if hovering { hoverControls } }
            .overlay(alignment: .bottomTrailing) { if hovering { resizeGrip } }
            .opacity(store.pinOpacity)
            .animation(.easeInOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }

    // MARK: content

    @ViewBuilder private var panelBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            switch store.phase {
            case .loading where store.lastSnapshot == nil:
                note("Loading…")
            case .signedOut:
                note("Sign in to Claude Code, then Refresh.")
            default:
                if let snap = currentSnapshot {
                    rows(snap)
                    if store.pinShowModels, !snap.models.isEmpty { modelTable(snap) }
                } else {
                    note("Updating…")
                }
            }
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Claude Usage").font(.subheadline.weight(.semibold))
            Spacer()
            if let sub = currentSnapshot?.subscriptionType {
                Text(sub.capitalized)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
        // Always reserve room for the hover controls so they never cover the
        // badge and the header doesn't shift when they fade in.
        .padding(.trailing, 36)
    }

    private func rows(_ snap: UsageSnapshot) -> some View {
        // "Show weekly limits" off trims to the limit driving the menu bar, so
        // the panel and the menu bar always talk about the same window.
        VStack(spacing: 10) {
            ForEach(snap.limitRows.filter { $0.id == store.heroRowID || store.pinShowWeekly }) { row in
                LimitRowView(row: row, style: store.vizStyle,
                             isHero: row.id == store.heroRowID)
            }
        }
    }

    private func modelTable(_ snap: UsageSnapshot) -> some View {
        VStack(spacing: 4) {
            Divider()
            Text("THIS WEEK — BY MODEL")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(snap.models) { m in
                HStack {
                    Text(m.displayName).font(.caption)
                    Spacer()
                    Text(Formatting.dollars(m.costUSD)).font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private var currentSnapshot: UsageSnapshot? {
        if case .ok(let s) = store.phase { return s }
        return store.lastSnapshot
    }

    // MARK: hover controls + resize

    private var hoverControls: some View {
        HStack(spacing: 8) {
            Button { SettingsWindowController.shared.show(store: store) } label: {
                Image(systemName: "gearshape.fill")
            }
            Button {
                store.isPinned = false
                PinnedPanelController.shared.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(8)
    }

    // Drag the corner to set the panel WIDTH; content reflows and the height
    // follows. `dragStartWidth` is captured once per gesture so the delta is
    // measured from a fixed base, not the live (changing) width.
    private var resizeGrip: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(.secondary)
            .padding(6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        if dragStartWidth == nil { dragStartWidth = store.pinWidth }
                        let base = dragStartWidth ?? store.pinWidth
                        store.pinWidth = PinnedPanelGeometry.clampWidth(base + Double(v.translation.width))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
    }
}
