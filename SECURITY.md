# Security Policy

## Reporting a Vulnerability

Do not open a public issue. Instead:

1. Go to the repository's **Security** tab and click **Report a vulnerability**
2. Or email the maintainer directly (contact on GitHub profile)

Include: description, reproduction steps, potential impact, and a suggested fix if you have one.

## Supported Versions

Security fixes are applied to the latest version on `main`.

## What the program can do

menubar-guard runs with the macOS Accessibility permission. That permission is powerful, so here is exactly what the program does with it:

- It reads the position, size and full-screen state of windows that belong to Screen Sharing (`com.apple.ScreenSharing`). It does not read windows of other apps.
- Its event tap is switched on only while Screen Sharing is in front and full screen. The rest of the time, pointer events do not pass through the program.
- While the tap is on, it changes the position of pointer events in a strip a few points high at the top of a display. It does not create or drop events. It does not read the keyboard, apart from checking whether Shift is held.
- It does not record the screen, read files, or use the network.
- It logs changes to `~/Library/Logs/menubar-guard.log`. Other front apps appear only as `front=other`. For Screen Sharing, a log line includes the size, position and full-screen flag of each window. The log has no window titles and no typed text.

## Install scope

`make install` writes only inside your home folder and loads a login agent in your own `gui/<uid>` launchd domain. It needs no `sudo` and runs as your user. It accepts only plain path characters in its settings, because they end up in shell commands and in the login agent file.

While it runs, the program also keeps an empty lock file in your per-user temporary folder (`$TMPDIR`), created with mode `0600`.
