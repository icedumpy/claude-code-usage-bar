#!/bin/bash
# Build ClaudeUsageBar as a UNIVERSAL (Apple Silicon + Intel) menu-bar .app
# bundle. No Xcode required — builds each arch with SwiftPM and lipo's them.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="ClaudeUsageBar"
BUNDLE_ID="com.pongporamat.claudeusagebar"
VERSION="${VERSION:-1.0.0}"   # release workflow overrides this from the git tag
APP="$ROOT/dist/${APP_NAME}.app"

echo "==> building arm64"
swift build -c release --arch arm64
echo "==> building x86_64"
swift build -c release --arch x86_64

ARM="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
X86="$(swift build -c release --arch x86_64 --show-bin-path)/$APP_NAME"

echo "==> assembling universal bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/$APP_NAME"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>Claude Usage</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP"

echo "==> done: $APP"
