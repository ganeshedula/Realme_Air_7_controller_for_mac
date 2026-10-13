# Air7Menu local release report

Generated: 2026-10-13 17:18 IST; amended after UI runtime check: 2026-10-13

## Environment and project

- macOS 27.0.1 (26A434), arm64, Mac15,3.
- Xcode 27.0 (27A266a). Active `xcode-select` path is Command Line Tools; project builds used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Xcode project `Air7Menu.xcodeproj`; scheme `Air7Menu`; targets `Air7Menu` and `Air7Monitor`; Debug and Release configurations; deployment target macOS 13.0.
- Main bundle ID `com.local.air7menu`; helper bundle ID `com.local.air7menu.monitor`; version 1.0 (build 1).
- The project has no entitlements file/configuration. Xcode target signing is disabled; the local bundle was ad-hoc signed for integrity. It is not Developer ID signed or notarized.
- Disk at inspection: 211 GiB available.

## Build and tests

- Debug build passed: `xcodebuild -project Air7Menu.xcodeproj -scheme Air7Menu -configuration Debug -destination 'platform=macOS,name=My Mac' -derivedDataPath .build/Task3Baseline build`.
- Release build passed: `xcodebuild -project Air7Menu.xcodeproj -scheme Air7Menu -configuration Release -destination 'platform=macOS,name=My Mac' -derivedDataPath .build/Task3Release build`.
- SwiftPM suite passed: 10 tests, 0 failures. It covers RFCOMM frame parsing and recovery, payload bounds, parser reset, one-shot/timeout/sequence-reuse callback behavior, and battery decoding of zero and missing readings. SwiftPM caches were redirected to writable temporary directories.
- Build warnings: Xcode reports legacy headermap style in both targets; Simulator service/cache diagnostics occurred, but the macOS build completed successfully.

## Source and confirmed fixes in this build

The source includes `Air7FrameParser.swift`, `EarbudModel.swift`, `Air7Menu.xcodeproj/project.pbxproj`, `Package.swift`, and `Tests/Air7MenuTests/Air7FrameParserTests.swift` changes from the preceding task. The parser uses the representable UInt16 payload plus fixed header bound, recovers from malformed markers, and handles fragmented and batched input. RFCOMM state is synchronized; pending requests fail on close or timeout and complete once; SDP discovery is timed; duplicate battery readings do not publish redundant state. No source edits were needed in this task.

## Runtime and performance evidence

The existing LaunchAgent `gui/501/com.local.air7menu.monitor` was already running exactly one helper (PID 77657) from `/Users/ganesh/Downloads/Earbud app/Air 7 Menu.app/Contents/MacOS/Air7Monitor`. It remained present during the checks; this task did not change the user's installed app or LaunchAgent. The connected-earbud state was not established.

The final Release app was launched through the desktop UI. Its menu popover displayed “realme Buds Air 7 Disconnected”, the Bluetooth connection guidance, refresh action, and the existing “Show pop-up when earbuds connect” and “Launch at login” controls (both on). This verifies basic app launch and disconnected-state UI rendering only. It does not verify Bluetooth detection or device functionality.

Activity Monitor provided instantaneous samples while the Release app and existing helper were present. In the Memory view, the app (PID 83104 at the sample) showed 23.9 MB Memory and 72.0 MB Real Mem; helper `Air7Monitor` (PID 77657) showed 4.3 MB Memory and 2.2 MB Real Mem. Thus the displayed combined values were 28.2 MB Memory and 74.2 MB Real Mem. In the CPU view, the app showed 0.0% CPU at the later instantaneous sample (CPU time 0.74 s, four threads); the helper showed 0.0% CPU (CPU time 0.05 s, two threads). Both showed zero idle wakeups in that sample. These are point-in-time Activity Monitor readings, not a timed benchmark, allocation analysis, or evidence of sustained idle behavior. Activity Monitor's Real Mem and Memory columns are reported separately as displayed; the combined values are simple sums of those process rows.

An earlier helper-only snapshot, before launching this app, showed 2.4 MB Real Memory and 4.3 MB Memory, 0.0% CPU, 2 threads, and 0 idle wakeups. It is not directly comparable with the later app-plus-helper sample. The device connection state was not established for either snapshot.

