# MacKeyClean

A native macOS app that locks your keyboard so you can clean it without accidental input. The trackpad stays alive so you can click **Stop cleaning** when done.

## Features

- **Keyboard lock** — swallows all key events: regular keys, modifier combos (⌘⌥⇧⌃), function keys, and media/volume/brightness keys
- **Keyboard & Trackpad lock** — everything frozen for a fixed countdown, then auto-unlocks
- **Auto-unlock timer** — 30 sec to 5 min presets, or a custom value in seconds/minutes
- **Blank screen** — hides everything behind a black screen while cleaning, showing only the session state, a **Stop cleaning** button, and the failsafe hint
- **Failsafe key** — press it 5 times in a row to force-end the session even with the keyboard dead. Default is **Esc**; any key can be recorded as the failsafe. Presses must land within 2 seconds of each other, and a live `n/5` counter with dots shows how many have registered
- **Remembers your settings** — mode, duration, blank screen, and failsafe key persist between launches
- **App icon** — the KeyClean mark filling the macOS icon shape, shipped as `Resources/AppIcon.icns`
- **Safe by design** — the event tap is process-scoped; killing the app instantly restores all input, no permanent lockout possible
- No Xcode project, no dependencies — Swift Package Manager only

## Requirements

- macOS 13 or later (arm64)
- Xcode command-line tools (`xcode-select --install`)
- **Input Monitoring** permission (prompted on first launch)

## Build & Install

```bash
# Build the .app bundle (embeds Resources/AppIcon.icns)
./scripts/build_app.sh

# Install to ~/Applications and launch
./scripts/install.sh
```

The app is ad-hoc signed. macOS may prompt for Input Monitoring on first launch — click **Allow**. If the prompt doesn't appear, click **Open Settings** inside the app, then enable it in **System Settings → Privacy & Security → Input Monitoring**.

### Regenerating the app icon

`Resources/AppIcon.icns` is generated from `Resources/icon-source.png` by:

```bash
./scripts/make_icon.sh Resources/icon-source.png
```

The script accepts any source image:

1. **Background** — a source that still has one is matted by `scripts/matte.swift`: the flat
   background is removed, soft edges and the neutral shadow stay as real alpha, and the mark
   keeps its true colour (edges are un-premultiplied against white, so no white fringe appears
   on dark backgrounds). Light *tinted* details are treated as artwork and stay opaque, while
   neutral light pixels are recognised as background blends. A PNG that is already transparent
   skips this step, which `make_icon.sh` detects from the corner alpha.
2. **Shape** — `scripts/iconify.swift` trims the artwork, scales it to fit the canvas without
   cropping, propagates the nearest edge colour into the remaining canvas so gradients continue
   into the corners, and masks the result to the macOS icon shape (squircle).
3. **Sizes** — every icon size is rendered and packed into the `.icns`.

Step 2's mask is not cosmetic: macOS only draws an app icon as-is when its opaque silhouette is
the system icon shape. Any other silhouette is composited onto the system's own light plate,
which reads as a white background behind the logo. `iconify.swift` prints the measured silhouette
coverage and warns if it drifts off the icon shape.

## Usage

1. Launch MacKeyClean (a small window appears)
2. Pick a lock mode:
   - **Keyboard** — keyboard dead, trackpad alive; click Stop cleaning to exit anytime
   - **Keyboard + Trackpad** — everything frozen until the timer runs out
3. Pick an auto-unlock duration, or **Custom** for your own value
4. Optionally turn on **Blank screen** to black out the display while cleaning
5. Set the **Failsafe key** (default Esc) and press **Change** to record a different one — press Esc while recording to cancel
6. Click **Start cleaning**
7. Clean your keyboard
8. Stop by any of:
   - clicking **Stop cleaning** with the trackpad
   - pressing the failsafe key 5 times in a row
   - waiting for the countdown (timed modes)

While a session runs, the window and the black screen both show the session state, how many failsafe presses have registered, and a Stop button. `⌘Q` is swallowed like every other keystroke — use the Stop button or the failsafe key.

## Project Structure

```
MacKeyClean/
├── Package.swift
├── Sources/MacKeyClean/
│   ├── MacKeyCleanApp.swift        # App entry point
│   ├── ContentView.swift           # SwiftUI UI: settings, session panel, key recorder
│   ├── LockController.swift        # State, lock/unlock, countdown, settings persistence
│   ├── KeyboardBlocker.swift       # CGEventTap install, swallow callback, failsafe counter
│   ├── BlackoutController.swift    # Full-screen black overlay per display
│   ├── FailsafeKey.swift           # Failsafe key model and key-name labels
│   ├── FailsafeProgressView.swift  # Dots + n/5 counter for registered presses
│   └── Permissions.swift           # Input Monitoring permission helpers
├── Resources/
│   ├── AppIcon.icns                # App icon, mark filling the macOS icon shape
│   └── icon-source.png             # Source artwork for make_icon.sh
└── scripts/
    ├── build_app.sh                # swift build → .app bundle → ad-hoc codesign
    ├── install.sh                  # copy to ~/Applications and launch
    ├── make_icon.sh                # source image → Resources/AppIcon.icns
    ├── iconify.swift               # fit, corner fill and icon-shape mask
    └── matte.swift                 # background remover for opaque sources
```

## How It Works

A `CGEventTap` at `.cgSessionEventTap` intercepts events before they reach any app. When locked, the callback returns `nil` to swallow the event. The tap is installed once at launch and gated on the `isLocked` flag — no events are dropped when unlocked. A health-check timer re-enables the tap every 3 seconds to survive macOS's "silent disable" behavior after re-signing.

Because the tap swallows keystrokes before any app sees them, it is also the only place that can observe the failsafe key: the callback counts presses of the configured key code (ignoring key auto-repeat) and, on the fifth press within the burst window, force-ends the session.

The black screen is a borderless window per display at `.screenSaver` level. It is deliberately **not** key, so every keystroke still reaches the event tap — if the overlay took focus, the failsafe key could never fire. Trackpad clicks land on the overlay's Stop button, so that route stays available while the screen is blanked.

## Notes

- The power button and Touch ID cannot be intercepted (firmware-level) — this is a hardware limit, not a bug
- Modifier keys (⌘⌥⇧⌃) cannot be used as the failsafe key: they arrive as `flagsChanged`, never as key-down events
- Each rebuild may re-trigger the TCC/Input Monitoring prompt due to ad-hoc signing
- Bundle ID is `com.mackeyclean.app` — changing it resets TCC permissions
