# FGMacOS Optimizer

Premium macOS **menu-bar** optimizer — live metrics, Turbo Mode, Smart Watchdog, and Deep Cleaner.

## Download & install

**Latest release:** [FGMacOS Optimizer v1.0.1](https://github.com/FaizGusion00/fgmacos-optimizer/releases/tag/v1.0.1)

| File | What to do |
|------|------------|
| **[FGMacOS-Optimizer-v1.0.1.dmg](https://github.com/FaizGusion00/fgmacos-optimizer/releases/download/v1.0.1/FGMacOS-Optimizer-v1.0.1.dmg)** | Open DMG → drag **FGMacOS Optimizer** into **Applications** |
| [FGMacOS-Optimizer-v1.0.1-macos.zip](https://github.com/FaizGusion00/fgmacos-optimizer/releases/download/v1.0.1/FGMacOS-Optimizer-v1.0.1-macos.zip) | Unzip → move `.app` into Applications |

First launch: right-click the app → **Open** (ad-hoc signed; Gatekeeper may warn).  
App lives in the **menu bar** (gauge / bolt icon) — no Dock icon.

**Requirements:** macOS 13 Ventura+ (Apple Silicon or Intel)

## Features

- **Status gauges** — RAM / CPU / Disk / Thermal / Battery (Mach-backed, smoothed)
- **Turbo Mode** — pause Spotlight *indexing* (search still works), stop Time Machine backup, clear Xcode Derived Data
- **Free RAM** — purge reclaimable disk cache
- **Watchdog** — CPU hog + not-responding detection with whitelist (Cursor, Terminal, Docker, …)
- **Deep Cleaner** — selective `~/Library/Caches`, DNS flush, Docker dangling volume prune
- **Security session** — Touch ID when available + timed admin unlock
- **Appearance** — Auto / Light / Dark · Open at Login

## Build from source

- macOS 13 Ventura+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
xcodegen generate
./Scripts/build.sh Release
```

## Architecture notes

- App Sandbox **off** (outside Mac App Store) for kill / cache / Docker
- `LSUIElement` menu-bar only
- Sampling on utility QoS; UI on MainActor via `MetricSmoother`

## Docs

- [48h soak test](Docs/SOAK_TEST.md)
- [Notarize](Scripts/notarize.sh)

## Permissions

Grant Full Disk Access, Notifications, and optionally Accessibility via **Permissions** in the popover footer.

---

**Developed by:** Faiz Nasir (Malaysia)  
**Owned by:** FG Universal Empire
