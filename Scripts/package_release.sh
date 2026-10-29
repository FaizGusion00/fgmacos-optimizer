#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?usage: package_release.sh 1.0.5}"
APP="${2:-$ROOT/.derivedData/Build/Products/Release/FGMacOS Optimizer.app}"

test -d "$APP"
rm -rf "$ROOT/dist/dmg-root"
mkdir -p "$ROOT/dist/dmg-root"
cp -R "$APP" "$ROOT/dist/dmg-root/FGMacOS Optimizer.app"
cp "$ROOT/Scripts/Install.command" "$ROOT/dist/dmg-root/Install.command"
chmod +x "$ROOT/dist/dmg-root/Install.command"
xattr -cr "$ROOT/dist/dmg-root/FGMacOS Optimizer.app" || true
xattr -cr "$ROOT/dist/dmg-root/Install.command" || true
ln -sf /Applications "$ROOT/dist/dmg-root/Applications"

OUT_DMG="$ROOT/dist/FGMacOS-Optimizer-v${VERSION}.dmg"
OUT_ZIP="$ROOT/dist/FGMacOS-Optimizer-v${VERSION}-macos.zip"
rm -f "$OUT_DMG" "$OUT_ZIP"

hdiutil create -volname "FGMacOS Optimizer" -srcfolder "$ROOT/dist/dmg-root" -ov -format UDZO "$OUT_DMG" >/dev/null
ditto -c -k --keepParent "$ROOT/dist/dmg-root/FGMacOS Optimizer.app" "$OUT_ZIP"

echo "DMG $OUT_DMG"
echo "ZIP $OUT_ZIP"
lipo -archs "$ROOT/dist/dmg-root/FGMacOS Optimizer.app/Contents/MacOS/FGMacOS Optimizer"
