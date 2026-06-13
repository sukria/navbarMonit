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

- **`SystemMetrics.swift`** — pure data layer. `sample()` returns a `Snapshot` of CPU/RAM/disk `0.0...1.0` ratios. CPU, **network** (`networkRate`, via `getifaddrs`) and **disk I/O** (`diskIORate`, via IOKit `IOBlockStorageDriver` statistics) are **stateful instance methods** — they store previous totals and report the per-second delta (first call returns 0). RAM/disk capacity, **battery** (`batteryInfo`, IOKit.ps) and **top process** (`topProcess`, shells out to `/bin/ps`) are **static**. `Detail` carries used/total/avail GB; `Rate` carries in/out bytes-per-second; `formatRate` pretty-prints. Note: `ps` emits locale-formatted decimals (e.g. `39,8`) — the parser normalizes the comma before `Double()`.
- **`Settings.swift`** — `Settings.shared` (UserDefaults-backed) with an `onChange` callback the app subscribes to. Toggles: bar visibility (`showCPU/RAM/Disk`), `showPercentText`, `displayMode` (.packed/.flat), `redThreshold`, `refreshInterval`, and detail rows (`showNetwork/DiskIO/Battery/TopCPU/TopRAM`). `LoginItem` wraps `SMAppService.mainApp`.
- **`SettingsWindowController.swift`** — programmatic `NSWindow` with a vertical `NSStackView`. Checkboxes share one `checkboxChanged(_:)` handler dispatched by a `Tag` enum; popups have their own actions. Every control writes straight to `Settings.shared`.
- **`main.swift`** — `AppDelegate` (also `NSMenuDelegate`) owns the `NSStatusItem`, the repeating `Timer` (interval from settings, rebuilt on change), and a cached `Readings` struct. Each tick refreshes `latest`, re-renders the icon and `toolTip` — it does **not** touch the menu. The menu is rebuilt fresh on open via `menuNeedsUpdate(_:)` from `latest` (+ live `topProcess` calls, which only run on open). Status button uses a **single action** on both mouse-up events: left click pops the menu (temporary-`menu`+`performClick` pattern, then detaches), right/⌃-click opens settings. Icon rendering takes a variable `[Bar]` array (only enabled bars); `renderEmpty` is the fallback when all bars are off. `color(for:threshold:)` normalizes usage by `redThreshold`. App runs as `.accessory`.

### Things to know

- The bundle's `Info.plist` lives at `Resources/Info.plist` and is copied by the `Makefile` `app` target. Bundle metadata changes (identifier, version, `LSUIElement`) go there.
- "Start at login" via `SMAppService` requires a real bundle; ad-hoc-signed/non-`/Applications` builds may fail to register — the checkbox reverts to the actual `SMAppService` status, by design.
- CPU temperature is deliberately not implemented — no reliable public API on Apple Silicon (private SMC access required).
- All code and comments are kept in **English**.
- Adding a bar metric: extend `Snapshot`/`Readings`, add a `Settings` toggle, append to `enabledBars()`; both `renderPacked`/`renderFlat` already handle any bar count. Adding a detail row: add a reader + `Settings` toggle, then a line in `menuNeedsUpdate` and `tooltip()`.
