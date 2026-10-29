#!/bin/bash
# Double-click this from the DMG. Copies app to Applications and clears Gatekeeper quarantine.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$SRC_DIR/FGMacOS Optimizer.app"
DEST="/Applications/FGMacOS Optimizer.app"

if [[ ! -d "$APP_SRC" ]]; then
  osascript -e 'display dialog "FGMacOS Optimizer.app not found next to Install.command." buttons {"OK"} default button 1 with icon stop'
  exit 1
fi

echo "Installing FGMacOS Optimizer to /Applications ..."
rm -rf "$DEST"
cp -R "$APP_SRC" "$DEST"

# Remove download quarantine so Ventura/Sonoma Gatekeeper "Done"-only dialog goes away.
xattr -cr "$DEST" || true
xattr -d com.apple.quarantine "$DEST" 2>/dev/null || true

echo "Launching..."
open "$DEST"

osascript -e 'display dialog "Installed.\n\nLook at the menu bar (top-right) for the gauge / bolt icon.\n\nIf macOS still blocks: System Settings → Privacy & Security → Open Anyway." buttons {"OK"} default button 1 with title "FGMacOS Optimizer"'

exit 0
