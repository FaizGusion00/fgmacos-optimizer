# Developer ID signing & notarization

## Why this matters

Ad-hoc builds (`CODE_SIGN_IDENTITY="-"`) get a **new code directory hash every rebuild**.
macOS Accessibility / Full Disk Access often keep showing **FGMacOS Optimizer = ON** for the *old* binary while the new process still reports Off (“ghost ON”).

**Developer ID Application** + notarization keeps a stable Team ID identity across updates so TCC grants stick.

## One-time setup

1. Join [Apple Developer Program](https://developer.apple.com/programs/).
2. In Xcode → Settings → Accounts → Manage Certificates → **Developer ID Application**.
3. Create an [app-specific password](https://appleid.apple.com) for notarization.
4. Store notary credentials:

```bash
xcrun notarytool store-credentials "fgmacos-notary" \
  --apple-id "you@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

## Ship a signed build

```bash
export DEVELOPMENT_TEAM=YOUR_TEAM_ID
export NOTARY_PROFILE=fgmacos-notary
chmod +x Scripts/sign_and_notarize.sh Scripts/notarize.sh Scripts/package_release.sh
./Scripts/sign_and_notarize.sh
```

Output: notarized app + `dist/FGMacOS-Optimizer-v*.dmg` / zip.

## Daily debug builds

Keep using ad-hoc for speed:

```bash
./Scripts/build.sh Release
```

After each ad-hoc reinstall, if Accessibility looks ON but the app says Off: toggle OFF → ON, then Quit & reopen (or use the in-app Apply button).

## Verify

```bash
codesign -dv --verbose=4 "/Applications/FGMacOS Optimizer.app"
spctl --assess --type execute -v "/Applications/FGMacOS Optimizer.app"
```

Expect `Authority=Developer ID Application: …` and `accepted` from spctl after staple.
