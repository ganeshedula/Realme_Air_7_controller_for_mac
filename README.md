# Air 7 Menu

> A native macOS menu bar companion for the **realme Buds Air 7** — battery monitoring, noise control, spatial audio, and EQ presets without reaching for your phone.

![Menu bar controls showing the charging case battery as well as left and right earbud levels](screenshots/battery-case-and-controls.png)

---

## Table of Contents

- [Overview](#overview)
- [Screenshots](#screenshots)
- [Features](#features)
- [Architecture](#architecture)
  - [Targets](#targets)
  - [Source Files](#source-files)
  - [Project Layout](#project-layout)
- [Requirements](#requirements)
- [Build and Run](#build-and-run)
  - [Xcode](#xcode)
  - [Build Script](#build-script)
  - [Swift Package Manager](#swift-package-manager)
- [Testing](#testing)
- [How It Works](#how-it-works)
  - [Bluetooth Discovery & Connection](#bluetooth-discovery--connection)
  - [RFCOMM Frame Protocol](#rfcomm-frame-protocol)
  - [Battery Decoding](#battery-decoding)
  - [Push Events](#push-events)
  - [Launch at Login](#launch-at-login)
- [UI Components](#ui-components)
- [Configuration & User Defaults](#configuration--user-defaults)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Known Limitations](#known-limitations)
- [Protocol & Research Sources](#protocol--research-sources)
- [License](#license)

---

## Overview

Air 7 Menu is a lightweight, native macOS menu bar application built with **SwiftUI** for the realme Buds Air 7 (codenamed **Doraemon**). It lives in the menu bar and communicates with the earbuds over Bluetooth RFCOMM to read battery levels and send control commands — all without the official phone app.

The project consists of two executables packaged in a single `.app` bundle:

1. **Air7Menu** — The main SwiftUI menu bar application.
2. **Air7Monitor** — A background helper that watches for Bluetooth connect/disconnect events and automatically launches the main app when the earbuds connect.

---

## Screenshots

| Connection Pop-up | Menu Bar Controls |
| --- | --- |
| ![Connection pop-up showing the earbuds and left/right battery levels](screenshots/connection-pop-up.png) | ![Menu bar controls with left and right battery levels, noise control, spatial audio, EQ, and preferences](screenshots/connected-controls.png) |

![Menu bar controls showing the charging case battery as well as left and right earbud levels](screenshots/battery-case-and-controls.png)

---

## Features

### Battery Monitoring
- **Left & Right earbud** battery percentages displayed in real time.
- **Charging case** battery shown when the earbuds report it (hidden when case reports 0%, i.e. closed/unavailable).
- **Charging state indicator** — bolt icon shown for case charging (OPOv1 bit 7); earbud charging state is marked unknown since the protocol field is unverified.
- **Low-battery alerts** — floating HUD notifications at ≤20% (warning) and ≤10% (critical) thresholds with progressive alert stages to avoid repeating.
- **Connection pop-up** — compact floating battery card appears at the top of the screen when earbuds connect, auto-dismisses after 4 seconds.

### Listening Controls
- **Noise Control modes** — Noise Cancellation, Normal, and Transparency. Visual mode selector with animated highlight.
- **ANC Strength** — Smart, Max, Moderate, and Mild presets. The app enforces Max ANC when noise cancellation is active.
- **360° Spatial Audio** — Toggle on/off with spoken feedback via `AVSpeechSynthesizer`.
- **EQ Presets** — Serenade, Original Sound, Pure Bass, and Deep Bass.

### System Integration
- **Launch at Login** — Installs a `launchd` LaunchAgent for the `Air7Monitor` helper.
- **Explicit quit handling** — Records a UserDefaults flag so the monitor won't relaunch the app until the next earbud disconnect/reconnect cycle.
- **Bluetooth power monitoring** — App quits gracefully when Bluetooth is turned off.
- **CoreAudio route observation** — Detects when the system audio output changes.

---

## Architecture

### Targets

| Target | Type | Description |
| --- | --- | --- |
| `Air7Menu` | macOS app (menu bar) | Main SwiftUI application with popover UI, Bluetooth RFCOMM link, and battery/control logic. |
| `Air7Monitor` | Helper executable | Background Bluetooth connection watcher. Embedded at `Air7Menu.app/Contents/MacOS/Air7Monitor`. Runs as a LaunchAgent. |

### Source Files

```
Sources/
├── Air7Menu/
│   ├── Air7MenuApp.swift          # @main App entry point, MenuBarExtra, keyboard shortcuts, AppDelegate
│   ├── Air7FrameParser.swift      # RFCOMM frame parser (AA + LEB128 length + header + payload)
│   │                              # + Air7PendingRequests (thread-safe one-shot callback registry)
│   │                              # + Air7BatteryDecoder (OPOv1 battery snapshot decoder)
│   ├── EarbudModel.swift          # Core ObservableObject model:
│   │                              #   - BudsLink (RFCOMM connection, SDP discovery, frame I/O)
│   │                              #   - EarbudModel (state, controls, battery, notifications)
│   │                              #   - Air7NoiseMode, Air7ANCStrength, Air7ChargingState enums
│   │                              #   - LaunchAgent management (launchctl bootstrap/bootout)
│   └── PopoverView.swift          # SwiftUI views:
│                                  #   - PopoverView (main menu bar popover)
│                                  #   - BatteryBarCard (horizontal battery gauge)
│                                  #   - BatteryPopupView (compact floating connection banner)
│                                  #   - LowBatteryFloatingAlert (warning/critical HUD)
│                                  #   - BatteryPopupController & LowBatteryAlertController (NSPanel managers)
│                                  #   - Air7Design (design tokens: colors, radii, sizing)
├── Air7Monitor/
│   └── main.swift                 # Standalone helper:
│                                  #   - Air7BluetoothMonitor (IOBluetooth connect/disconnect observer)
│                                  #   - Respects explicit-quit flag, records connection events
│                                  #   - Launches main app via NSWorkspace on earbud connect
Resources/
│   └── Info.plist                 # Bundle metadata: ID com.local.air7menu, LSUIElement=true,
│                                  # Bluetooth usage description, macOS 13.0 minimum
Tests/
└── Air7MenuTests/
    └── Air7FrameParserTests.swift # 12 unit tests covering:
                                   #   - Complete/split/multi-frame parsing
                                   #   - Malformed frame resynchronization
                                   #   - Maximum UInt16 payload acceptance
                                   #   - Pending request take-once semantics
                                   #   - Timeout and sequence-reuse safety
                                   #   - Battery decoder (zero, missing, charging-flag preservation)
```

### Project Layout

```
.
├── Air7Menu.xcodeproj/           # Xcode project (Air7Menu + Air7Monitor targets)
├── Package.swift                 # Swift Package Manager manifest (swift-tools-version: 6.0, macOS 13+)
├── Sources/                      # Application source code
├── Tests/                        # Unit tests
├── Resources/Info.plist          # App bundle Info.plist
├── screenshots/                  # README screenshots
├── release/                      # Release artifacts
│   ├── Air7Menu.app              # Release build (ad-hoc signed)
│   ├── Air7Menu-macOS.zip        # Distributable ZIP archive
│   └── BUILD-REPORT.md           # Detailed build/verification report
├── build-app.sh                  # Local build + ad-hoc sign + launch script
├── .env.example                  # Environment template (no variables currently required)
└── .gitignore                    # Ignores .env, DerivedData, .build, local app bundles
```

---

## Requirements

| Requirement | Details |
| --- | --- |
| **macOS** | 13.0 (Ventura) or newer |
| **Xcode** | With macOS SDK and Swift 6 toolchain |
| **Hardware** | Paired realme Buds Air 7 for Bluetooth features. The app launches without connected earbuds (shows disconnected state). |
| **Bluetooth** | System Bluetooth must be enabled. The app requests `NSBluetoothAlwaysUsageDescription` permission. |

---

## Build and Run

### Xcode

1. Open `Air7Menu.xcodeproj`.
2. Select the **Air7Menu** scheme and **My Mac** as the destination.
3. Build and run (`⌘R`).

The Xcode project includes both the `Air7Menu` and `Air7Monitor` targets. The monitor helper is embedded inside the app bundle at `Contents/MacOS/Air7Monitor`.

### Build Script

For a quick local build without opening Xcode:

```sh
./build-app.sh
```

This script:
1. Builds the Debug configuration using `xcodebuild`.
2. Copies the built bundle to `Air 7 Menu.app` in the project root.
3. Ad-hoc code-signs it (`codesign --force --deep --sign -`).
4. Opens the app.

> **Note:** Requires Xcode at `/Applications/Xcode.app` or a valid `DEVELOPER_DIR`. This is **not** Developer ID signing or notarization — the bundle is for local use only.

### Swift Package Manager

The project also has a `Package.swift` for building via SwiftPM:

```sh
swift build
```

The package defines an executable target `Air7Menu` (Sources/Air7Menu) and a test target `Air7MenuTests`. The Swift language mode is set to Swift 5 for compatibility.

---

## Testing

Run the full test suite:

```sh
swift test
```

The test suite contains **12 tests** in `Air7FrameParserTests` covering:

| Test | What It Verifies |
| --- | --- |
| `testCompleteFrame` | Single complete frame is parsed correctly |
| `testFrameSplitAcrossChunks` | Frame split across two data chunks reassembles correctly |
| `testMultipleFramesInOneChunk` | Multiple concatenated frames in one delivery are all parsed |
| `testIncompleteFrameIsRetainedAndThenCompleted` | Partial frame is buffered and completed when remaining bytes arrive |
| `testMalformedAndOversizedFramesResynchronizeToNextMarker` | Short body, invalid LEB128, and oversized length are all skipped; parser resynchronizes to next valid `0xAA` marker |
| `testMaximumUInt16PayloadIsAcceptedAndResetDiscardsPartialFrame` | 65,535-byte payload accepted; `reset()` discards partial state |
| `testPendingRequestIsTakenOnlyOnceAndCloseFailsRemainingCallbacks` | Callback fires exactly once; `failAll()` drains remaining |
| `testPendingRequestTimesOutAndReleasesItsCompletion` | Timeout fires the completion with sentinel `0xFFFF` |
| `testSequenceReuseFailsOldCallbackWithoutLettingItsTimeoutFailTheNewOne` | Re-registering same sequence ID cancels old timeout, old callback receives failure, new callback is unaffected |
| `testBatteryDecoderPreservesZeroAndRepresentsUnavailableAsMissing` | Zero battery is a valid reading; missing device IDs are absent from the dictionary |
| `testBatteryDecoderPreservesPercentagesWithoutInferringCharging` | Bit 7 charging flag is preserved for Case; earbuds report `.unknown` charging state |
| `testBatteryDecoderPreservesZeroAndUnknownForMissingDevice` | Single-entry payload with zero percentage and missing Right entry |

---

## How It Works

### Bluetooth Discovery & Connection

1. **IOBluetooth device enumeration** — scans paired devices for a connected earbud matching:
   - A previously saved Bluetooth address (`air7.bluetoothAddress` in UserDefaults)
   - The current audio route's Bluetooth address (extracted from CoreAudio device UID)
   - Device names containing "realme buds air 7", "air7", or "doraemon"
2. **SDP query** — performs a full SDP database query on the matched device (filtered searches fail on some Realme firmware).
3. **Control service lookup** — searches for the BBK/OPPO companion service UUID (`0000079A-D102-11E1-9B23-00025B00A5A5` or `00001107-…`).
4. **RFCOMM channel** — opens a synchronous RFCOMM channel to the discovered service, enabling bidirectional command/response communication.
5. **Product identity** — sends command `0x0103` to verify the connected device is a realme Buds Air 7 (product ID `0x064812`).

### RFCOMM Frame Protocol

Frames follow the BudsLink/OPOv1 wire format:

```
┌──────┬──────────────────┬─────────────────────────────────┬──────────┐
│ 0xAA │ LEB128(bodyLen)  │ 2B zero + 2B cmd + 1B seq + 2B │ payload  │
│      │ (1–3 bytes)      │ payloadLen (LE)     = 7B header │          │
└──────┴──────────────────┴─────────────────────────────────┴──────────┘
```

- **Marker**: `0xAA` start byte.
- **Length**: LEB128-encoded body length (header + payload).
- **Header** (7 bytes): 2 zero bytes, 2-byte little-endian command ID, 1-byte sequence number, 2-byte little-endian payload length.
- **Payload**: Variable-length data (max 65,535 bytes, bounded by UInt16).

The `Air7FrameParser` handles fragmented input, batched frames, malformed markers, and automatically resynchronizes on corruption.

### Battery Decoding

Battery responses (command `0x0106` and push `0x0204` with prefix `1`) contain:

```
[count] [id₁, raw₁] [id₂, raw₂] ...
```

- **ID mapping**: `1` = Left, `2` = Right, `3` = Case.
- **Raw value**: Bits 0–6 = percentage (clamped to 100); Bit 7 = charging flag (verified for Case only via OPOv1 documentation; earbuds report `.unknown`).
- An optional 1-byte prefix offset is auto-detected for firmware variations.

### Push Events

The earbuds asynchronously push state changes:

| Command | Prefix | Content |
| --- | --- | --- |
| `0x0204` | `1` | Battery update |
| `0x0204` | `3` | ANC/noise mode change |
| `0x0504` | — | EQ preset change |

### Launch at Login

The app installs a `launchd` LaunchAgent plist at `~/Library/LaunchAgents/com.local.air7menu.monitor.plist` pointing to the embedded `Air7Monitor` binary. The plist is configured with `RunAtLoad: true` (but **not** `KeepAlive`, to avoid restart loops after explicit quit). The monitor:

1. Watches IOBluetooth connect/disconnect notifications.
2. Records a timestamped connection event in UserDefaults + posts a `DistributedNotification`.
3. Launches the main app via `NSWorkspace` unless the user has explicitly quit.
4. Clears the explicit-quit flag on earbud disconnect to re-enable auto-launch for the next session.

---

## UI Components

| Component | Description |
| --- | --- |
| **PopoverView** | Main menu bar popover — dark glassmorphic panel with emerald/blue ambient gradients, header with connection status, battery dashboard, listening controls, and preferences footer. |
| **BatteryBarCard** | Horizontal battery gauge with animated capsule progress bar, percentage label, charging bolt icon, and color-coded warnings (orange ≤20%, red ≤10%). |
| **BatteryPopupView** | Compact floating connection banner shown at screen top on earbud connect. Includes left/right battery cards. Auto-dismisses after 4 seconds with fade animation. |
| **LowBatteryFloatingAlert** | Capsule-shaped floating HUD for low/critical battery warnings. Shows affected sides and percentages. Dismisses after 5 seconds. |
| **Air7Design** | Centralized design tokens — accent color (`#33D191`), glass edge, warning/critical colors, panel/card corner radii, content width. |

All views use `preferredColorScheme(.dark)` and respect `accessibilityReduceMotion` for animations.

---

## Configuration & User Defaults

| Key | Type | Description |
| --- | --- | --- |
| `air7.bluetoothAddress` | String | Saved Bluetooth MAC of the paired earbuds |
| `air7.showPopupOnConnection` | Bool | Show the battery pop-up when earbuds connect |
| `air7.autoLaunchMonitor` | Bool | Launch at login preference |
| `air7.userDidExplicitlyQuit` | Bool | Flag to prevent auto-relaunch after user quits |
| `air7.connectionEventTimestamp` | Double | Timestamp of last connection event (set by monitor) |
| `air7.connectionEventName` | String | Device name from last connection event |

---

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘⌥B` | Show battery pop-up |
| `⇧⌘R` | Quit Air 7 Menu |

---

## Known Limitations

- **Protocol is reverse-engineered** — The Air 7 vendor protocol is not officially documented. Behavior is derived from community OPOv1/BBK reverse-engineering (OppoPods, Realme-TWS-Mac-Controller). Not every command or response has been independently verified on Air 7 hardware.
- **Charging state** — Only the charging case has a verified charging flag (bit 7). Left and right earbud charging states are reported as "unknown".
- **No notarization** — The app is ad-hoc signed for local use only. It is not Developer ID signed or notarized for Gatekeeper distribution.
- **Firmware variability** — Some controls may not be available depending on earbud firmware version and macOS behavior. Unavailable controls do not necessarily indicate an app problem.
- **Single device** — Currently supports one paired realme Buds Air 7 at a time.
- **No entitlements** — The project has no entitlements file. Xcode target signing is disabled.

---

## Protocol & Research Sources

- [realme Buds Air 7 product manual/specification](https://manuals.plus/m/70aa0bdacdae1e027c2bf2549970d08cce20e117363fea8346022cfd3ba0fa8d)
- [Realme TWS Mac Controller protocol notes](https://github.com/anikket-b/Realme-TWS-Mac-Controller) — mappings documented for Buds T500 Pro, not a complete Air 7 verification
- [OppoPods implementation](https://github.com/Leaf-lsgtky/OppoPods) — battery values as index/raw pairs with bit 7 charging flag
- [BudsLink Air 7 testing request](https://github.com/maniacx/BudsLink/issues/60) — community request for Air 7 owners to capture device details and test a configuration
- [Build verification report](release/BUILD-REPORT.md) — detailed checks performed for each build and scenarios that remain unverified

---

## License

This project does not currently specify a license. Please contact the author for usage terms.
