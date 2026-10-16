import AppKit
import Foundation

private let VERSION = "1.0.1" // x-release-please-version
private let POLL_SECONDS: TimeInterval = 0.5
private let POLL_TOLERANCE_SECONDS: TimeInterval = 0.1
private let RELEASE_AFTER_MISSES = 3
private let TRUST_POLL_SECONDS: TimeInterval = 1
// Set across an in-place restart, so a copy that still cannot use the
// permission exits instead of restarting again.
private let RESTARTED_ENV = "MENUBAR_GUARD_RESTARTED"
private let DISPLAY_CHANGE_TIMEOUT_SECONDS = 5.0
// macOS switches a tap off when its callback is too slow. If that keeps
// happening, the program exits rather than slow the pointer down.
private let TIMEOUT_LIMIT = 3
private let TIMEOUT_WINDOW_SECONDS = 60.0

private enum ExitCode: Int32 {
    case stopped = 0
    case cannotStart = 1
    case badOptions = 2
    case tapFailed = 3
    case restartForPermission = 4
}

private let USAGE = """
usage: menubar-guard [--margin POINTS] [--verbose]
       menubar-guard --check [--margin POINTS]
       menubar-guard --version
       menubar-guard --help

While Screen Sharing is the front app and full screen, keeps the pointer a few
points below the top edge of that display, so this Mac's hidden menu bar does
not slide down over the remote one. Hold Shift to reach this Mac's menu bar.

  --margin POINTS  height of the blocked strip, \(Int(Options.MARGIN_RANGE.lowerBound))-\(Int(Options.MARGIN_RANGE.upperBound)) (default \(describe(margin: Options.DEFAULT_MARGIN)))
  --verbose        log every change in what the program sees, not only on/off
  --check          print what the program sees once, then exit
  --version        print the version, then exit
  -h, --help       print this help, then exit

Needs the Accessibility grant (Privacy & Security > Device Control and Data
Access on macOS 27) for the program that starts it. Only one copy runs at a
time; a second copy waits until the first one exits.

Exit codes: 0 stopped or done, 1 could not start, 2 bad options,
3 event tap failed, 4 permission arrived but an in-place restart was not
possible (start again).
"""

private let TIMESTAMP_STYLE = Date.ISO8601FormatStyle()

private func timestamp() -> String {
    Date.now.formatted(TIMESTAMP_STYLE)
}

private func log(_ message: String) {
    print("\(timestamp()) \(message)")
}

private func logError(_ message: String) {
    FileHandle.standardError.write(Data("\(timestamp()) error: \(message)\n".utf8))
}

private func stop(_ code: ExitCode) -> Never {
    activeBands.set([])
    exit(code.rawValue)
}

@MainActor
private final class Monitor {
    private let options: Options
    private let tap: EventTap
    private var hold = Hold(releaseAfterMisses: RELEASE_AFTER_MISSES)
    private var health = TapHealth(timeoutLimit: TIMEOUT_LIMIT, window: TIMEOUT_WINDOW_SECONDS)
    private var lastDetail = ""
    private var isTrusted = true
    private var isSessionActive = isSessionOnConsole()
    private var isTapWanted = false
    // Set when the user switched the tap off; honored until the guard next turns on.
    private var isTapHeldOff = false

    init(options: Options, tap: EventTap) {
        self.options = options
        self.tap = tap
    }

    var sessionText: String { isSessionActive ? "active" : "inactive" }

    func refresh() {
        checkTrust()
        checkTap()
        let reason = offReason(
            isTrusted: isTrusted,
            isSessionActive: isSessionActive,
            isDisplayChanging: isDisplayChangeUnderWay()
        )
        if let reason {
            release(reason: reason)
            return
        }
        let observation = observeFront(margin: options.margin)
        let isChanged = hold.update(observation.sighting)
        publish()
        if isChanged {
            log("\(describeState(bands: hold.bands, margin: options.margin)) \(observation.detail)")
        } else if options.isVerbose && observation.detail != lastDetail {
            log("detail \(observation.detail)")
        }
        lastDetail = observation.detail
    }

