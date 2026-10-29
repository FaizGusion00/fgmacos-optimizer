#!/bin/bash
# Right-click → Open  (jangan expect double-click selalu lulus Gatekeeper)
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$SRC_DIR/FGMacOS Optimizer.app"
DEST="/Applications/FGMacOS Optimizer.app"

clear 2>/dev/null || true
echo "============================================"
echo " FGMacOS Optimizer — Install"
echo "============================================"
echo

if [[ ! -d "$APP_SRC" ]]; then
  echo "ERROR: FGMacOS Optimizer.app not found."
  read -r -p "Press Enter to close..."
  exit 1
fi

echo "Copying to /Applications ..."
rm -rf "$DEST"
cp -R "$APP_SRC" "$DEST"

echo "Clearing Gatekeeper quarantine ..."
xattr -cr "$DEST" 2>/dev/null || true
xattr -d com.apple.quarantine "$DEST" 2>/dev/null || true
find "$DEST" -exec xattr -c {} \; 2>/dev/null || true

echo "Launching ..."
open "$DEST"

echo
echo "DONE. Look at the MENU BAR (top-right), not the Dock."
echo "If still blocked: System Settings → Privacy & Security → Open Anyway"
echo
read -r -p "Press Enter to close..."
exit 0
