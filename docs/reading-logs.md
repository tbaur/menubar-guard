# Reading the log

The login agent writes to `~/Library/Logs/menubar-guard.log`. Use `make status` for the last few lines, or `make logs` to follow it.

The program writes one line per change, not one per check, so the log grows slowly. It is not rotated on its own. `make rotate-log` moves it to `menubar-guard.log.1` and restarts the agent, which starts a new file.

Each line starts with a UTC timestamp. Problems are written as `error: …` lines, with the reason from macOS where there is one.

## Guard state

| Log line | Meaning |
|---|---|
| `started version=… pid=… margin=… session=…` | The program is running. The event tap exists and is off until it is needed. |
| `state=on bands=x=0..1920,y=0 margin=8 front=screen-sharing windows=[…]` | The guard is on. It blocks the top strip of the listed x range on the display whose top edge is at that y. |
| `state=off front=other` / `front=none` | Another app, or no app, came to the front. Other apps are never named in the log. |
| `state=off front=screen-sharing windows=[…:window]` | Screen Sharing is in front, but no window is full screen. |
| `state=off front=screen-sharing windows=unreadable` | Screen Sharing's windows could not be read 3 times in a row. |
| `state=off displays=changing` / `displays=changed` | The display layout is changing, or just changed. The guard turns off and reads the layout again. |
| `display change did not report its end after 5s; carrying on` | macOS started a display change but never reported the end, so the guard resumes. |
| `session=inactive` / `session=active`, `state=off session=inactive` | You switched user accounts away from this session, or back to it. The guard is off while the session is inactive. |
| `detail …` | With `--verbose` only: what the program saw changed, but the guard state did not. |
| `stopped by signal …` | The program was asked to stop. |

Window entries look like `1600x1000@0,0:full`: width, height, position, then `full`, `window`, or `unknown` when the window does not report its full-screen state.

## Permission and startup

| Log line | Meaning |
|---|---|
| `waiting for permission in System Settings > …` | The program has no permission yet and checks again every second. If its switch is already on, the entry is from an earlier build: remove it and add the binary again (see the README's Install section). |
| `accessibility=granted; restarting in place` | The permission arrived while the program was waiting. A process that started without the permission does not see it, so the program replaces itself with a fresh copy, keeping the same pid. launchd sees no exit, so there is no restart delay. A `started` line follows. |
| `accessibility=granted; exiting so that launchd starts a fresh copy` (or `granted again; …`) | The in-place restart was already tried, or could not run. The program exits with code 4 and launchd starts it again, at most 30 seconds after the last start. |
| `accessibility=granted` | The permission arrived and this process can use it, so it carries on without a restart. |
| `another copy is running; waiting for it to exit` | A second copy is waiting on the lock. |
| `accessibility=revoked`, `state=off accessibility=revoked` | The permission was removed. The guard is off. |
| `accessibility=granted again; restarting in place` | The permission came back after it was removed. The program replaces itself with a fresh copy, which creates a new event tap. |
| `error: could not restart in place: …; exiting` | The in-place restart failed. The program exits with code 4 instead. |

## Event tap

| Log line | Meaning |
|---|---|
| `tap was switched off from outside; totals timeout=… user-input=…` | Something other than this program switched the tap off. After a timeout, the program turns it back on at once. The program's own switch-offs are not counted, even though macOS reports them as user input. |
| `tap was off; turned it back on` | A regular check found the tap off while the guard was on, and turned it back on. |
| `tap stays off until the guard next turns on, because it was switched off by user input` | Something outside this program switched the tap off while the guard was on. The program respects that until the guard next turns on. |

## Errors

| Log line | Meaning |
|---|---|
| `error: could not … single-instance lock: …` | The lock file could not be used. Exit code 1. |
| `error: could not create the event tap; …` | macOS refused the tap, usually because the permission is missing. Exit code 1. |
| `error: could not set the Accessibility timeout; …` | The program carries on with the system's default timeout. |
| `error: could not watch for display changes; …` | The program carries on. It still reads the layout on every check. |
| `error: event tap is no longer valid; exiting` | Exit code 3. |
| `error: tap timed out 3 times in 60s; exiting` | macOS kept pausing the tap because it was too slow. The program exits rather than slow the pointer down. Exit code 3. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Stopped by a signal, or `--help`, `--version` or `--check` finished. |
| 1 | Could not start: the lock file could not be used, or the event tap could not be created. |
| 2 | Bad command-line options. |
| 3 | The event tap failed: it timed out 3 times in 60 seconds, or it became invalid. |
| 4 | The permission arrived while the program was running, and the in-place restart could not be used. Start the program again so that it can use the permission. launchd does this on its own. |

While the login agent is loaded, launchd starts the program again after any exit, at most once every 30 seconds. `make stop` and `make uninstall` unload it, so it stays stopped.
