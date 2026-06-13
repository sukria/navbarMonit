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

## How it works

- **CPU** — `host_statistics(HOST_CPU_LOAD_INFO)`, busy/total tick delta between samples.
- **RAM** — `host_statistics64(HOST_VM_INFO64)`: active + wired + compressed pages.
- **Disk** — root volume capacity vs. available space.

Metrics refresh every 2 seconds.

## License

[GNU General Public License v3.0](LICENSE) © Alexis Sukrieh
