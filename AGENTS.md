# AGENTS.md — rules for Codex (and humans) working in this repo

## Simulator workflow — NEVER leak like the 2026-06-04 22 GB incident

A previous Codex job on this machine left ~22 GB of RSS across `SimulatorTrampoline`,
orphaned dyld cache pages, and three live `WristAssistant` processes inside an iPhone
simulator. Root causes were:

1. `xcrun simctl launch --console-pty booted … &` — backgrounded with a held PTY.
2. Three `simctl launch` calls against the same bundle with no `simctl terminate` between.
3. `sleep 60-180; simctl io booted screenshot` loops while the sim kept running.
4. **No `simctl shutdown` at end of job.**
5. `xcodebuild` with no `-derivedDataPath`, scattering build artefacts into both
   `./build/derived` and `./build/DerivedData` across runs.

### Hard rules for every future job in this repo

- **Always use `scripts/sim.sh`** for any simulator work. Do not call
  `xcrun simctl boot / install / launch / shutdown` directly from a freeform command.
- **One boot, one install, one launch per `sim.sh boot` invocation.** If you need
  a second launch (e.g. to re-seed with a different env var), call
  `sim.sh teardown` first, then `sim.sh boot` again.
- **Never combine `--console-pty` with `&`.** If you must capture app stdout, use
  `simctl launch --console booted <bundle> >log 2>&1` in the foreground, then
  `cat log` after a bounded sleep.
- **Never `sleep > 10` waiting on a sim.** Poll with
  `xcrun simctl spawn booted launchctl print system | grep -i wristassistant`
  or just trust `simctl bootstatus <udid> -b`.
- **Always end the job with `sim.sh teardown`**, even on error. The script also
  installs an `EXIT` trap on `boot`, so a hard session kill still releases the sim.
- **Always pass `-derivedDataPath ./build/derived`** to `xcodebuild` so the build
  lands in exactly one place. The repo root is `./`, not `~/Library/Developer/Xcode/`.
- If a job *does* see `SimulatorTrampoline` RSS climb past 200 MB or a
  `com.wristassistant` process appear in `pgrep -lf WristAssistant` after
  teardown, that is a regression — stop, file it, do not continue booting sims.

### Quick reference

```bash
scripts/sim.sh status        # report current sim/host state
scripts/sim.sh build         # xcodebuild only
scripts/sim.sh boot          # build + boot + install + launch + screenshot
scripts/sim.sh screenshot /tmp/x.png   # capture the booted sim
scripts/sim.sh teardown      # terminate app + shutdown all sims
```
