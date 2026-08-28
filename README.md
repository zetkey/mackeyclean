# MacKeyClean

A native macOS app that locks your keyboard so you can clean it without accidental input. The trackpad stays alive so you can click **Unlock** when done.

## Features

- **Keyboard lock** — swallows all key events: regular keys, modifier combos (⌘⌥⇧⌃), function keys, and media/volume/brightness keys
- **Keyboard & Trackpad lock** — everything frozen for a fixed countdown, then auto-unlocks
- **Auto-unlock timer** — 1, 5, 10, or 30 minutes; or manual (keyboard-only mode)
- **Safe by design** — the event tap is process-scoped; killing the app instantly restores all input, no permanent lockout possible
- No Xcode project, no dependencies — Swift Package Manager only

## Requirements

- macOS 13 or later (arm64)
- Xcode command-line tools (`xcode-select --install`)
- **Input Monitoring** permission (prompted on first launch)

## Build & Install

```bash
# Build the .app bundle
./scripts/build_app.sh

# Install to ~/Applications and launch
./scripts/install.sh
```

The app is ad-hoc signed. macOS may prompt for Input Monitoring on first launch — click **Allow**. If the prompt doesn't appear, click **Grant Input Monitoring** inside the app, then enable it in **System Settings → Privacy & Security → Input Monitoring**.

## Usage

1. Launch MacKeyClean (a small window appears)
2. Choose a lock mode:
   - **Keyboard** — keyboard dead, trackpad alive; click Unlock to exit anytime
   - **Keyboard & Trackpad** — everything frozen until the timer runs out
3. Choose an auto-unlock duration (required for Keyboard & Trackpad mode)
4. Click **Lock**
5. Clean your keyboard
6. Click **Unlock** (keyboard mode) or wait for the countdown (full lock mode)

## Project Structure

```
MacKeyClean/
├── Package.swift
├── Sources/MacKeyClean/
│   ├── MacKeyCleanApp.swift     # App entry point
│   ├── ContentView.swift        # SwiftUI UI, mode/duration pickers
│   ├── LockController.swift     # State, lock/unlock logic, countdown timer
│   ├── KeyboardBlocker.swift    # CGEventTap install, swallow callback, health-check
│   └── Permissions.swift        # Input Monitoring permission helpers
└── scripts/
    ├── build_app.sh             # swift build → .app bundle → ad-hoc codesign
    └── install.sh               # copy to ~/Applications and launch
```

## How It Works

A `CGEventTap` at `.cgSessionEventTap` intercepts events before they reach any app. When locked, the callback returns `nil` to swallow the event. The tap is installed once at launch and gated on the `isLocked` flag — no events are dropped when unlocked. A health-check timer re-enables the tap every 3 seconds to survive macOS's "silent disable" behavior after re-signing.

## Notes

- The power button and Touch ID cannot be intercepted (firmware-level) — this is a hardware limit, not a bug
- Each rebuild may re-trigger the TCC/Input Monitoring prompt due to ad-hoc signing
- Bundle ID is `com.mackeyclean.app` — changing it resets TCC permissions
