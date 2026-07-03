#!/bin/bash
# Build the universal app and install it to /Applications, then launch it.
# Also the update path: `git pull && ./scripts/install.sh`.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="ClaudeUsageBar"

./scripts/build_app.sh

echo "==> quitting any running instance"
# killall, not osascript: an Apple Events quit needs an automation-permission
# grant and can silently fail, leaving the old instance running after "update".
if killall "$APP_NAME" 2>/dev/null; then sleep 1; fi

echo "==> installing to /Applications"
# ditto overwrites in place; your icons/settings live in
# ~/Library/Application Support/ClaudeUsageBar and are NOT touched by updates.
ditto "dist/$APP_NAME.app" "/Applications/$APP_NAME.app"

echo "==> launching"
open "/Applications/$APP_NAME.app"
echo "Done. Look for the Claude badge in your menu bar."
