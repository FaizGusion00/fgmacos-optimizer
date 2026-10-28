#!/bin/zsh
# Notarization helper for outside-MAS distribution.
# Requires: Apple Developer ID Application cert, app-specific password in keychain.
# Usage:
#   ./Scripts/notarize.sh /path/to/FGMacOS\ Optimizer.app
# Env:
#   APPLE_ID, TEAM_ID, APP_PASSWORD (or NOTARYTOOL keychain profile)

set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Usage: $0 /path/to/FGMacOS Optimizer.app"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="$ROOT/.notarize-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"

APP_NAME="$(basename "$APP_PATH")"
ZIP="$STAGING/${APP_NAME%.app}.zip"

echo "→ Ditto zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "→ Submit with keychain profile $NOTARY_PROFILE"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "${APPLE_ID:-}" && -n "${TEAM_ID:-}" && -n "${APP_PASSWORD:-}" ]]; then
  echo "→ Submit with Apple ID"
  xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait
else
  echo "Set NOTARY_PROFILE or APPLE_ID + TEAM_ID + APP_PASSWORD"
  exit 1
fi

echo "→ Staple"
xcrun stapler staple "$APP_PATH"
echo "Notarization complete: $APP_PATH"
