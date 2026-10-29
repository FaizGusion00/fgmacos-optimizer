#!/bin/zsh
# Sign with Developer ID + notarize for stable TCC (Accessibility / FDA).
# Ad-hoc builds (CODE_SIGN_IDENTITY="-") change cdhash every rebuild → ghost ON in Settings.
#
# Prerequisites:
#   1. Apple Developer Program membership
#   2. "Developer ID Application" certificate in login keychain
#   3. notarytool credentials once:
#        xcrun notarytool store-credentials "fgmacos-notary" \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#
# Usage:
#   ./Scripts/sign_and_notarize.sh
#   DEVELOPMENT_TEAM=XXXXXXXX ./Scripts/sign_and_notarize.sh
#   NOTARY_PROFILE=fgmacos-notary ./Scripts/sign_and_notarize.sh /path/to/app

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

TEAM="${DEVELOPMENT_TEAM:-${FG_DEVELOPMENT_TEAM:-}}"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-fgmacos-notary}"

if [[ -z "$TEAM" ]]; then
  echo "Set DEVELOPMENT_TEAM (10-char Team ID) before signing."
  echo "  export DEVELOPMENT_TEAM=XXXXXXXXXX"
  echo "Find it: https://developer.apple.com/account → Membership"
  exit 1
fi

# List matching identities
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "No 'Developer ID Application' identity in keychain."
  echo "Create one in Xcode → Settings → Accounts → Manage Certificates."
  exit 1
fi

echo "→ xcodegen"
xcodegen generate >/dev/null

echo "→ Build Release (Developer ID, team=$TEAM)"
xcodebuild \
  -project FGMacOSOptimizer.xcodeproj \
  -scheme FGMacOSOptimizer \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$ROOT/.derivedData" \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build

APP="$(find "$ROOT/.derivedData/Build/Products/Release" -name 'FGMacOS Optimizer.app' -maxdepth 2 | head -1)"
test -d "$APP"

echo "→ Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP" || true

echo "→ Notarize"
NOTARY_PROFILE="$NOTARY_PROFILE" "$ROOT/Scripts/notarize.sh" "$APP"

echo "→ Package"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
"$ROOT/Scripts/package_release.sh" "$VERSION" "$APP"

echo "Signed + notarized. Install from dist/ and enable Accessibility once — it should stick across updates with the same Team ID."
