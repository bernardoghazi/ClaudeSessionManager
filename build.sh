#!/bin/zsh
# Builds ClaudeSessionManager.app in this folder.
# Launch it with `open ClaudeSessionManager.app`: notification clicks only reach an app started by LaunchServices.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="ClaudeSessionManager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeSessionManager "$APP/Contents/MacOS/"
cp -R plugin "$APP/Contents/Resources/plugin"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Claude Session Manager</string>
  <key>CFBundleDisplayName</key><string>Claude Session Manager</string>
  <key>CFBundleIdentifier</key><string>local.claude-session-manager</string>
  <key>CFBundleExecutable</key><string>ClaudeSessionManager</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSUserNotificationAlertStyle</key><string>alert</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
