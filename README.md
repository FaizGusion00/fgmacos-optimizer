# FGMacOS Optimizer

Premium macOS **menu-bar** optimizer — live metrics, Turbo Mode, Smart Watchdog, and Deep Cleaner.

## Download & install

**Latest release:** [FGMacOS Optimizer v1.10.3](https://github.com/FaizGusion00/fgmacos-optimizer/releases/tag/v1.10.3)

| File | What to do |
|------|------------|
| **[FGMacOS-Optimizer-v1.10.3.dmg](https://github.com/FaizGusion00/fgmacos-optimizer/releases/download/v1.10.3/FGMacOS-Optimizer-v1.10.3.dmg)** | Open DMG → baca **BACA-INI.txt** → right-click **00-INSTALL.command** → Open |

### “Apple could not verify…” / button **Done** only
Gatekeeper (unsigned free app). **Not malware.** After you click Done once:

1. **System Settings → Privacy & Security → scroll down → Open Anyway**, or  
2. Drag app to Applications, then Terminal:
   ```bash
   xattr -cr "/Applications/FGMacOS Optimizer.app" && open "/Applications/FGMacOS Optimizer.app"
   ```

Universal (Intel + Apple Silicon) · macOS 13 Ventura+.

First launch: right-click the app → **Open** (ad-hoc signed; Gatekeeper may warn).  
App lives in the **menu bar** (gauge / bolt icon) — no Dock icon.

**Requirements:** macOS 13 Ventura+ (Apple Silicon or Intel)

## Features

- **Menu-bar meters** — live CPU% · free RAM beside the icon
- **Focus profiles** — Meeting / Coding / Gaming (Turbo + leftovers + Low Power)
- **Status gauges** — RAM (with memory pressure) / CPU / Disk / Thermal / Battery
- **Before/after reports** — 3s banner after Free RAM, Clean, Kill, Focus, Cool down
- **Smart Free RAM** — suggest on pressure; optional auto (off by default, 30 min cooldown)
- **Storage map** — Caches / Downloads / DerivedData / Docker / Trash + one-tap clean
- **Network pulse** — up/down rates, top talker, Flush DNS
- **Thermal cool-down** — why it’s hot + kill hogs + Low Power on battery
- **24h CPU hall of fame** — history + Quit leftovers
- **Turbo Mode** — pause Spotlight *indexing*, stop Time Machine backup, clear Derived Data
- **Watchdog** — CPU hog + hung apps with whitelist
- **Cleaner suite** — Smart Care, Uninstaller + leftovers, Large & Old, Duplicates, Startup agents, TM local snapshots, Dev pack, Mail/Messages attachments, Space Lens, Browser caches (no cookies)
- **Schedule** — daily/weekly Smart Care scan + notification (confirm before clean)
- **History / Undo** — log cleaned paths; restore from Trash when still present
- **Protection list** — whitelist folders/apps so they never scan/clean
- **Shortcuts + Widget** — Free RAM / Turbo / DNS via Shortcuts; Notification Center widget
- **Security session** — one admin unlock reused for the timed window
- **Appearance** — Auto / Light / Dark · Open at Login

## Build from source

- macOS 13 Ventura+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
xcodegen generate
./Scripts/build.sh Release   # ad-hoc (fast debug)
```

For **Developer ID + notarize** (stable Accessibility / FDA across updates): see [Docs/SIGNING.md](Docs/SIGNING.md).

```bash
export DEVELOPMENT_TEAM=YOUR_TEAM_ID
./Scripts/sign_and_notarize.sh
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
