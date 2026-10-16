# How it works

This note explains the design and the reason for each safeguard. The [README](../README.md) covers install and daily use. [reading-logs.md](reading-logs.md) lists every log line and exit code.

## The two parts

The program has two parts that share one value: the list of strips to keep the pointer out of.

- **The monitor** runs on the main thread. It checks every half second. It also checks at once when the front app, the Space, the login session or the display layout changes, after wake, and when macOS switches the event tap off. Each check decides which strips should be active.
- **The event tap** runs on its own thread. While it is on, it sees every pointer event before other apps do. If an event lands inside an active strip, the tap moves it down to just below the strip.

The strip list sits behind an unfair lock, which passes priority to whoever holds it, so the user-interactive tap thread never waits behind a slower thread. The monitor publishes the list. The display callback, the signal handlers and every exit path clear it. The tap only reads it, once per event, and does nothing else, so it stays fast.

## Deciding when to block

The guard stays off while any of these is true:

1. The permission is missing.
2. The login session is not the one on screen. The program reads the real session state at start and then follows the session notifications.
3. A display change is under way.

Otherwise the monitor turns the guard on only when both of these are true:

1. The front app is Apple's Screen Sharing (`com.apple.ScreenSharing`).
2. One of its windows is full screen. The program reads the `AXFullScreen` attribute of each window through Accessibility. If a window does not report it, the program counts the window as full screen only if its frame exactly fills a display (to within 1 point). Frames that are not finite numbers, or are wildly out of range, are ignored.

The program sets a 0.25 second Accessibility timeout for the whole process. A timeout set on the app element alone would not cover the window elements that it returns. With the timeout, a stuck Screen Sharing cannot stall the monitor for long.

### The hold

Accessibility reads sometimes fail for a moment, and during the full-screen animation Screen Sharing can briefly list no windows at all. If the guard turned off at each such moment, it would flicker on and off. So the monitor keeps the current strips through these unreadable moments. It turns the guard off on the third unreadable look in a row, about 1.5 seconds. A good read resets the count.

The hold applies only to unreadable moments. If a read succeeds and shows no full-screen window, or another app comes to the front, the guard turns off at once.

## The strip

Event positions and Accessibility window frames use the same coordinates. The origin is the top left of the main display, and Y grows downward. `CGDisplayBounds` uses the same space. A display's top edge is therefore its smallest Y.

Each full-screen display gets a strip `margin` points high along its top edge. The default margin is 8 points. In testing, 2 points still let this Mac's menu bar come down, and 8 points did not.

When an event lands in the strip, the tap moves it to `top + margin` and keeps its X. The remote Mac's menu bar is drawn inside the Screen Sharing window at the top of the display, so it is still under the pointer.

### Which events are moved

The tap moves the pointer on moves, drags, and button presses and releases (left, right and other buttons). An earlier version moved only plain moves. Clicks at the very top then used the original position, and the remote menu bar could not be clicked at the top pixel. Moving every positional event keeps clicks and the visible pointer in the same place.

### Shift

If Shift is held, the tap leaves the event alone. This is the way to reach this Mac's menu bar while the guard is on.

### More than one display

A top edge is only a real screen edge where no other display sits directly above it. Where another display touches the edge from above, the pointer has to be able to move up into it. Otherwise the pointer would be trapped on the lower display. So the program splits the edge. It leaves the covered parts open and puts strips only on the parts with nothing above them. The unit tests cover side-by-side displays, a display fully above, a narrow display above that splits the edge, overlapping displays above, a display that overhangs one side, and a display that is near the edge but does not touch it.

## The event tap

The tap is created with `CGEvent.tapCreate` at `.cghidEventTap`, at the head of the queue, as an active filter. The SDK header says HID-level taps need root. In practice, on macOS 27, a HID tap works for a normal user with the Accessibility permission. This is the setup that was tested and is known to keep the menu bar hidden. Other tap locations have not been tested.

The main thread creates the tap and owns it. Its run loop source runs on a dedicated thread (`menubar-guard.tap`) with user-interactive priority, so a busy main thread never delays pointer events.

