# iPhone usage widget via Scriptable (sync from Mac)

Date: 2026-07-06
Status: Design approved, pending spec review

## Goal

Show Claude Code rate-limit usage on an iPhone home-screen (and optionally
lock-screen) widget, synced from the Mac app, so the user can check or flex
usage without opening the Mac.

## Why Scriptable instead of a native widget

A native WidgetKit widget needs App Group + iCloud entitlements to sync across
devices. Apple gates both behind a **paid** Developer account ($99/yr); free
provisioning explicitly excludes them. The user has no paid account, so the
native path is blocked at the provisioning layer.

Scriptable (free iOS app) builds home/lock-screen widgets from a JavaScript
file and can read files from its own iCloud Drive folder. The Mac app is not
sandboxed, so it can write a plain JSON file into that folder with **no
entitlements and no signing change** — the public `curl | bash` build is
untouched. iCloud Drive syncs the file to the phone; the Scriptable widget
reads and renders it.

## Architecture

```
Mac app refresh (success)
  -> encode SyncSnapshot (JSON)
  -> write usage.json to Scriptable's iCloud Drive Documents folder
        ~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/
  == iCloud Drive syncs ==>
  iPhone: Scriptable widget script reads usage.json
  -> draws hero ring + percent + reset countdown
```

- **No token, no history, no entitlements.** Only computed numbers cross the
  wire. The OAuth token never leaves the Mac.
- **Stale-tolerant by design.** iCloud Drive sync and Scriptable's widget
  refresh both run on the OS budget, not real time. The widget shows
  "updated Xm ago" and greys out when the file is old (Mac off).

## Data contract: `SyncSnapshot`

A small `Codable` in `UsageCore` (the only shared, platform-neutral target),
serialized to JSON. Fields (v1):

| Field         | Type    | Meaning                                        |
|---------------|---------|------------------------------------------------|
| `schema`      | Int     | Contract version (start at 1) for forward-compat |
| `heroPercent` | Double? | Hero limit percent (nil if unknown)            |
| `heroLabel`   | String  | e.g. "session"                                 |
| `severity`    | String  | normal / warn / crit / unknown (for tint)      |
| `resetsAt`    | String? | ISO-8601; widget computes countdown            |
| `weeklyUSD`   | Double  | Notional API-equivalent weekly dollars         |
| `updatedAt`   | String  | ISO-8601 write time; drives staleness display  |

`schema` lets the widget refuse to render an unknown future format instead of
drawing garbage.

## Mac side

- `SyncSnapshot` type + a mapping from the existing display snapshot to it, in
  `UsageCore` (pure, unit-testable).
- A writer (`ScriptableSyncWriter` or similar) invoked from
  `UsageStore.refresh()` on the success path only.
- **Best-effort and silent:** if the Scriptable Documents folder does not exist
  (Scriptable not installed / not yet synced), skip the write. Never surface an
  error, never block a refresh. Write atomically (temp file + rename) so the
  widget never reads a half-written file.
- Ships in the **public** build — needs no entitlement.

## Phone side

- `scriptable/usage-widget.js` committed to the repo. The user pastes it into
  Scriptable once.
- Reads `usage.json` from Scriptable's own Documents dir via
  `FileManager.iCloud()`.
- Small widget: hero percent ring (tinted by `severity`), `heroLabel`, and a
  reset countdown derived from `resetsAt`.
- Fallbacks: file missing -> "Open the Mac app"; stale (updatedAt older than a
  threshold, e.g. 30 min) -> dim + show age.

## What the user does (one-time)

1. Install **Scriptable** from the App Store (free).
2. Ensure iCloud Drive is enabled for Scriptable (Settings -> Apple ID ->
   iCloud -> Drive -> Scriptable on). This makes the Scriptable folder appear
   in the Mac's iCloud Drive so the Mac app can write into it.
3. Run the updated Mac app once so it writes `usage.json`.
4. In Scriptable: create a new script, paste `scriptable/usage-widget.js`, name
   it e.g. "ClaudeUsage".
5. On the home screen: long-press -> add a Scriptable widget (small) -> edit
   widget -> pick the "ClaudeUsage" script.

## Testing

- Unit-test `SyncSnapshot` encoding + the display-snapshot -> snapshot mapping
  in `UsageCoreTests`.
- Unit-test the writer's atomic-write and skip-when-folder-absent behavior
  (point it at a temp dir).
- Manual: run Mac app, confirm `usage.json` appears in the Scriptable folder and
  the widget renders on the phone.

## Out of scope (v1)

- Native SwiftUI widget (revisit if a paid dev account is acquired; the native
  KVS/App Group design from this session's brainstorm is captured and ready).
- Lock-screen accessory widget (easy Scriptable follow-up once v1 lands).
- Any settings toggle for the writer (always best-effort; add later if needed).