    func displaysChanged() {
        acknowledgeDisplayChange()
        release(reason: "displays=changed")
        refresh()
    }

    func setSessionActive(_ isActive: Bool) {
        isSessionActive = isActive
        log("session=\(sessionText)")
        refresh()
    }

    private func release(reason: String) {
        if hold.update(.notFront) {
            log("state=off \(reason)")
        }
        publish()
    }

    /// Hands the held bands to the tap, and keeps the tap on only while there
    /// is something to enforce.
    private func publish() {
        activeBands.set(hold.bands)
        if hold.bands.isEmpty {
            isTapHeldOff = false
        }
        let shouldRun = !hold.bands.isEmpty && !isTapHeldOff
        if shouldRun && isTapWanted && !tap.isEnabled {
            log("tap was off; turned it back on")
        }
        isTapWanted = shouldRun
        tap.setEnabled(shouldRun)
    }

    private func isDisplayChangeUnderWay() -> Bool {
        let startedAt = displayChangeStartedAt.get()
        if isDisplayChanging(startedAt: startedAt, now: uptime(), timeout: DISPLAY_CHANGE_TIMEOUT_SECONDS) {
            return true
        }
        if startedAt != nil {
            displayChangeStartedAt.set(nil)
            log("display change did not report its end after \(Int(DISPLAY_CHANGE_TIMEOUT_SECONDS))s; carrying on")
        }
        return false
    }

    private func checkTrust() {
        let isNowTrusted = isAccessibilityTrusted()
        guard isNowTrusted != isTrusted else { return }
        isTrusted = isNowTrusted
        if isNowTrusted {
            restartInPlace(reason: "accessibility=granted again")
        }
        log("accessibility=revoked")
    }

    private func checkTap() {
        guard isTrusted else { return }
        guard tap.isValid else {
            logError("event tap is no longer valid; exiting")
            stop(.tapFailed)
        }
        let report = health.check(tapDisables.get(), selfDisables: tap.selfDisables, at: uptime())
        if report.isChanged {
            let totals = health.totals
            log("tap was switched off from outside; totals timeout=\(totals.byTimeout) user-input=\(totals.byUserInput)")
        }
        if report.newUserInputs > 0 && !hold.bands.isEmpty {
            isTapHeldOff = true
            log("tap stays off until the guard next turns on, because it was switched off by user input")
        }
        if report.isTripped {
            logError("tap timed out \(TIMEOUT_LIMIT) times in \(Int(TIMEOUT_WINDOW_SECONDS))s; exiting")
            stop(.tapFailed)
        }
    }
}

@MainActor
private func printCheck(options: Options) {
    _ = configureAccessibilityTimeout()
    print("version: \(VERSION)")
    print("accessibility: \(isAccessibilityTrusted() ? "granted" : "not granted") (for the program running this check)")
    print("session: \(isSessionOnConsole() ? "active" : "inactive")")
    for display in activeDisplayBounds() {
        print("display: \(describe(display))")
    }
    let front = NSWorkspace.shared.frontmostApplication
    print("front: \(front?.bundleIdentifier ?? front?.localizedName ?? "none")")
    guard let app = runningScreenSharing() else {
        print("screen sharing: not running")
        return
    }
    let seen = observeScreenSharing(pid: app.processIdentifier, margin: options.margin)
    print("screen sharing: \(seen.detail)")
    guard case .windows(let bands) = seen.sighting, !bands.isEmpty else {
        print("would block when in front: nothing")
        return
    }
    print("would block when in front: \(bands.map { describe($0) }.joined(separator: ", ")) margin=\(describe(margin: options.margin))")
}

/// Replaces this process with a fresh copy of the program: same pid, same
/// arguments. launchd sees no exit, so its 30-second restart delay does not
/// apply. Falls back to exiting when exec fails or was already tried.
private func restartInPlace(reason: String) -> Never {
    activeBands.set([])
    guard getenv(RESTARTED_ENV) == nil, let path = Bundle.main.executablePath else {
        log("\(reason); exiting so that launchd starts a fresh copy")
        stop(.restartForPermission)
    }
    log("\(reason); restarting in place")
    for number in [SIGINT, SIGTERM, SIGHUP] {
        signal(number, SIG_DFL)
    }
    setenv(RESTARTED_ENV, "1", 1)
    fflush(stdout)
    var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) } + [nil]
    execv(path, &argv)
    logError("could not restart in place: \(String(cString: strerror(errno))); exiting")
    stop(.restartForPermission)
}

