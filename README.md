# Claude Usage Bar

A native macOS menu bar app that shows your Claude Code usage at a glance — the
rate-limit headroom that `/usage` reports, plus a per-model token/cost breakdown.

```
🟢 19%                         ← menu bar: highest usage-vs-limit %, colored by severity

Claude Usage            [Max]
─────────────────────────────
5-hour window     19%   resets in 2h 59m   (now)
Weekly (all)      15%   resets in 4d 2h
Weekly · Sonnet   17%   resets in 4d 2h
─────────────────────────────
This week — by model
  Opus 4.8     138.5M tok   $405
  Sonnet 4.6     1.1M tok   $1.26
  Haiku 4.5      1.1M tok   $0.60
  Total        140.7M tok   $407
─────────────────────────────
[30s ▾]            updated 12:00
☐ Launch at login   Refresh  Quit
```

## What it shows

- **Hero number** (menu bar): the highest current-usage-vs-limit percentage
  across your active limits (5-hour, weekly-all, weekly-per-model), colored by
  the API's severity (🟢 normal / 🟡 warning / 🔴 critical). When Opus is your
  binding limit, that's the number you see.
- **Dropdown**: each rate-limit window with its reset countdown, then per-model
  token totals for the current weekly window with a notional API-equivalent
  dollar figure. (You're on a flat-fee plan, so the dollars are "value
  extracted", not real spend.)

## How it works

Two data sources, both confirmed working:

1. **Rate limits** — `GET https://api.anthropic.com/api/oauth/usage` with your
   Claude Code OAuth token (the same call `/usage` makes). The token is read
   from the macOS Keychain item `Claude Code-credentials`, which Claude Code
   keeps refreshed.
2. **Token/cost** — parses `~/.claude/projects/**/*.jsonl` transcripts,
   aggregating per-model token usage for the current weekly window and pricing
   it via `PriceTable` (public list prices, easy to edit).

Polls every 30s (configurable: 15s/30s/60s/5m). The cost engine caches parsed
files by modification date, so steady-state polling is cheap even with a large
transcript history.

### Keychain access

The app reads the credential by invoking `/usr/bin/security`, which accesses the
Keychain item without a blocking permission dialog. (A freshly ad-hoc-signed app
is not in the item's trust list, so the direct Security-framework read would
prompt on every poll.)

## Architecture

- `Sources/UsageCore/` — UI-free, fully unit-tested data layer:
  `UsageClient` (API), `CostEngine` (actor; JSONL parsing + caching),
  `CredentialProvider` (Keychain), `PriceTable`, `UsageSnapshot` (view-model
  builder), `Formatting`.
- `Sources/ClaudeUsageBar/` — SwiftUI app: `UsageStore` (`@MainActor`
  `ObservableObject`, polling), `DropdownView`, `AppDelegate` (starts polling at
  launch), `ShellCredentialProvider`, `Probe` (`--probe` CLI mode).

## Requirements

- macOS 13 or later (Apple Silicon or Intel — the build is universal).
- The Swift toolchain. Xcode Command Line Tools is enough (`xcode-select --install`) — no full Xcode needed.
- **Claude Code installed and logged in.** The app reads your usage from the
  Claude Code OAuth token in your Keychain; without it there's no data.

## Install

```sh
git clone <repo-url> claude-usage-tab
cd claude-usage-tab
./scripts/install.sh        # builds universal .app, installs to /Applications, launches
```

Then open the dropdown and tick **Launch at login** so it starts with your Mac.

First launch may show a Gatekeeper prompt (the app is ad-hoc signed, not
notarized): right-click the app in `/Applications` → **Open** once, or run
`xattr -dr com.apple.quarantine /Applications/ClaudeUsageBar.app`.

## Updating

```sh
git pull
./scripts/install.sh        # rebuilds and replaces the installed app
```

Your custom icons and any settings live in
`~/Library/Application Support/ClaudeUsageBar/` and are **not** touched by an
update, so they survive upgrades.

## Privacy

The app has no embedded secrets and no server of its own. Your OAuth token is
read at runtime from *your* Keychain and sent only to Anthropic's API — exactly
as Claude Code does — never to the author or any third party. The token/cost
breakdown is computed entirely from local files on your machine.

## Custom icons

The menu bar icon is loaded from three SVG files (one per severity); drop in your
own art and it's picked up automatically (no rebuild):

```
~/Library/Application Support/ClaudeUsageBar/icons/
   normal.svg     # green  state
   warning.svg    # yellow state
   critical.svg   # red    state
```

The app renders whatever SVG is in that folder. It's a normal user-writable
directory, so only put art you trust there (the app doesn't sanitize SVG
contents before rendering).

## Other commands

```sh
swift test                          # run the unit tests (Swift Testing)
.build/release/ClaudeUsageBar --probe   # print what the menu bar would show
```

## Distributing to others

This repo is the simplest path — people clone and run `./scripts/install.sh`.
For a double-click, notarized download you'd need an Apple Developer account
($99/yr) to Developer-ID-sign and notarize the `.app`. Note the icon's Claude
mark is Anthropic's trademark — swap in your own art before redistributing.

## Limitations / future ideas (v1 deliberately omits)

- Threshold notifications (e.g. ping at 80%), history charts, per-day breakdown.
- All-time cumulative totals (the breakdown is scoped to the current weekly
  window to match the limit reset).
- If your token expires and Claude Code hasn't refreshed it, the menu bar shows
  `⚠️` until you next use Claude Code (the app doesn't refresh the token itself).
- Update `PriceTable` when Anthropic's public prices change.
