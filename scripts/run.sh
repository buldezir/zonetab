#!/bin/bash
# Build ZoneTab, install it to /Applications and (re)launch it.
#   scripts/run.sh            Debug build (includes zonetab:// diagnostics)
#   scripts/run.sh Release
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
BUNDLE_ID="dev.sasha.zonetab"
DERIVED="build/DerivedData"
INSTALLED="/Applications/ZoneTab.app"

xcodegen generate --quiet
xcodebuild -project ZoneTab.xcodeproj -scheme ZoneTab -configuration "$CONFIG" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" build -quiet

# Quit gracefully so the native ⌘⇥ switcher is restored before the new build takes over.
if osascript -e "application id \"$BUNDLE_ID\" is running" | grep -q true; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null || true
  for _ in $(seq 1 50); do
    osascript -e "application id \"$BUNDLE_ID\" is running" | grep -q true || break
    sleep 0.1
  done
fi

rm -rf "$INSTALLED"
ditto "$DERIVED/Build/Products/$CONFIG/ZoneTab.app" "$INSTALLED"
open "$INSTALLED"
echo "ZoneTab ($CONFIG) installed to $INSTALLED and launched."
