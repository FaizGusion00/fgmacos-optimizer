# Prompt for Claude Fable — FGMacOS Optimizer

**How to use:** Copy everything from the line below (`YOU ARE…`) to the end of this file. Paste into Claude Fable as the full task. Do not summarize — give Fable the whole thing.

---

YOU ARE a world-class macOS systems engineer + SwiftUI product engineer + QA lead in one brain.

Your mission is to take **FGMacOS Optimizer** and push it until it feels like the app people recommend when a friend’s Mac is dying: slow, hot, full disk, Spotlight crawling, Time Machine fighting them mid-work — and after they install this, the Mac feels usable again.

This is not a toy menu-bar experiment. This is a real product with a brutal honesty bar:

> **If someone downloads FGMacOS Optimizer, their Mac should get faster and more stable quickly — including very old Macs — and the optimizer itself must never become the reason the Mac is slow.**

You will explore, improve, implement, **build, install, and actually test** on this machine. Plans without proof are incomplete. Fancy UI without measured idle CPU is incomplete. “Should be fine” is not a test.

---

## 0. Repo & baseline

**Repo path:**
`/Users/faiznasir00/Development/fg/macos-app/fgmacos-optimizer`

**App identity:**
- Product name: FGMacOS Optimizer
- Bundle ID: `com.fgmacos.optimizer`
- Type: LSUIElement menu-bar app + Cleaner window suite
- Min OS: macOS 13.0+
- Stack: Swift / SwiftUI / AppKit popover / privileged helper via `PrivilegedRunner`

**Current baseline in tree (approx):** **v1.10.6** — Soft Turbo, Quick Optimize, Focus profiles, Watchdog, Storage Map, Smart Care Cleaner, on-demand quit by default (`keepInMenuBar = false`), idle-CPU fixes already landed after a bad ~25–30% idle bug.

Read the code. Do not assume docs are complete. Prefer truth in Swift files over memory.

Build helper:
```bash
./Scripts/build.sh Debug
# then install:
pkill -x 'FGMacOS Optimizer' 2>/dev/null || true
rm -rf "/Applications/FGMacOS Optimizer.app"
cp -R ".derivedData/Build/Products/Debug/FGMacOS Optimizer.app" "/Applications/"
open "/Applications/FGMacOS Optimizer.app"
```