/// Returns once the permission is there. A process that started without it
/// does not see the grant through the Accessibility check, so when only the
/// event tap shows the grant, the program restarts in place.
private func waitForAccessibility() {
    if requestAccessibility() { return }
    log("waiting for permission in System Settings > Privacy & Security > Device Control and Data Access (Accessibility)")
    while true {
        Thread.sleep(forTimeInterval: TRUST_POLL_SECONDS)
        if isAccessibilityTrusted() {
            log("accessibility=granted")
            return
        }
        if canCreateEventTap() {
            restartInPlace(reason: "accessibility=granted")
        }
    }
}

private var signalSources: [DispatchSourceSignal] = []

@MainActor
private func stopOnSignals() {
    for number in [SIGINT, SIGTERM, SIGHUP] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler {
            log("stopped by signal \(number)")
            stop(.stopped)
        }
        source.resume()
        signalSources.append(source)
    }
}

@MainActor
private func observeSystem(_ monitor: Monitor) {
    let workspace = NSWorkspace.shared.notificationCenter
    let refreshing: [Notification.Name] = [
        NSWorkspace.didActivateApplicationNotification,
        NSWorkspace.activeSpaceDidChangeNotification,
        NSWorkspace.didWakeNotification,
    ]
    for name in refreshing {
        workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { monitor.refresh() }
        }
    }
    workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { monitor.setSessionActive(false) }
    }
    workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { monitor.setSessionActive(true) }
    }
    NotificationCenter.default.addObserver(forName: DISPLAYS_CHANGED, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { monitor.displaysChanged() }
    }
    NotificationCenter.default.addObserver(forName: TAP_DISABLED, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { monitor.refresh() }
    }
    if !watchDisplayChanges() {
        logError("could not watch for display changes; the layout is read again on each check only")
    }
}

@MainActor
private func run(options: Options) -> Never {
    // The waits below block the main thread, so SIGINT, SIGTERM and SIGHUP keep
    // their default action (terminate) until the handlers are installed.
    do {
        try lockSingleInstance(onWait: { log("another copy is running; waiting for it to exit") })
    } catch {
        logError("\(error)")
        stop(.cannotStart)
    }
    waitForAccessibility()
    if !configureAccessibilityTimeout() {
        logError("could not set the Accessibility timeout; reads use the system default")
    }
    guard let tap = EventTap.create() else {
        logError("could not create the event tap; check the permission for this program")
        stop(.cannotStart)
    }
    unsetenv(RESTARTED_ENV)
    stopOnSignals()
    let monitor = Monitor(options: options, tap: tap)
    observeSystem(monitor)
    let timer = Timer(timeInterval: POLL_SECONDS, repeats: true) { _ in
        MainActor.assumeIsolated { monitor.refresh() }
    }
    timer.tolerance = POLL_TOLERANCE_SECONDS
    RunLoop.main.add(timer, forMode: .common)
    log("started version=\(VERSION) pid=\(getpid()) margin=\(describe(margin: options.margin)) session=\(monitor.sessionText); hold Shift to reach this Mac's menu bar")
    monitor.refresh()
    RunLoop.main.run()
    stop(.stopped)
}

setvbuf(stdout, nil, _IOLBF, 0)

let options: Options
do {
    options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("menubar-guard: \(error)\n\n\(USAGE)\n".utf8))
    exit(ExitCode.badOptions.rawValue)
}

if options.isHelp {
    print(USAGE)
    exit(ExitCode.stopped.rawValue)
}
if options.isVersion {
    print("menubar-guard \(VERSION)")
    exit(ExitCode.stopped.rawValue)
}
if options.isCheck {
    printCheck(options: options)
    exit(ExitCode.stopped.rawValue)
}
run(options: options)
