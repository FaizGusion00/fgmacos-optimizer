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

# Release ships as universal (Intel + Apple Silicon). Debug can stay native-only for speed.
EXTRA_ARCH_FLAGS=()
if [[ "$CONFIG" == "Release" ]]; then
  EXTRA_ARCH_FLAGS=(
    ARCHS="arm64 x86_64"
    ONLY_ACTIVE_ARCH=NO
    EXCLUDED_ARCHS=
  )
  DEST="generic/platform=macOS"
else
  DEST="platform=macOS,arch=$(uname -m)"
fi

xcodebuild \
  -project FGMacOSOptimizer.xcodeproj \
  -scheme FGMacOSOptimizer \
  -configuration "$CONFIG" \
  -destination "$DEST" \
  -derivedDataPath "$ROOT/.derivedData" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  "${EXTRA_ARCH_FLAGS[@]}" \
  build

APP="$(find "$ROOT/.derivedData/Build/Products/$CONFIG" -name 'FGMacOS Optimizer.app' -maxdepth 2 | head -1)"
BIN="$APP/Contents/MacOS/FGMacOS Optimizer"
echo "Build OK ($CONFIG). App at: $APP"
if [[ -f "$BIN" ]]; then
  echo "Architectures: $(lipo -archs "$BIN" 2>/dev/null || lipo -info "$BIN")"
  echo "Min OS: $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
fi
