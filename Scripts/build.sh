#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Prefer full Xcode when Command Line Tools are the active developer dir.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi


if [[ ! -d FGMacOSOptimizer.xcodeproj ]]; then
  xcodegen generate
fi

CONFIG="${1:-Debug}"
DEST="platform=macOS,arch=$(uname -m)"

xcodebuild \
  -project FGMacOSOptimizer.xcodeproj \
  -scheme FGMacOSOptimizer \
  -configuration "$CONFIG" \
  -destination "$DEST" \
  -derivedDataPath "$ROOT/.derivedData" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build

echo "Build OK ($CONFIG). App at:"
find "$ROOT/.derivedData/Build/Products" -name "FGMacOS Optimizer.app" -maxdepth 3 2>/dev/null | head -5
