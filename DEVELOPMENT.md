# Development

Internals, build instructions, and the release process for Claude Usage Bar.
User-facing setup is in the [README](README.md).

## How it works

Two data sources:

1. **Rate limits** — `GET https://api.anthropic.com/api/oauth/usage` with your
   Claude Code OAuth token (the same call `/usage` makes). The token is read
   from the macOS Keychain item `Claude Code-credentials`, which Claude Code
   keeps refreshed.
2. **Token/cost** — parses `~/.claude/projects/**/*.jsonl` transcripts,
   aggregating per-model token usage for the current weekly window and pricing
   it via `PriceTable` (public list prices, easy to edit).

Polls every 60s by default (configurable: 15s / 30s / 60s / 5m). The cost engine
caches parsed files by modification date, so steady-state polling stays cheap
even with a large transcript history.

The dollar figures are notional "value extracted" — on a flat-fee subscription
they're what the same tokens would cost on pay-as-you-go API pricing, not real
spend.

### Keychain access

The app reads the credential by invoking `/usr/bin/security`, which accesses the
Keychain item without a blocking permission dialog. (A freshly ad-hoc-signed app
is not in the item's trust list, so a direct Security-framework read would prompt
on every poll.)

## Build from source

Requires the Swift toolchain — Xcode Command Line Tools is enough
(`xcode-select --install`), no full Xcode needed:

```sh
git clone https://github.com/icedumpy/claude-code-usage-bar.git
cd claude-code-usage-bar
./scripts/install.sh        # builds the universal .app, installs to /Applications, launches
```

A locally built app has no quarantine flag, so no Gatekeeper dance is needed.

Other commands:

```sh
swift test                              # run the unit tests (Swift Testing)
.build/release/ClaudeUsageBar --probe   # print what the menu bar would show
```

## Architecture

- `Sources/UsageCore/` — UI-free, unit-tested data layer: `UsageClient` (API),
  `CostEngine` (actor; JSONL parsing + caching), `Credentials` (token parsing),
  `PriceTable`, `ThresholdAlerter`, `UsageSnapshot`, `Formatting`,
  `PinnedPanelGeometry` (pure clamp + on/off-screen logic for the pinned panel),
  and `Updating` (pure decision logic for the in-app updater — version compare,
  download verification, crash recovery, swap paths).
- `Sources/ClaudeUsageBar/` — SwiftUI app: `UsageStore` (`@MainActor`
  `ObservableObject` polling + backoff), `DropdownView` (with the bars/race
  visualization), `SettingsView`, `PinnedPanelController` / `PinnedPanelView`
  (the floating PiP panel), `NotificationManager`, `ShellCredentialProvider`,
  `Updater` (download + verify + detached swap helper), and `Probe`
  (`--probe` CLI).

## In-app updater

The **Update & Relaunch** banner turns `install-release.sh` into an in-app flow:
download the latest release zip, verify it, swap the running bundle in place, and
relaunch — same trust model as the one-line installer (ad-hoc signed,
unnotarized, no Sparkle).

Safety (the swap is done by a detached bash helper):

- **Same-volume atomic swap** — the download is staged, backed up, and swapped
  as siblings of the target so every move is a rename, never a cross-volume copy.
- **Always-restore** — the old bundle is parked at a backup path and only deleted
  once the new one is in place; the helper restores it on any failure, so the
  user is never left without an app.
- **Interprocess lock** guards the swap; the button is disabled while it runs.
- **Crash recovery** — `Updater.reconcileAtLaunch()` restores an interrupted
  swap, clears a stale backup/lock/staging dir, and surfaces the helper's last
  status (written to a file, since the app is dead during the swap).
- **Verification before swap** — top-level `.app` only, bundle-id match, not a
  version downgrade, executable present, `codesign --verify` passes.
- **Fallback** — if the install location isn't writable (needs admin), the banner
  opens the release page instead. This is a normal outcome, not an error.

Brick-risk decisions are pure and unit-tested in `UsageCore/Updating.swift`; the
side effects live in `Sources/ClaudeUsageBar/Updater.swift`.

Settings and custom icons live in `~/Library/Application Support/ClaudeUsageBar/`
and are not touched by an update.

## Custom icons

The menu bar icon is loaded from three SVG files (one per severity); drop in your
own art and it is picked up automatically (no rebuild):

```
~/Library/Application Support/ClaudeUsageBar/icons/
   normal.svg     # low usage   (green by default)
   warning.svg    # mid usage   (amber by default)
   critical.svg   # high usage  (red by default)
```

The app renders whatever SVG is in that folder. It is a normal user-writable
directory, so only put art you trust there (SVG contents are not sanitized
before rendering).

## Distributing

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which builds the
universal app and publishes `ClaudeUsageBar.zip` on GitHub Releases — that zip
is what the one-line installer and the in-app update banner point at. The app
is ad-hoc signed; removing the Gatekeeper warning entirely would require an
Apple Developer account ($99/yr) to Developer-ID-sign and notarize (roadmap).
The default icons are plain colored circles (original artwork, no third-party
marks), so the repo is safe to share as-is.

## Notes

- The `/api/oauth/usage` endpoint is undocumented, so an Anthropic change could
  break the rate-limit display. The token/cost breakdown reads local files and
  is unaffected.
- If your token expires while Claude Code is closed, the bar shows a warning
  state until you next use Claude Code (the app does not refresh the token
  itself).
- Update `PriceTable` when Anthropic's public prices change.