The initial command-line LaunchServices attempts (`open`) returned `kLSNoExecutableErr`, and direct shell execution of the app aborted during AppKit application registration. These errors did not prevent the later desktop UI launch. The reason for the command-line launch discrepancy was not established; the crash report showed the abort in AppKit `NSApplication` registration/initialization, so it is not attributed to an application defect.

The Command + Shift + R shortcut was invoked in the UI. The UI automation call then reported that the app process was no longer available when it attempted to inspect the app, consistent with the quit action. However, Activity Monitor showed a process named `Air 7 Menu` again in the subsequent sample and a later PID, and the Relaunch check itself was not cleanly observed. Therefore shortcut termination is suggestive but the complete quit-and-relaunch scenario is not marked verified. The helper remained running throughout; launch-at-login behavior was not tested.

Instruments templates are installed (`Allocations`, `Leaks`, `Time Profiler`, and `Power Profiler` were listed after directing its cache to `/private/tmp`). Attaching Time Profiler to the existing LaunchAgent PID failed with `Cannot find process for provided pid: 77657`. No Instruments trace was collected. The 10-minute disconnected/connected/battery scenarios, 20-cycle reconnect stress, 60-minute idle, memory growth/allocation patterns, Energy Impact, and sleep/wake behavior are unmeasured. There is no Git repository/history here to reproduce a prior-build benchmark.

| Metric | Baseline | Optimized / final Release | Difference |
|---|---:|---:|---|
| App memory footprint (Activity Monitor Memory) | Unmeasured | 23.9 MB instant sample | Unmeasured |
| Monitor memory footprint (Activity Monitor Memory) | 4.3 MB helper-only instant sample | 4.3 MB instant sample | Not comparable |
| Combined memory footprint (Activity Monitor Memory) | Unmeasured | 28.2 MB instant sample | Unmeasured |
| Idle CPU utilization | Helper-only: 0.0% instant sample | App 0.0%, helper 0.0% instant sample | Unmeasured; states/durations differ |
| Active CPU utilization | Unmeasured | Unmeasured | Unmeasured |
| Energy Impact | Unavailable | Unavailable | Unmeasured |
| Wake Ups / Idle Wake Ups | Helper-only: 0 instant sample | App and helper: 0 instant sample | Not comparable |

## Feature verification

Verified on this Mac: Release app opens to its menu popover, shows the disconnected status and Bluetooth guidance, and renders the two existing preference controls. The UI showed both controls enabled. The app process was visible in Activity Monitor. The existing monitor helper remained visible as one process.

Not verified: physical earbud discovery/connection, disconnect/reconnect, left/right/case battery readings, low-battery notifications, connect pop-up behavior, Bluetooth refresh result, Liquid Glass appearance/animation beyond the basic visible popover, Launch at Login installation/activation, sleep/wake, and a complete Command + Shift + R quit/relaunch cycle. No paired earbud interaction was available in this run; no hardware success is inferred or simulated. The two-monitor architecture and external LaunchAgent configuration were inspected and left unchanged.

The helper is embedded at `Air7Menu.app/Contents/MacOS/Air7Monitor`. The current user LaunchAgent still points to `/Users/ganesh/Downloads/Earbud app/Air 7 Menu.app/Contents/MacOS/Air7Monitor`; this task did not change that user setting. After placing this local bundle at its intended permanent path, use the app's Launch at Login setting to refresh the helper path if needed.

## Deliverables and limitations

- `release/Air7Menu.app` — Release build, arm64, bundle integrity verified, ad-hoc signed for local use. The Release app launched successfully through desktop UI and displayed the disconnected-state popover.
- `release/Air7Menu-macOS.zip` — ZIP containing the app bundle; ZIP integrity and extracted bundle signature were checked separately.
- `release/BUILD-REPORT.md` — This report.

This is a local build and is not notarized or ready for unrestricted Gatekeeper distribution. The report records only point-in-time system resource readings; it does not establish a sustained performance improvement over a comparable baseline. Hardware-dependent behavior and longer profiling scenarios remain outstanding.
