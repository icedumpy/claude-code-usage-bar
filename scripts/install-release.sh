#!/bin/bash
# Install the latest prebuilt release. No git, no Swift toolchain — just macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/icedumpy/claude-code-usage-bar/main/scripts/install-release.sh | bash
#
set -euo pipefail

REPO="icedumpy/claude-code-usage-bar"
APP_NAME="ClaudeUsageBar"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> downloading latest release"
curl -fsSL "https://github.com/$REPO/releases/latest/download/$APP_NAME.zip" \
    -o "$TMP/$APP_NAME.zip"

echo "==> unpacking"
ditto -x -k "$TMP/$APP_NAME.zip" "$TMP"

echo "==> quitting any running instance"
if killall "$APP_NAME" 2>/dev/null; then sleep 1; fi

echo "==> installing to /Applications"
# Your icons/settings live in ~/Library/Application Support/ClaudeUsageBar
# and are NOT touched by updates.
ditto "$TMP/$APP_NAME.app" "/Applications/$APP_NAME.app"

echo "==> removing the quarantine flag (the app is ad-hoc signed, not notarized)"
xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true

echo "==> launching"
open "/Applications/$APP_NAME.app"
echo "Done. Look for the Claude badge in your menu bar."
