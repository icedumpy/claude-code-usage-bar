#!/bin/bash
# Claude Code Notification-hook script: relays a session event to the
# ClaudeUsageBar menu bar app, which fires a native notification naming the
# repo and the session's topic. Clicking it activates the terminal app that
# hosted the session — unlike `osascript -e 'display notification'` fired
# directly, whose notifications are attributed to Script Editor, so clicking
# them just brings Script Editor forward instead of your actual terminal.
#
# Falls back to a plain (Script-Editor-attributed) osascript notification if
# ClaudeUsageBar isn't installed to handle the claudeusagebar:// URL scheme,
# so this script is still useful on its own.
#
# Install: add to the "Notification" hook in ~/.claude/settings.json —
#   "hooks": {
#     "Notification": [
#       { "matcher": "", "hooks": [
#         { "type": "command", "command": "/path/to/claude-code-usage-bar/scripts/session-notify.sh" }
#       ]}
#     ]
#   }
#
# Claude Code passes the notification payload as JSON on stdin:
#   { "session_id", "transcript_path", "cwd", "message", "hook_event_name" }
set -euo pipefail

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // empty')
message=$(echo "$input" | jq -r '.message // "Claude Code needs your attention"')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Repo/folder name: prefer the git repo's top-level directory name, falling
# back to the plain folder name outside a repo.
repo="Claude Code"
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  if root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
    repo=$(basename "$root")
  else
    repo=$(basename "$cwd")
  fi
fi

# Topic: Claude Code's own auto-generated session title, the same text shown
# in the `/resume` picker. It's written as the most recent `ai-title` line in
# the transcript, so read that back rather than re-deriving anything.
topic=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  topic=$(grep -a '"type":"ai-title"' "$transcript_path" 2>/dev/null \
    | tail -1 \
    | jq -r '.aiTitle // empty' 2>/dev/null || true)
fi
[ -z "$topic" ] && topic="$message"

# Which GUI app is hosting this session (Terminal, iTerm2, VS Code, Cursor,
# Warp, ...)? Walk up the process tree from this script's parent until an app
# bundle shows up, then read its bundle ID off disk. Generic across
# terminals — no hardcoded app list to keep up to date.
bundle_id=""
pid=$PPID
for _ in $(seq 1 12); do
  [ -z "$pid" ] && break
  exe=$(ps -o comm= -p "$pid" 2>/dev/null || true)
  [ -z "$exe" ] && break
  case "$exe" in
    *.app/Contents/MacOS/*)
      app_path=$(printf '%s' "$exe" | sed -E 's#(.*\.app)/Contents/MacOS/.*#\1#')
      bundle_id=$(mdls -name kMDItemCFBundleIdentifier -raw "$app_path" 2>/dev/null || true)
      [ "$bundle_id" = "(null)" ] && bundle_id=""
      break
      ;;
  esac
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  [ -z "$ppid" ] || [ "$ppid" = "1" ] && break
  pid=$ppid
done

urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

link="claudeusagebar://session-notify?repo=$(urlencode "$repo")&topic=$(urlencode "$topic")&message=$(urlencode "$message")"
[ -n "$bundle_id" ] && link="${link}&bundleId=$(urlencode "$bundle_id")"

if ! open -g "$link" 2>/dev/null; then
  # ClaudeUsageBar isn't installed to handle the URL scheme — fall back to a
  # plain notification (clicking it activates Script Editor, not your
  # terminal, but at least you get the heads-up).
  escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  osascript -e "display notification \"$(escape "$message")\" with title \"$(escape "$repo")\" subtitle \"$(escape "$topic")\" sound name \"Ping\""
fi
