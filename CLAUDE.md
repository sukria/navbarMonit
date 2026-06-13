# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `make app` — build the release binary and assemble `NavbarMonit.app`
- `make run` — build the bundle and launch it
- `make build` — compile the release binary only (`swift build -c release`)
- `make clean` — remove `.build/` and `NavbarMonit.app`

There is no test suite. To verify a change, run `make run`, confirm the icon appears in the menu bar, then quit with ⌘Q (or `pkill -x NavbarMonit`).

## Architecture

A dependency-free macOS menu bar system monitor written in Swift (SwiftPM executable, no Xcode project). Two source files:

- **`SystemMetrics.swift`** — pure data layer. Reads CPU/RAM/disk via Mach/BSD APIs only (no Foundation polling shells). `sample()` returns a `Snapshot` of three `0.0...1.0` ratios. CPU is **stateful**: it stores the previous tick counts and reports the busy/total *delta* between samples — so the first call after launch always returns 0 until a second sample exists. Static helpers (`diskDetail`, `ramTotalGB`) provide human-readable totals for the menu.
- **`main.swift`** — `AppDelegate` owns the `NSStatusItem`, a 2-second repeating `Timer`, and the live menu. Each tick calls `metrics.sample()`, re-renders the menu bar icon, and updates the three disabled menu rows. The icon is drawn programmatically in `renderBars(...)` into an `NSImage` (three stacked rounded bars, C/R/D labels); `color(for:)` interpolates hue from green (0.33) to red (0.0) by usage. The app runs as `.accessory` (no Dock icon).

### Things to know

- The app bundle's `Info.plist` is generated inline by the `Makefile` (`app` target), not stored as a file. Bundle metadata changes (identifier, version, `LSUIElement`) must be edited there.
- All code and comments are kept in **English**.
- Adding a new metric means: extend `Snapshot` + a private reader in `SystemMetrics`, then add a row/bar in `main.swift` (`renderBars` loops over fixed 3-element arrays — update `labels`/`values` and the row count).
