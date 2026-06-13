# NavbarMonit

A lightweight, dependency-free macOS menu bar system monitor. It shows three
mini progress bars in the top menu bar — **CPU**, **RAM** and **Disk** — each
fading from green to red as it approaches 100%. Click the icon for exact
percentages and totals.

## Requirements

- macOS 13+
- Xcode / Swift toolchain (`swift`, `make`)

## Build & run

```sh
make app    # build NavbarMonit.app
make run    # build and launch
make clean  # remove build artifacts
```

The app runs as a menu bar accessory (`LSUIElement`) — no Dock icon. Quit it
from its menu (**Quit NavbarMonit**, ⌘Q).

## Usage

- **Left click** — readout menu (live CPU/RAM/disk, Open Activity Monitor, Settings, Quit).
- **Right click** (or ⌃-click) — open the Settings window.
- **Hover** — tooltip with exact percentages and free space.

### Settings

Everything below is toggleable from the Settings window:

**Menu-bar bars** (ratio metrics, fade green → red):
- **CPU**, **RAM**, **Disk** — show/hide each bar independently.
- **Show percentage as text** next to the bars.
- **Layout** — *Packed* (horizontal bars stacked) or *Flat* (vertical bars side by side).
- **Turn red at** — usage threshold for full red (100% / 90% / 80%).
- **Refresh interval** — 1 / 2 / 5 / 10 seconds.

**Menu details** (textual rows in the dropdown + tooltip):
- **Network throughput** (↓/↑), **Disk I/O** (read/write), **Battery** (level + charging).
- **Top CPU process** and **Top memory process**.

**Start at login** — registers the app as a login item (`SMAppService`).

> Note: CPU temperature is intentionally omitted — there is no public API to read it
> reliably on Apple Silicon (it requires private SMC access).

## How it works

- **CPU** — `host_statistics(HOST_CPU_LOAD_INFO)`, busy/total tick delta between samples.
- **RAM** — `host_statistics64(HOST_VM_INFO64)`: active + wired + compressed pages.
- **Disk** — root volume capacity vs. available space.

Metrics refresh every 2 seconds.

## License

[GNU General Public License v3.0](LICENSE) © Alexis Sukrieh
