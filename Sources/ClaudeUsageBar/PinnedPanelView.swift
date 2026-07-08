import AppKit
import SwiftUI
import UsageCore

/// The detached picture-in-picture usage widget. Shows the same data as the
/// dropdown, trimmed to the pinned-section prefs, with hover-revealed
/// refresh / settings / close controls and a corner grip that resizes the
/// panel width (content reflows). Drag the body to move it. Observes the one
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
        .background(WindowDragSurface())
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
        // Always reserve room for the hover controls (refresh/gear/close) so
        // they never cover the badge and the header doesn't shift as they fade.
        .padding(.trailing, 88)
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
            // Manual refresh (bypasses backoff) — the frequent action, so it
            // sits leftmost. The signed-out note tells the user to Refresh; this
            // is the button that does it.
            Button { store.refreshNow() } label: {
                hoverControlIcon("arrow.clockwise.circle.fill")
            }
            .disabled(store.isRefreshing)
            Button { SettingsWindowController.shared.show(store: store) } label: {
                hoverControlIcon("gearshape.circle.fill")
            }
            Button {
                store.isPinned = false
                PinnedPanelController.shared.hide()
            } label: {
                hoverControlIcon("xmark.circle.fill")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 14))
        .imageScale(.medium)
        .foregroundStyle(.secondary)
        .padding(8)
    }

    private func hoverControlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }

    // Drag the corner to set the panel WIDTH; content reflows and the height
    // follows. `dragStartWidth` is captured once per gesture so the delta is
    // measured from a fixed base, not the live (changing) width.
    private var resizeGrip: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 12, weight: .bold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture()
                    .onChanged { v in
                        if dragStartWidth == nil { dragStartWidth = store.pinWidth }
                        let base = dragStartWidth ?? store.pinWidth
                        store.pinWidth = PinnedPanelGeometry.clampWidth(base + Double(v.translation.width))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .padding(3)
    }
}

private struct WindowDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> DragSurfaceView {
        DragSurfaceView()
    }

    func updateNSView(_ nsView: DragSurfaceView, context: Context) {}

    final class DragSurfaceView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
