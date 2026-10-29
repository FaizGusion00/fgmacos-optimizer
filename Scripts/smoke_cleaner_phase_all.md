# Smoke — Cleaner suite v1.9.0

## Gates
- [x] Release universal build
- [x] `swift Scripts/safety_checks.swift` passes (path blocklist)
- [x] Install + launch; menu bar stays after closing Cleaner window
- [ ] Popover **Cleaner** opens dedicated window (~720×560)

## Tabs
- [ ] Smart Care: Scan → select safe → Clean selected (caches / trash / optional RAM)
- [ ] Uninstaller: pick app → leftovers checklist → Trash (Apple/self hidden)
- [ ] Large & Old: >100MB / >30d under Downloads/Documents/Desktop/Movies/Music → Trash
- [ ] Duplicates: enable toggle → Downloads hash → Trash dups
- [ ] Startup: disable user LaunchAgent (reversible); Apple/system read-only
- [ ] Snapshots: list `tmutil` locals → thin selected (admin)
- [ ] Dev: DerivedData / sim / npm / pip / brew cleanup
- [ ] Mail & Messages: large stale attachments → Trash (FDA if empty)
- [ ] Space Lens: Home + Applications sizes
- [ ] Browsers: cache on, history off; Cookies untouched

## Auth
- [ ] Unlock once → purge / DNS / snapshot thin reuse session
