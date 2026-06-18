# Pinned PiP panel — design

A chromeless, always-on-top usage widget the user can detach from the menu-bar
dropdown, like a YouTube picture-in-picture window.

## Behavior

- Floating `NSPanel`: `.nonactivatingPanel` + `.borderless`, `level = .floating`,
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` — visible on
  every Space and over fullscreen apps, never steals focus.
- `movableByWindowBackground` — drag from anywhere on the body.
- Rounded, semi-transparent body; chromeless. Hover reveals `×` (unpin) and `⚙`
  (open Settings) in the top corners with no layout shift.
- Resize by a hover-revealed corner grip that zooms the content (`scaleEffect`),
  clamped 0.8x–1.6x. Avoids AppKit borderless-resize fiddliness; the panel
  auto-sizes to the scaled content.
- Persists across launches: on/off, frame (origin + scale), opacity, section
  toggles. If the saved frame is off the visible screen (monitor changed),
  re-center on the current `visibleFrame`.

## Content (default = all limits, no model table)

- Header: title + subscription badge.
- Limit rows: the active 5-hour row always; weekly rows when `pinShowWeekly`;
  per-model breakdown table when `pinShowModels` (default off).
- Honors `vizStyle` (bars or rabbit/turtle race), same as the dropdown.
- Same phase handling as the dropdown (loading / signed-out / error → last
  snapshot or a note).

## Components

- `PinnedPanelController` (`@MainActor` singleton, mirrors
  `SettingsWindowController`): owns the panel, window flags, chromeless rounded
  styling, opacity, frame persistence, show/hide/toggle. Auto-sizes to content.
- `PinnedPanelView` (SwiftUI): the content above, observing the shared
  `UsageStore`; hover controls; corner resize grip driving the scale.
- Shared rows: lift `LimitRowView` in `DropdownView.swift` from `private` to
  internal so the dropdown and the PiP render rows identically (no behavior
  change to the dropdown).
- `DropdownView` footer: a **Pin** button toggling the panel.
- `SettingsView`: a **Pinned panel** section — Opacity slider (40–100%) and
  section toggles (Weekly limits default on, Per-model breakdown default off).

## State (on `UsageStore`, UserDefaults-backed, like existing prefs)

`isPinned: Bool`, `pinOpacity: Double`, `pinShowWeekly: Bool`,
`pinShowModels: Bool`. Frame (origin + scale) persisted by the controller.

## Data flow

One `UsageStore` (from `AppDelegate`) is observed by the menu-bar label, the
dropdown, and the PiP — all update together each refresh. No new polling.

## Testing

Windowing/SwiftUI is verified by build + manual (toggle, drag, resize, opacity,
section toggles, relaunch persistence, multi-Space/fullscreen). The one piece
with real logic — opacity/scale clamping and off-screen frame correction — goes
in a pure `PinnedPanelGeometry` helper in `UsageCore` with unit tests.