The tap starts switched off. The monitor switches it on only while there are strips to enforce, and off again when there are none. The rest of the time, pointer events do not pass through this process at all.

## Safeguards

| Event | What the program does | Why |
|---|---|---|
| A display change begins | The display callback clears all strips at the first "begin" call. The guard stays off until macOS reports the end, then the layout is read again. The several "end" calls, one per display, are merged into one check. | Strips from the old layout could block a real edge in the new one. |
| A display change never reports its end | After 5 seconds the guard resumes and logs it | The guard should not stay off forever because of one missing callback. |
| Switching users away from this session | Clears all strips until the session is active again | The tap should not affect another user's session. |
| Wake from sleep, Space change, app switch | Checks again right away | These are the moments when the full-screen state usually changes. |
| Accessibility permission is removed | Clears all strips, switches the tap off, and logs `accessibility=revoked` | The program cannot see windows without it, so it stops guessing. |
| The permission arrives while waiting at start | Checks every second. If only a trial event tap shows the grant, replaces itself with a fresh copy through `exec`, keeping the same pid | A process that started without the permission did not see the grant through the Accessibility check in testing. WindowServer checks the permission each time a tap is created, so a trial tap does see it. An `exec` gives a fresh process image without an exit, so launchd's 30-second restart delay does not apply. |
| The permission is given back after removal | Restarts in place the same way | The old tap may not work after the permission was removed. A fresh copy creates a new tap. |
| An in-place restart does not help | Exits with code 4, so launchd starts a new process | An environment marker survives the `exec`. A copy that still cannot use the permission sees the marker and exits instead of restarting again, so it never loops. The marker is cleared once the tap exists. |
| macOS switches the tap off after a timeout | The callback tells the main thread, which turns the tap back on at once if the guard is on. It logs and counts each time. | macOS does this when a callback is slow. |
| The tap is switched off by user input from outside the program | Leaves it off until the guard next turns on, and logs it | The SDK describes this as a user asking for taps to be switched off. macOS also reports the program's own switch-offs this way, as seen in testing, so the program counts its own and leaves them out. |
| The tap times out 3 times in 60 seconds | Clears all strips and exits with code 3 | A slow tap makes the whole pointer feel slow. Exiting is safer. launchd starts it again, at most once every 30 seconds. |
| The tap becomes invalid | Clears all strips and exits with code 3 | An invalid tap cannot be fixed in place. |
| A second copy starts | Waits on a lock file in the per-user temporary folder until the first copy exits | Two taps would both move events and fight over the state. |
| SIGINT, SIGTERM or SIGHUP | Clears all strips, logs, and exits with code 0 | This gives a clean stop for `launchctl`, `make restart` and Ctrl-C. |

The tap-timeout count uses time since boot, not the wall clock, so a clock change cannot make old timeouts look recent.

The program installs its signal handlers only after it has the lock, the permission, and the tap. Before that, the main thread may be blocked waiting, and the default signal action, which ends the process at once, is the right behavior. Nothing needs cleaning up at that point, because the tap does not exist yet.

## Logging

The program writes line-buffered output, so that each line reaches the launchd log file at once. It logs only changes, not every check. With `--verbose` it also logs each change in what it sees. It names no app other than Screen Sharing: other front apps appear only as `front=other`. For Screen Sharing it logs the size, position and full-screen flag of each window. It never logs window titles or anything typed. Errors go to standard error, which launchd sends to the same file, with the reason from macOS where there is one.

## Testing

Every decision lives in the pure files: `Geometry.swift`, `State.swift`, `Options.swift` and `Describe.swift`. They use only CoreGraphics geometry types and Foundation formatting, and `Tests/main.swift` tests them directly. That covers the strip math, the Shift bypass, full-screen detection, the hold, the reasons to stay off, tap health, option parsing and every log format.

`Platform.swift` and `main.swift` only feed real values into those decisions and act on the results. They cannot run in a test, because the event tap needs a real login session and the permission. Use `--check` and `--verbose` to see what the program sees on a real Mac.
