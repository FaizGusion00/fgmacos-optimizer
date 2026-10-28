# FGMacOS Optimizer

Premium macOS menu-bar optimizer — low footprint, Mach-backed metrics, Turbo Mode, Smart Watchdog, and deep cleaner.

## Requirements

- macOS 14+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Generate & build

```bash
xcodegen generate
./Scripts/build.sh Debug
# or open FGMacOSOptimizer.xcodeproj
```

## Features

- **Status gauges** — RAM / CPU / thermal (smoothed 60fps display from 4–5s samples)
- **Turbo Mode** — pause Spotlight indexing, stop Time Machine backup, clear Xcode Derived Data
- **Watchdog** — CPU hog + not-responding detection with whitelist (Cursor, Terminal, Docker, …)
- **Deep Cleaner** — selective `~/Library/Caches`, DNS flush, Docker dangling volume prune
- **Vibrancy popover** — SwiftUI + `NSVisualEffectView`, Dark/Light automatic

## Architecture notes

- App Sandbox **off** (outside Mac App Store) for kill / cache / Docker
- `LSUIElement` menu-bar only, target idle RSS &lt; 20 MB
- Sampling on utility QoS; UI on MainActor via `MetricSmoother`

## Docs

- [48h soak test](Docs/SOAK_TEST.md)
- [Notarize](Scripts/notarize.sh)

## Permissions

Grant Full Disk Access, Notifications, and optionally Accessibility via **Permissions** in the popover footer (or Settings scene).
