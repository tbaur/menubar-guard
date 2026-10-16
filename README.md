# menubar-guard

Guard local hidden menu bar from sliding down over a full-screen Screen Sharing window.

When you share another Mac's screen in full screen and this Mac hides its menu bar, moving the pointer to the top edge brings this Mac's menu bar down over the remote one. macOS has no setting for "show the menu bar on the desktop, but never in full screen".

While Apple's Screen Sharing app is in front and full screen, menubar-guard keeps the pointer a few points below the top edge of that display. This Mac's menu bar stays hidden, and the remote menu bar is still right under the pointer. Hold Shift to reach this Mac's menu bar. In every other case the program changes nothing, and its event tap is switched off.

## Requirements

- macOS. Tested on macOS 27. The build targets the macOS version that you build on.
- Xcode Command Line Tools with Swift 6 (`xcode-select --install`).

## Install

```bash
make install
```

This checks the settings, runs the tests, builds the program, and starts it as a login agent for your account. It needs no `sudo`. Then:

1. Open System Settings > Privacy & Security > Device Control and Data Access.
2. Turn on `menubar-guard` (at `~/local/bin/menubar-guard`). If it is not listed, click `+` and add that file.
3. Run `make status`. You should see `state = running` and a `started` line.

It installs three files: the program in `~/local/bin/`, the login agent in `~/Library/LaunchAgents/local.menubar-guard.plist`, and the log in `~/Library/Logs/menubar-guard.log`.

You can change the defaults:

```bash
make install PREFIX=$HOME/bin LABEL=com.example.menubar-guard MARGIN=10
```

`PREFIX` must be an absolute path. `LABEL` and `PREFIX` may contain only letters, digits and `. _ -` (plus `/` and `+` in `PREFIX`). `MARGIN` is a number from 1 to 40. `make install` checks them before it changes anything. If you change `PREFIX` or `LABEL`, pass the same values to the other `make` targets.

To remove it, run `make uninstall`, then turn it off in Device Control and Data Access. The log file stays until you delete it.

## Permission

The program needs the Accessibility permission, which macOS 27 lists under Device Control and Data Access. It uses it to read the size, position and full-screen state of Screen Sharing's windows, and to move pointer events out of the top strip. It does not record the screen, read keystrokes, read files or use the network.

macOS gives the permission to whatever starts the program. For the login agent, that is the installed binary. When you run it from Terminal, including `make check`, that is Terminal. The login agent does not need Terminal's grant.

The build is signed ad hoc, so after a rebuild macOS may ask again. If the log shows it waiting for permission, turn it off and on again in the settings list.

## Usage

```text
menubar-guard [--margin POINTS] [--verbose]
menubar-guard --check [--margin POINTS]
menubar-guard --version | --help
```

| Option | Meaning |
|---|---|
| `--margin POINTS` | Height of the blocked strip, 1 to 40. Default 8. |
| `--verbose` | Log every change in what the program sees, not only on and off. |
| `--check` | Print what the program sees right now, including Screen Sharing's windows when it is not in front, then exit. |

Only one copy runs at a time. A second copy waits until the first one exits.

| Command | What it does |
|---|---|
| `make status` | Agent state, last exit code, and the last log lines. |
| `make logs` | Follow the log. |
| `make restart` | Restart the agent. |
| `make stop` | Unload the agent until the next login or `make install`. |
| `make rotate-log` | Start a fresh log. |
| `make check` | Run `--check` from the repository. Needs the permission for your terminal. |

[docs/reading-logs.md](docs/reading-logs.md) explains every log line and exit code.

## Troubleshooting

**This Mac's menu bar still comes down.** Put Screen Sharing in full screen and run `make status`. If the last line says `state=off`, the rest of the line says why. If it says `state=on`, the strip is too short for this Mac. Try `make install MARGIN=12`.

**I need this Mac's menu bar while in full screen.** Hold Shift and move to the top.

**I want to turn it off for a while.** Run `make stop`, and `make install` to bring it back.

## Limitations

- It knows only Apple's Screen Sharing app.
- It reads full-screen state from the undocumented `AXFullScreen` attribute. If a window does not report it, it checks whether the window exactly fills a display.
- While the guard is on, the pointer cannot reach the top few points of the display. Anything on the remote Mac that needs the very top edge, like its own auto-hidden menu bar, may not appear.
- It guards only the top edge, not the Dock.
- The multi-display rules are unit tested, but have only been tried on a single display.

## Development

```bash
make test     # unit tests for the pure logic
make build    # .build/menubar-guard
make clean
```

The pure logic lives in `Sources/Geometry.swift`, `State.swift`, `Options.swift` and `Describe.swift`, and `Tests/main.swift` tests it without XCTest. `Sources/Platform.swift` holds the macOS calls, and `Sources/main.swift` holds the monitor loop and the command line. [docs/how-it-works.md](docs/how-it-works.md) explains the design and each safeguard.

## License

Copyright 2026 tbaur

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) file for details.