When you ship meaningful improvements, bump together:
- `FGMacOSOptimizer/Resources/Info.plist`
- `FGOptimizerWidget/Info.plist`
- `FGMacOSOptimizer.xcodeproj/project.pbxproj` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`)
- `project.yml`

---

## 1. North star — what “perfect” feels like

Imagine three users:

1. **Auntie with a 2018 MacBook, 8GB RAM, disk 90% full**  
   She opens the app once. She taps one obvious green/primary button. Admin password once. Two minutes later: more free space, less beachballing, backup not slamming the disk, Spotlight not indexing DerivedData forever. She closes the panel. App quits. She didn’t need a PhD.

2. **Developer on Cursor + Docker + Xcode**  
   He wants Turbo for focus without nuking Spotlight volume-wide (that reindex storm ruined his day before). Coding Focus must never wipe DerivedData by surprise. Whitelist must protect Cursor/Terminal/Docker/Xcode.

3. **Power user who wants monitoring**  
   He enables **Keep in menu bar**. The agent watches RAM/CPU/thermal/hogs and nudges him. Idle CPU of FGMacOS Optimizer must stay ≈ **0–1%**. If monitoring costs 25% CPU, we failed the product.

Every feature decision answers: *Does this make a slow Mac feel faster/safer — without us becoming the hog?*

Tagline burned into the work:
**Make old Macs usable again. Make new Macs quieter. Never become the problem.**

---

## 2. Product principles (decision filters)

1. **Real speed > theater** — free disk that matters, pause backup storms, stop Spotlight thrash on heavy folders, free reclaimable RAM, quit true CPU hogs. No fake “health score” that burns GPU.
2. **Immediate + sustained** — Quick Optimize = instant one-shot. Turbo Mode = sustained Soft Turbo. Don’t blur them.
3. **Safe by default** — regenerable caches only; review UI for risky deletes; whitelist kills; clear admin reasons.
4. **On-demand by default** — don’t live in the background unless the user opts into Keep in menu bar.
5. **Honest telemetry in UI** — before/after RAM, bytes cleaned, exclusions count, DNS/TM status via `ActionReport`.
6. **Old-Mac first** — main-thread must stay light; scans capped; progress visible; no 500k-file freeze.
7. **Developer-respectful** — Coding focus ≠ Turbo hammer; DerivedData wipe opt-in only.
8. **Names must be unmistakable** — never again two “Boost” buttons.

---

## 3. Hard constraints — do not regress (blood lessons)

### 3.1 Spotlight / Soft Turbo
- **FORBIDDEN** as a Turbo toggle: volume-wide `mdutil -a -i off` / `mdutil -a -i on`.  
  That caused catastrophic reindex storms (`mds_stores` / `mdworker` eating the machine for hours).
- Soft Turbo ONLY:
  - path-level `mdutil -i off <path>` where safe
  - `.metadata_never_index` markers on heavy folders
  - `tmutil stopbackup`
  - optional DerivedData wipe **only** if `FeatureSettingsStore.clearDerivedDataOnTurbo` is on
- Turbo OFF must leave volume indexing alone (no reindex storm).
- Legacy repair: if volume indexing was left disabled by old builds, one-shot restore is OK (`TurboModeEngine.repairLegacyVolumeIndexingIfNeeded`).

### 3.2 Idle CPU / popover hosting
Historical failure mode:
- NSPopover kept SwiftUI tree alive when “closed”
- `AngularGradient` / conic gauges + `TimelineView(1s)` + forever pulse animations + `@Published` metrics while offscreen
- Result: **~25–30% CPU for ~7.5 hours** — ironic for an “optimizer”

Guards that must remain (improve, don’t delete):
- Detach popover content on close → `NSHostingController(rootView: EmptyView())`
- Attach full `OptimizerPopoverView` only when shown
- Solid gauge strokes (no AngularGradient gauges)
- No forever `TimelineView` / `repeatForever` while content can stay hosted
- Gate displayMetrics / watchdog UI publishes when `!isPopoverOpen`
- Network pulse only while open
- Conservative sampler / watchdog intervals when closed
- Default `keepInMenuBar = false` → quit when UI is done

### 3.3 Safety
- Never silent-delete Documents / Desktop / Photos libraries / Mail essentials.
- Cache cleaner uses denylist + regenerable folders (`SystemCleaner`).
- Docker prune only on explicit Deep Clean / Docker bucket — not inside Quick Optimize silently.
- Whitelist-protected apps never force-killed.
- Admin prompts: human reason strings; cancel must not brick state.
- No SIP disable, no kexts, no sketchy always-on root daemons.

### 3.4 Naming contract (keep this exact product language)
| UI | Job |
|----|-----|
| **Quick Optimize** | One-shot: safe caches, stale logs, TM pause, heavy Spotlight exclusions, DNS flush, RAM purge |
| **Turbo Mode** | Sustained Soft Turbo (exclusions + TM). Never label “Boost Now” |
| **Free RAM** | `purge` only |
| **Deep Clean** | caches + DNS + Docker unused |
| **Open Cleaner** | full suite / Smart Care review-and-confirm |
| **Keep in menu bar** | opt-in resident agent (required for Open at Login) |
| **Focus** Meeting / Coding / Gaming | profile behaviors; Coding must not hard-Turbo / wipe DerivedData |

If you add features, name them so a tired human at 1am cannot confuse them.

---

## 4. Scope of improvement (high leverage first)

Explore gaps vs north star, then implement the highest ROI work. Suggested pillars:

### A. First-open “wow” for old Macs
- Hero CTA = Quick Optimize (primary visual weight).
- Turbo secondary; Cleaner for deep space reclaim with review.
- If free disk critically low or memory pressure critical → urgent banner + one tap.
- Strong, honest `ActionReport` after every major action.

### B. Stronger Quick Optimize & Soft Turbo (real speed)
Audit and improve:
- `SystemCleaner.runSpeedBoost` / launch light boost
- Exclusion paths in `TurboModeEngine.heavyExclusionPaths` (Cursor/VS Code caches, Homebrew, npm, cargo, CocoaPods, Logs, Caches, simulators, Docker data path, etc.) — exclude from Spotlight, don’t reckless-delete user projects
- Stale logs cleanup caps (don’t freeze on huge trees)
- Progress copy during multi-step optimize
- Ensure Coding focus rules stay correct in `FocusProfileEngine`

### C. Monitoring that doesn’t hurt
Resident mode (Keep in menu bar ON):
- Throttled menu-bar meters
- Detached popover when closed
- Watchdog/Smart RAM useful but cheap
- Smart Care scheduler only in resident mode

On-demand (default):
- Close panel → app quits (Cleaner/Permissions open = don’t quit yet)
- No forgotten background hog

### D. Cleaner suite quality
- Smart Care: scan → review ticks → clean selected (never surprise)
- Storage Map reclaim estimates should match what Clean actually frees (honesty)
- Large/old / duplicates / uninstall: keep safety rails

### E. Stability & polish
- No main-thread disk walks
- Operation banner while long work runs; keep popover open during optimize
- Bundle version in footer (no hardcoded stale “v1.10.3”)
- Simple clear English copy
- Don’t break `Scripts/build.sh`, packaging, or `Docs/SIGNING.md` flows

---

## 5. Architecture map (read these)

```
FGMacOSOptimizer/App/AppState.swift          # actions, pace, Smart RAM, launch boost
FGMacOSOptimizer/App/AppDelegate.swift       # status item, attach/detach, on-demand quit
FGMacOSOptimizer/Core/TurboMode/TurboModeEngine.swift
FGMacOSOptimizer/Core/Cleaner/SystemCleaner.swift
FGMacOSOptimizer/Core/Cleaner/SmartCare*.swift
FGMacOSOptimizer/Core/Focus/FocusProfileEngine.swift
FGMacOSOptimizer/Core/Watchdog/*
FGMacOSOptimizer/Core/SystemMonitor/*
FGMacOSOptimizer/Support/FeatureSettingsStore.swift
FGMacOSOptimizer/Support/LaunchAtLoginStore.swift
FGMacOSOptimizer/UI/Popover/*                # ActionButtonsView, gauges, StartupSettings
FGMacOSOptimizer/UI/Cleaner/*
FGMacOSOptimizer/UI/Components/CircularGauge.swift
Scripts/build.sh
```

Match existing Swift style. Prefer surgical high-impact edits over fashionable rewrites.

---

## 6. MANDATORY TESTING — you must run this yourself

Do **not** say “please verify”. **You** build, install, click paths where possible, and capture evidence in your final report.

### 6.1 Build & install
```bash
cd /Users/faiznasir00/Development/fg/macos-app/fgmacos-optimizer
pkill -x 'FGMacOS Optimizer' 2>/dev/null || true
./Scripts/build.sh Debug
# confirm BUILD SUCCEEDED
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  ".derivedData/Build/Products/Debug/FGMacOS Optimizer.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  ".derivedData/Build/Products/Debug/FGMacOS Optimizer.app/Contents/Info.plist"
rm -rf "/Applications/FGMacOS Optimizer.app"
cp -R ".derivedData/Build/Products/Debug/FGMacOS Optimizer.app" "/Applications/"
open "/Applications/FGMacOS Optimizer.app"
sleep 3
pgrep -x 'FGMacOS Optimizer' || echo "FAIL: did not launch"
```

### 6.2 Test A — On-demand quit (default)
Goal: close UI → process gone.
```bash
# After launch, dismiss popover (Escape often works for transient popover):
osascript -e 'tell application "System Events" to key code 53' || true
sleep 2
pgrep -x 'FGMacOS Optimizer' && echo "FAIL: still running (on-demand broken)" || echo "PASS: quitted on-demand"
```
If Escape doesn’t dismiss, use the in-app Quit or click outside; still prove process exits when panel is done and Cleaner isn’t open.

### 6.3 Test B — Resident idle CPU (Keep in menu bar)
1. Launch app, enable **Keep in menu bar** in Startup section.
2. Close popover.
3. Wait 60–120 seconds.
4. Measure:
```bash
ps -axo pid,pcpu,pmem,etime,command | grep 'FGMacOS Optimizer.app' | grep -v grep
PID=$(pgrep -x 'FGMacOS Optimizer' | head -1)
sample "$PID" 3 -f /tmp/fgopt-idle.sample.txt
# FAIL signals in sample:
grep -E 'NSHostingView.layout|RepeatAnimation|AngularGradient|argb32_shade_conic|TimelineView' /tmp/fgopt-idle.sample.txt | head
```
**Pass criteria:** sustained CPU roughly **≤ 1%** (brief spikes OK). Sample must NOT show continuous SwiftUI layout/animation hot loops while closed.

### 6.4 Test C — Quick Optimize smoke
1. Open popover.
2. Run Quick Optimize (confirm dialog OK). Enter admin if prompted for DNS/purge.
3. Confirm `ActionReport` / banner shows real outcomes (caches/logs/DNS/RAM/TM/exclusions — whatever ran).
4. Confirm it did **not** prune Docker / wipe DerivedData unless those settings/paths were explicit.
5. Note any UI freeze >2s — if freeze, fix with background queues + progress.

### 6.5 Test D — Turbo Mode Soft (no reindex storm)
```bash
# Before / after Turbo on:
mdutil -s /
# Must remain indexing enabled on "/" (not "Indexing disabled") for Soft Turbo design
pgrep -l mdworker | head
pgrep -l mds_stores || true
```
Turn Turbo on, wait ~30–60s, confirm no explosion of mdworker CPU. Turn Turbo off, confirm still no volume reindex storm.

### 6.6 Test E — Coding Focus safety
Enable Coding focus. Confirm:
- Does not enable DerivedData wipe
- Does not use volume `mdutil -a`
- Copy/behavior matches “no hard Turbo”

### 6.7 Test F — Watchdog / whitelist sanity
If a hog appears in Watchdog, confirm whitelisted names (Cursor, etc.) cannot be killed. If no hog, at least code-path review + unit-level reasoning in report.

### 6.8 Test G — Naming / UX regression
Open popover and confirm labels:
- Quick Optimize present
- Turbo Mode present (not “Boost Now”)
- No duplicate confusing “Boost” twins
- Footer version matches installed Info.plist

### 6.9 Test H — Cleaner path (lightweight)
Open Cleaner → Smart Care scan starts or can start → UI responsive → close Cleaner. In on-demand mode, app should quit when no other UI remains (or stay only if Keep in menu bar on).

### 6.10 Regression battery after your edits
Re-run **6.2** and **6.3** after every substantive UI/lifecycle change. Idle CPU regressions are release blockers.

---

## 7. Evidence you must paste in the final answer

Your closing report must include:

1. **Version** you bumped to (marketing + build).
2. **What you changed** (user-visible wins first, then internals) — bullets.
3. **Why it helps old Macs** specifically.
4. **Test results table:**

| Test | Result | Evidence |
|------|--------|----------|
| Build | PASS/FAIL | log tail |
| On-demand quit | PASS/FAIL | pgrep output |
| Resident idle CPU | PASS/FAIL | `ps` %CPU + sample notes |
| Quick Optimize | PASS/FAIL | what report showed |
| Soft Turbo / mdutil -s / | PASS/FAIL | mdutil output |
| Coding focus safety | PASS/FAIL | notes |
| Naming | PASS/FAIL | labels seen |

5. **Residual risks** / what you did not finish.
6. **How a human tries it in 30 seconds** (click path).

If a test fails, **fix it** before ending. Do not hand back a known idle-CPU or Spotlight footgun.

---

## 8. Explicit anti-goals

- Fake scores, placebo gauges that animate forever and burn CPU  
- Particle candy that keeps hosting views dirty after close  
- “Disable SIP”, kernel extensions, shady background daemons  
- Login item without Keep in menu bar  
- Volume Spotlight off as a feature  
- Silent deletion of user documents/photos  
- Silent Docker prune inside Quick Optimize  
- Leaving a high-CPU idle agent “for monitoring”  
- Renaming things back to “Boost Now” / dual Boost confusion  
- Stopping at a plan or markdown-only “recommendation”

---

## 9. Working style

1. Explore the codebase thoroughly (grep + read critical engines).  
2. Pick the highest-leverage improvements vs the north star.  
3. Implement surgically; match existing style.  
4. Build → install → **run the mandatory tests**.  
5. Fix failures. Re-test.  
6. Bump version.  
7. Write the evidence report.

Think like the person who owns 1-star reviews that say *“optimizer used 30% CPU”* and refuse to ship that again. Think like the auntie with 8GB RAM who just wants the beachball to stop. Think like the developer who still needs DerivedData tomorrow morning.

---

## 10. Begin now

Start by surveying the repo against this brief. Then improve FGMacOS Optimizer until install → Quick Optimize → close feels like a real tune-up — especially on old Macs — with Soft Turbo available for sustained calm, and monitoring available only when the user opts in, at ≈0% idle cost.

**Implement. Build. Install. Test. Prove it. Then report with evidence.**
