# Claude Usage Menu Bar App — Design Spec

Date: 2026-06-17
Status: Approved (design); pending implementation plan

## Problem

There is no at-a-glance way to see Claude Code usage. Today the only options are
running `/usage` inside a session or opening the Claude website. As a Max
subscriber, the number that matters is **how much of the rate-limit window is
left** ("am I about to get throttled?"), and there is no ambient display of it.

## Goal

A native macOS menu bar app that shows, in real time and at a glance:

1. **Rate-limit headroom** (hero number) — how much of the 5-hour and weekly
   limits have been consumed, including the per-model weekly limit. This mirrors
   what `/usage` shows.
2. **Token + cost breakdown** (dropdown) — tokens per model for the current
   weekly window, with an API-equivalent dollar figure (notional "value
   extracted", since the plan is flat-fee).

Non-goals for v1: threshold notifications, history charts, per-day breakdowns,
cumulative all-time stats. The architecture must leave room for these without a
rewrite.

## Platform & Stack

- **Native Swift**, SwiftUI `MenuBarExtra` (macOS 13+).
- Rationale: most modern and longest-lasting (first-party Apple, actively
  developed), best glanceability (custom rendering/color), highest feature
  ceiling, ships as a real `.app`. Developer skill is not a constraint because
  the build is fully agent-driven.
- App runs as a menu-bar-only agent (`LSUIElement` / `.menuBarExtraStyle`), no
  Dock icon, launch-at-login optional.

## Data Sources (both confirmed via spike)

### A. Rate-limit headroom — live API

- Endpoint: `GET https://api.anthropic.com/api/oauth/usage`
- Headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`,
  `anthropic-version: 2023-06-01`.
- Auth token: read from macOS Keychain, generic-password service
  `Claude Code-credentials`. JSON shape:
  `{ "claudeAiOauth": { accessToken, refreshToken, expiresAt, scopes,
  subscriptionType, rateLimitTier } }`.
- Confirmed response shape (HTTP 200):
  ```json
  {
    "five_hour": { "utilization": 5.0, "resets_at": "2026-06-17T07:40Z" },
    "seven_day": { "utilization": 14.0, "resets_at": "2026-06-21T08:00Z" },
    "seven_day_opus": null,
    "seven_day_sonnet": { "utilization": 17.0, "resets_at": "..." },
    "extra_usage": { "is_enabled": false, ... },
    "limits": [
      { "kind": "session",       "group": "session", "percent": 5,  "severity": "normal", "resets_at": "...", "scope": null, "is_active": false },
      { "kind": "weekly_all",    "group": "weekly",  "percent": 14, "severity": "normal", "resets_at": "...", "scope": null, "is_active": false },
      { "kind": "weekly_scoped", "group": "weekly",  "percent": 17, "severity": "normal", "resets_at": "...", "scope": { "model": { "display_name": "Sonnet" } }, "is_active": true }
    ],
    "spend": { "used": { "amount_minor": 0, "currency": "USD" }, "percent": 0, "enabled": false }
  }
  ```
- The `limits` array is the primary source for the menu bar: each entry has
  `percent`, `severity`, `resets_at`, `scope.model.display_name`, `is_active`.

### B. Token + cost breakdown — local files

- Source: `~/.claude/projects/**/*.jsonl` transcripts.
- Each assistant message line carries `message.usage` with `input_tokens`,
  `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, and
  `message.model` (e.g. `claude-opus-4-8`). Synthetic lines (`"model":
  "<synthetic>"`) are skipped.
- Aggregate tokens per model, scoped to the **current weekly window** (start =
  `seven_day.resets_at` minus 7 days). Compute an API-equivalent dollar figure
  via a maintained model→price table (per-MTok input/output/cache-write/
  cache-read rates).

## Architecture

Data layer is pure Swift with no UI dependency, independently testable. UI is a
thin SwiftUI layer over a single published view-model.

### Data layer

1. **`CredentialProvider`**
   - Reads + parses the Keychain credential; exposes `accessToken` and
     `expiresAt`.
   - On a 401 from `UsageClient`, refreshes via `POST /v1/oauth/token` with the
     stored `refreshToken`, writes the new token back to Keychain, retries once.
   - If refresh fails (logged out), surfaces a `.signedOut` state.
   - Depends on: macOS Keychain, network (refresh only).

2. **`UsageClient`**
   - `func fetchUsage() async throws -> Usage` — calls `GET /api/oauth/usage`
     with bearer + beta headers, decodes into typed structs (`FiveHour`,
     `SevenDay`, `Limit`, `Spend`).
   - Depends on: `CredentialProvider`, `URLSession`.

3. **`CostEngine`**
   - `func breakdown(since: Date) -> [ModelUsage]` — scans the JSONL transcripts,
     parses per-message usage + model, aggregates tokens per model, applies the
     price table for the API-equivalent dollar figure.
   - Incremental: remembers file offsets/byte positions so each poll only reads
     newly appended lines (the transcripts are append-only).
   - Depends on: filesystem (`~/.claude/projects`), `PriceTable`.

4. **`PriceTable`**
   - Static model→price map (input/output/cache rates per MTok) used only for the
     notional dollar figure. Easy to update as pricing changes.

5. **`UsageStore`** (`ObservableObject`)
   - Polls `UsageClient` + refreshes `CostEngine` on a timer (default 30s).
   - Merges both into one `UsageViewModel` (hero %, color/severity, the three
     limit rows with reset countdowns, the per-model breakdown rows).
   - Holds app state: `.loading`, `.ok`, `.signedOut`, `.error`.

### UI layer (SwiftUI `MenuBarExtra`)

6. **Menu bar label**
   - Shows max utilization across the active limits, colored by the worst
     `severity` among them: `normal`→green, `warning`→yellow, otherwise red.
   - Format: `🟢 17%` (icon/dot + percent). `⚠️` when signed out / error.

7. **Dropdown content** (layout from approved design):
   - Three rate-limit rows (5h / weekly-all / weekly-per-model) with percent and
     a humanized reset countdown; the active limit is marked.
   - "This week — by model": per-model token totals + API-equivalent dollars, and
     a total row.
   - Actions: Refresh now · Settings · Quit.

8. **Settings (v1, minimal)**: refresh interval (default 30s) and launch-at-login.

## Data Flow

```
Timer (30s)
  └─ UsageStore.refresh()
       ├─ UsageClient.fetchUsage() ── CredentialProvider (Keychain → token, refresh on 401)
       │     └─ GET /api/oauth/usage → Usage (limits, windows)
       └─ CostEngine.breakdown(since: weekStart)
             └─ tail ~/.claude/projects/**/*.jsonl → [ModelUsage]
       → merge → UsageViewModel → SwiftUI MenuBarExtra re-renders
```

## Error Handling

- **Token expired** → refresh via refresh token, retry once; success transparent.
- **Refresh fails / logged out** → `.signedOut`, menu bar shows `⚠️ sign in`,
  dropdown explains to open Claude Code to re-auth.
- **Network offline / API 5xx** → keep last good values, show a subtle stale
  indicator; retry next poll.
- **No transcripts yet** → breakdown shows "no usage this week"; rate-limit hero
  still works.
- **Malformed JSONL line** → skip that line, continue (transcripts can contain
  partial writes).

## Testing

- `CredentialProvider`: parse fixture JSON; 401→refresh→retry path with a mocked
  client; logged-out path.
- `UsageClient`: decode the confirmed response fixture into typed structs;
  pick the correct hero limit and severity.
- `CostEngine`: aggregate tokens from fixture JSONL; correct weekly-window
  scoping; skip synthetic/malformed lines; incremental offset reads.
- `PriceTable`: dollar math for a known token mix.
- `UsageStore`: merge logic and state transitions (ok/signedOut/error) with
  mocked dependencies.
- UI: not automated (menu bar GUI) — manual glance check during verification.

## Deployment

- Build the `.app` with the Xcode toolchain; ad-hoc code-sign for personal use.
- Install to `/Applications`; optional launch-at-login via `SMAppService`.
- Gatekeeper first-run approval is expected and documented.

## Build Approach (orchestrated)

After the implementation plan, build via agent orchestration (Workflow tool):

- **Plan** — one planner agent expands this spec into a task plan.
- **Build (parallel)** — `CredentialProvider`, `UsageClient`, `CostEngine` are
  independent and built concurrently with TDD; then `UsageStore` + UI (depend on
  the above) sequentially.
- **QA (adversarial, per module)** — `swift-reviewer` (idioms/memory/
  concurrency) + `code-reviewer` (correctness) + a verification pass that builds
  and runs the tests green.
- **Deploy** — build, sign, install, launch-at-login.

## Open Questions

None blocking. Pricing table values to be filled from current public API pricing
at implementation time.
