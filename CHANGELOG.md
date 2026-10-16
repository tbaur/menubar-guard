# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-15

### Added

- Keep the pointer out of a strip along the top edge while Apple's Screen Sharing is in front and full screen, so this Mac's hidden menu bar stays hidden.
- Move moves, drags, and button presses and releases, so clicks at the top reach the remote menu bar.
- Hold Shift to reach this Mac's menu bar.
- Leave parts of a top edge open where another display sits directly above it.
- Keep the strips through brief unreadable moments. Turn off at once when a read shows no full-screen window or another app comes to the front.
- Switch the event tap on only while the guard is on.
- Stay off while a display change is under way, while the session is inactive, and while the permission is missing. Restart for a fresh tap when the permission comes back.
- Turn the event tap back on at once after a timeout. Leave it off after a user-input disable from outside the program, and ignore the program's own switch-offs, which macOS reports the same way. Exit if it times out 3 times in 60 seconds or becomes invalid.
- Pick up the permission within a second or two, without a manual restart: when it arrives while waiting, restart in place through `exec`, so launchd's restart delay does not apply.
- GitHub Actions CI on macOS for tests, build, command-line and install-setting checks, and the login agent lint, plus `shellcheck` on Ubuntu. CodeQL scans the workflows when they change, and the Swift code weekly or on demand with a `make build`. Dependabot keeps the actions current.
- `make agent` builds and lints the login agent file without installing it.
- `make install` waits for the permission when it is missing: it opens System Settings, asks you to type `yes` once it is on, then restarts the agent and confirms that it is running.
- Bound every Accessibility read with a 0.25 second timeout.
- Run only one copy at a time.
- `--margin`, `--verbose`, `--check`, `--version` and `--help` options. `--check` finds Screen Sharing even when it is not in front.
- Exit codes 0 to 4, and errors with the reason from macOS.
- `make install` for a per-user login agent, with checked `PREFIX`, `LABEL` and `MARGIN` settings. Also `uninstall`, `stop`, `status`, `logs`, `rotate-log`, `restart` and `check`.
