#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/CLW.app"
DEST_APP="$HOME/Applications/CLW.app"
WORKER_APP="$HOME/Applications/CLWWorker.app"
DATA="$HOME/Library/Application Support/CodexLimitWatch"
AGENT="$HOME/Library/LaunchAgents/dev.local.codex-limit-watch.plist"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers" "$DATA" "$HOME/Library/LaunchAgents"
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Apple Command Line Tools are required: xcode-select --install'
  read -r -p 'Press Enter to close...'
  exit 1
fi
echo 'Building CLW for macOS...'
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.clw.notifications</string>
<key>CFBundleName</key><string>CLW</string>
<key>CFBundleDisplayName</key><string>CLW</string>
<key>CFBundleExecutable</key><string>CodexLimitWatch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.9</string>
<key>CFBundleVersion</key><string>290</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# iconutil builds a proper icon from PNG sources
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size*2))
  sips -s format png -z "$double" "$double" assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp assets/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
xcrun swiftc -O source/main.swift source/ui.swift -o "$APP/Contents/MacOS/CodexLimitWatch" -framework AppKit -framework UserNotifications -framework Security
 # A bare command-line helper, not a second .app. Never shows up in the Dock.
cp "$APP/Contents/MacOS/CodexLimitWatch" "$APP/Contents/Helpers/CLWWorker"
chmod 755 "$APP/Contents/Helpers/CLWWorker"
codesign --force --sign - "$APP/Contents/Helpers/CLWWorker" >/dev/null
codesign --force --deep --sign - "$APP" >/dev/null
# User-only installation: never request an administrator password.
echo 'Installing CLW in ~/Applications (no administrator password required)...'
# Stop legacy CLW GUI and worker processes before updating binaries.
/usr/bin/killall CLWWorker >/dev/null 2>&1 || true
# Remove legacy system-wide installation only if user can do so without admin privileges.
if [ -d "/Applications/CLW.app" ]; then
  echo "Note: An older /Applications/CLW.app also exists. Remove it manually if Dock shows duplicates."
fi
mkdir -p "$HOME/Applications"
chmod 700 "$DATA" || true
/usr/bin/ditto "$APP" "$DEST_APP"
# Remove old worker bundles that could appear as two extra Dock icons.
rm -rf "$WORKER_APP"
# Existing launch agent is disabled before updating the application.
APP="$DEST_APP"
[ -f "$DATA/language.txt" ] || printf 'en\n' > "$DATA/language.txt"
[ -f "$DATA/mode.txt" ] || printf 'test\n' > "$DATA/mode.txt"
[ -f "$DATA/interval-minutes.txt" ] || printf '7\n' > "$DATA/interval-minutes.txt"
[ -f "$DATA/channel.txt" ] || printf 'macos\n' > "$DATA/channel.txt"
# Old agents are removed; the GUI starts and stops the worker.
uid="$(id -u)"
launchctl bootout "gui/$uid" "$AGENT" >/dev/null 2>&1 || true
rm -f "$AGENT" "$AGENT.disabled"
rm -f "$DATA/monitoring-enabled" "$DATA/agent-interval.txt"
# Register desktop application for notification permission UI.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
# Remove the previous application only after successful new build.
if [ -d "$HOME/Applications/Codex Limit Watch.app" ]; then
  rm -rf "$HOME/Applications/Codex Limit Watch.app"
fi
open "$APP"
echo ''
echo 'Installed! Launch CLW.app from ~/Applications or Spotlight thereafter.'
echo 'Enable notifications in System Settings → Notifications → CLW.'
read -r -p 'Press Enter to close...'
