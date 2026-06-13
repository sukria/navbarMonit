# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `make app` — build the release binary and assemble `NavbarMonit.app`
- `make run` — build the bundle and launch it
- `make build` — compile the release binary only (`swift build -c release`)
- `make clean` — remove `.build/` and `NavbarMonit.app`

There is no test suite. To verify a change, run `make run`, confirm the icon appears in the menu bar, then quit with ⌘Q (or `pkill -x NavbarMonit`).

## Architecture

A dependency-free macOS menu bar system monitor written in Swift (SwiftPM executable, no Xcode project). Four source files:

- **`SystemMetrics.swift`** — pure data layer. Reads CPU/RAM/disk via Mach/BSD APIs only. `sample()` returns a `Snapshot` of three `0.0...1.0` ratios. CPU is **stateful** (instance method): stores previous tick counts and reports the busy/total *delta* between samples — the first call after launch returns 0 until a second sample exists. RAM/disk are **static** (`ramUsage`/`diskUsage`/`ramDetail`/`diskDetail`); `Detail` carries used/total/avail GB for the menu and tooltip.
- **`Settings.swift`** — `Settings.shared` (UserDefaults-backed: `displayMode`, `refreshInterval`) with an `onChange` callback the app subscribes to. `LoginItem` wraps `SMAppService.mainApp` for the "Start at login" toggle. `DisplayMode` enum: `.packed` / `.flat`.
- **`SettingsWindowController.swift`** — programmatic `NSWindow` (NSGridView) with the login checkbox, display-mode popup and refresh popup. Each control writes straight to `Settings.shared`.
- **`main.swift`** — `AppDelegate` owns the `NSStatusItem`, the repeating `Timer` (interval from settings, rebuilt on change), and the menu. The status button uses a **single action** (`statusClicked`) on both mouse-up events: left click pops the menu via the temporary-`menu`+`performClick` pattern (then detaches so the action fires next time), right/⌃-click opens settings. Each tick re-renders the icon (`renderPacked` / `renderFlat`), updates menu rows and the `toolTip`. `color(for:)` interpolates hue green(0.33)→red(0.0) by usage. App runs as `.accessory`.

### Things to know

- The bundle's `Info.plist` lives at `Resources/Info.plist` and is copied by the `Makefile` `app` target. Bundle metadata changes (identifier, version, `LSUIElement`) go there.
- "Start at login" via `SMAppService` requires a real bundle; ad-hoc-signed/non-`/Applications` builds may fail to register — the checkbox reverts to the actual `SMAppService` status, by design.
- All code and comments are kept in **English**.
- Adding a metric: extend `Snapshot` + a reader in `SystemMetrics`, then update the fixed 3-element `labels`/`values` arrays in both `renderPacked` and `renderFlat`.
