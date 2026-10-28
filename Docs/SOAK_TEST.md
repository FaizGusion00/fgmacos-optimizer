# 48-Hour Soak Test Checklist

Use this checklist after building a Release configuration of **FGMacOS Optimizer**.

## Setup

- [ ] Build Release (`Product → Archive` or `./Scripts/build.sh`)
- [ ] Quit other unrelated menu-bar utilities that might skew metrics
- [ ] Start Docker Desktop with at least one container
- [ ] Launch a local AI runtime (Ollama / LM Studio / similar) if available
- [ ] Open ~100 browser tabs across Chrome or Safari
- [ ] Launch FGMacOS Optimizer and leave the popover closed

## Hourly / daily checks

- [ ] App still present in menu bar after overnight
- [ ] Idle memory (Activity Monitor → Memory) stays under **~20 MB** with popover closed
- [ ] CPU of `FGMacOS Optimizer` stays near 0% between samples
- [ ] Gauges still update when popover reopened
- [ ] Turbo Mode toggle on/off restores Spotlight (`mdutil -s /`)
- [ ] Watchdog lists real hogs only; Cursor / Terminal never appear as kill targets
- [ ] Clear Cache completes without UI freeze
- [ ] No beach-ball on the optimizer itself

## Failure criteria

- Memory climbs unboundedly hour over hour
- Main-thread hitch when opening popover
- Crash or disappearance from menu bar
- Accidental kill of whitelisted apps

## Capture

- Instruments → Allocations (attach to process) for 30 minutes idle
- Note peak RSS and any leaked objects
