# Smoke checklist — Focus features (v1.8.0)

## Gate (every build)
- [x] Release universal build (`arm64` + `x86_64`)
- [x] Install to `/Applications`, `xattr -cr`, launch
- [x] Menu bar stays up after closing Permissions / alerts
- [x] Widget appex embedded under `Contents/PlugIns/`
- [x] Metrics snapshot written (`/tmp/com.fgmacos.optimizer.metrics.json`)

## Phase features
- [ ] Menu-bar meters show `CPU% · RAMg` (Startup → toggle off clears title)
- [ ] Free RAM / Clean / Kill Hogs show ActionReport banner ~3s
- [ ] Smart Free RAM chip when pressure elevated; Auto toggle default OFF
- [ ] Focus Meeting / Coding / Gaming / Off — ≤1 admin prompt when unlocked
- [ ] Storage map sizes + Clean per bucket (confirm on Downloads/DerivedData/Trash/Docker)
- [ ] Network pulse rates move; Flush DNS chip
- [ ] Thermal story + Cool down
- [ ] Hall of fame collects after load; Quit leftovers whitelist-safe
- [ ] Shortcuts: Free RAM / Turbo / Flush DNS appear for FGMacOS Optimizer
- [ ] Widget (Notification Center): CPU / RAM after app has run ≥5s

## Auth regression
- [ ] Unlock once → Free RAM / DNS / Turbo reuse session (no 2nd/3rd password)
