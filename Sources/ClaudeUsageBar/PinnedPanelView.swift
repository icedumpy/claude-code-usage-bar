import AppKit
import SwiftUI
import UsageCore

/// The detached picture-in-picture usage widget. Shows the same data as the
/// dropdown, trimmed to the pinned-section prefs, with hover-revealed
/// refresh / settings / close controls and a right-edge handle that resizes the
/// panel width (content reflows). Drag the body to move it. Observes the one
/// shared UsageStore, so it updates every refresh alongside the menu bar.
struct PinnedPanelView: View {
    @ObservedObject var store: UsageStore

    @State private var hovering = false
    // Start width captured for the active resize drag. A @GestureState (not
    // @State) so SwiftUI resets it to nil the instant the gesture ends OR is
    // cancelled — even if the mouse-up lands off-window and no .onEnded fires —
    // making a stale base impossible. Non-nil also means "resizing now", which
    // keeps the handle mounted while the cursor is off the panel (past max width).
    @GestureState private var dragStartWidth: Double?

    var body: some View {
        panelBody
            .frame(width: CGFloat(store.pinWidth), alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) { if hovering { hoverControls } }
            .overlay(alignment: .trailing) { if hovering || dragStartWidth != nil { resizeGrip } }
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

    // Title with the plan pill grouped right after it. The hover controls fade
    // in over the empty right side (they no longer reserve fixed space), so the
    // pill sits next to the title instead of floating in dead space.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Claude Usage").font(.subheadline.weight(.semibold)).lineLimit(1)
            if let sub = currentSnapshot?.subscriptionType {
                Text(sub.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        // Reserve room for the hover cluster only while it's visible. The Spacer
        // absorbs this at normal widths (no movement); at the minimum width it
        // nudges the pill left so the cluster never sits on top of it.
        .padding(.trailing, hovering ? 88 : 0)
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
            Text("By model")
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
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

    // The three actions grouped into one translucent cluster (refresh leftmost —
    // the frequent action, and the button the signed-out note points at). One
    // cluster reads far more modern than three loose floating symbols.
    private var hoverControls: some View {
        HStack(spacing: 10) {
            clusterButton("arrow.clockwise", label: "Refresh") { store.refreshNow() }
                .disabled(store.isRefreshing)
            clusterButton("gearshape", label: "Settings") { SettingsWindowController.shared.show(store: store) }
            clusterButton("xmark", label: "Close panel") {
                store.isPinned = false
                PinnedPanelController.shared.hide()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .padding(6)
    }

    private func clusterButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                // Larger hit target than the visible glyph, per review.
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .help(label)
    }

    // Width resize: a slim right-edge handle — an honest signal for horizontal-
    // only resize (a corner diagonal would imply 2D). The hit zone spans the
    // full right edge (~18pt) though the visible capsule is thin, and a native
    // resize cursor confirms the affordance. The drag is measured in .global
    // space so the handle sliding under the cursor as the panel grows doesn't
    // feed back. `.updating` captures the start width once per gesture and
    // SwiftUI clears it on end/cancel, so the base can never go stale.
    private var resizeGrip: some View {
        Color.clear
            .frame(width: 18)
            .overlay {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.42))
                    .frame(width: 4, height: 28)
            }
            .contentShape(Rectangle())
            .background(ResizeCursorArea())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($dragStartWidth) { _, base, _ in
                        if base == nil { base = store.pinWidth }
                    }
                    .onChanged { v in
                        let base = dragStartWidth ?? store.pinWidth
                        store.pinWidth = PinnedPanelGeometry.clampWidth(base + Double(v.translation.width))
                    }
            )
    }
}

/// A hover region that shows the horizontal-resize cursor. Uses cursor rects
/// (available on macOS 13) rather than `.pointerStyle` (macOS 15+) or manual
/// NSCursor push/pop (which can leave an unbalanced cursor stack if the view
/// disappears mid-hover).
private struct ResizeCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ nsView: CursorView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
    final class CursorView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
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
