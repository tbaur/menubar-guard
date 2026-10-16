import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

let SCREEN_SHARING_BUNDLE_ID = "com.apple.ScreenSharing"

// Not a public constant. Standard AppKit windows report it through Accessibility.
private let FULL_SCREEN_ATTRIBUTE = "AXFullScreen"
private let AX_TIMEOUT_SECONDS: Float = 0.25
// CGSession.h defines kCGSessionOnConsoleKey as a CFSTR macro, which Swift does not import.
private let SESSION_ON_CONSOLE_KEY = "kCGSSessionOnConsoleKey"
private let LOCK_FILE_NAME = "menubar-guard.lock"

private let POSITIONAL_EVENTS: [CGEventType] = [
    .mouseMoved,
    .leftMouseDown, .leftMouseUp, .leftMouseDragged,
    .rightMouseDown, .rightMouseUp, .rightMouseDragged,
    .otherMouseDown, .otherMouseUp, .otherMouseDragged,
]

let TAP_DISABLED = Notification.Name("menubar-guard.tap-disabled")
let DISPLAYS_CHANGED = Notification.Name("menubar-guard.displays-changed")

/// A value shared between threads. The unfair lock donates priority, so the
/// user-interactive tap thread never waits behind a lower-priority holder.
final class Locked<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        state = OSAllocatedUnfairLock(initialState: value)
    }

    func get() -> Value {
        state.withLock { $0 }
    }

    func set(_ newValue: Value) {
        state.withLock { $0 = newValue }
    }

    /// Changes the value in place, in one locked step, and returns what `body` returns.
    func update<Result: Sendable>(_ body: @Sendable (inout Value) -> Result) -> Result {
        state.withLock(body)
    }
}

/// Strips the tap keeps the pointer out of. The monitor publishes them. The
/// display callback, the signal handlers and every exit path clear them.
let activeBands = Locked<[TopBand]>([])

let tapDisables = Locked(TapDisables())

/// Seconds since boot. Never goes backward, unlike the wall clock.
func uptime() -> Double {
    ProcessInfo.processInfo.systemUptime
}

private func notifyMain(_ name: Notification.Name) {
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

// The callback runs on the tap thread for every pointer event while the tap
// is on, so it reads one locked value and does nothing else.
private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout:
        tapDisables.update { $0.byTimeout += 1 }
        notifyMain(TAP_DISABLED)
    case .tapDisabledByUserInput:
        tapDisables.update { $0.byUserInput += 1 }
        notifyMain(TAP_DISABLED)
    default:
        let isShiftDown = event.flags.contains(.maskShift)
        if let moved = adjustedLocation(event.location, isShiftDown: isShiftDown, bands: activeBands.get()) {
            event.location = moved
        }
    }
    return Unmanaged.passUnretained(event)
}

/// The HID event tap. It starts switched off, and the monitor switches it on
/// only while there are bands to enforce, so pointer events skip this process
/// the rest of the time.
@MainActor
final class EventTap {
    private let port: CFMachPort

    private init(port: CFMachPort) {
        self.port = port
    }

    /// Creates the tap and starts its thread, or returns nil when macOS refuses.
    static func create() -> EventTap? {
        let mask = POSITIONAL_EVENTS.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        ) else { return nil }
        CGEvent.tapEnable(tap: port, enable: false)
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return nil
        }
        TapThread(source: source).startAndWait()
        return EventTap(port: port)
    }

    var isValid: Bool { CFMachPortIsValid(port) }

    var isEnabled: Bool { CGEvent.tapIsEnabled(tap: port) }

    func setEnabled(_ isOn: Bool) {
        if isEnabled != isOn {
            CGEvent.tapEnable(tap: port, enable: isOn)
        }
    }
}

/// Runs the tap's run loop source on its own thread, so slow Accessibility
/// reads on the main thread never delay pointer events.
private final class TapThread: Thread, @unchecked Sendable {
    // Set before start() and never changed. Run loop sources are safe to use
    // from any thread.
    private let source: CFRunLoopSource
    private let ready = DispatchSemaphore(value: 0)

    init(source: CFRunLoopSource) {
        self.source = source
        super.init()
    }

    override func main() {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        ready.signal()
        CFRunLoopRun()
    }

    /// Starts the thread and returns once its run loop has the source.
    func startAndWait() {
        name = "menubar-guard.tap"
        qualityOfService = .userInteractive
        start()
        ready.wait()
    }
}

/// Uptime when the current display change began, or nil when none is under way.
let displayChangeStartedAt = Locked<Double?>(nil)
private let isDisplayChangePosted = Locked(false)

// macOS calls this once per display before a change and once per display after
// it. The bands are dropped at the first call, before the new layout is known,
// and the main thread is told once that the change is over.
private func displayReconfigured(
    display: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    activeBands.set([])
    if flags.contains(.beginConfigurationFlag) {
        let now = uptime()
        displayChangeStartedAt.update { startedAt in
            if startedAt == nil { startedAt = now }
        }
        return
    }
    displayChangeStartedAt.set(nil)
    let wasPosted = isDisplayChangePosted.update { isPosted in
        defer { isPosted = true }
        return isPosted
    }
    if !wasPosted {
        notifyMain(DISPLAYS_CHANGED)
    }
}

/// Call before acting on DISPLAYS_CHANGED, so the next change posts again.
func acknowledgeDisplayChange() {
    isDisplayChangePosted.set(false)
}

/// Returns false when macOS would not register the callback.
func watchDisplayChanges() -> Bool {
    CGDisplayRegisterReconfigurationCallback(displayReconfigured, nil) == .success
}

struct StartupError: Error, CustomStringConvertible {
    let description: String
}

private func errnoText(_ code: Int32) -> String {
    String(cString: strerror(code))
}

/// Holds an exclusive lock for the life of the process, so two copies never
/// run at once. Waits while another copy holds it.
func lockSingleInstance(onWait: () -> Void) throws {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(LOCK_FILE_NAME)
    let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    guard fd >= 0 else {
        throw StartupError(description: "could not open the single-instance lock: \(errnoText(errno))")
    }
    if flock(fd, LOCK_EX | LOCK_NB) == 0 { return }
    let code = errno
    guard code == EWOULDBLOCK else {
        throw StartupError(description: "could not take the single-instance lock: \(errnoText(code))")
    }
    onWait()
    guard flock(fd, LOCK_EX) == 0 else {
        throw StartupError(description: "could not wait for the single-instance lock: \(errnoText(errno))")
    }
}

func isAccessibilityTrusted() -> Bool {
    AXIsProcessTrusted()
}

/// Shows the system permission prompt if the permission is missing.
func requestAccessibility() -> Bool {
    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
}

/// Sets the Accessibility timeout for every element this process reads.
/// A timeout set on one element does not apply to the elements it returns.
func configureAccessibilityTimeout() -> Bool {
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), AX_TIMEOUT_SECONDS) == .success
}

/// Whether this login session is the one on screen. When macOS gives no
/// answer, assumes it is, because launchd starts the agent only in a GUI session.
func isSessionOnConsole() -> Bool {
    guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
    return info[SESSION_ON_CONSOLE_KEY] as? Bool ?? true
}

/// Bounds of every active display, in global display coordinates.
func activeDisplayBounds() -> [CGRect] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
}

private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value
}

private func axValue<T: BitwiseCopyable>(_ element: AXUIElement, _ attribute: CFString, _ type: AXValueType, empty: T) -> T? {
    guard let ref = copyAttribute(element, attribute), CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
    var result = empty
    // The type check above makes this cast safe.
    guard AXValueGetValue(ref as! AXValue, type, &result) else { return nil }
    return result
}

private func windowInfo(_ window: AXUIElement) -> WindowInfo? {
    guard let origin = axValue(window, kAXPositionAttribute as CFString, .cgPoint, empty: CGPoint.zero),
          let size = axValue(window, kAXSizeAttribute as CFString, .cgSize, empty: CGSize.zero) else { return nil }
    let frame = CGRect(origin: origin, size: size)
    guard isUsable(frame) else { return nil }
    let isFullScreen = copyAttribute(window, FULL_SCREEN_ATTRIBUTE as CFString) as? Bool
    return WindowInfo(frame: frame, isFullScreen: isFullScreen)
}

/// The app's windows, or nil when Accessibility could not list them.
func accessibilityWindows(pid: pid_t) -> [WindowInfo]? {
    let app = AXUIElementCreateApplication(pid)
    guard let windows = copyAttribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement] else { return nil }
    return windows.compactMap(windowInfo)
}

/// What one look found, with a summary for the log.
struct Observation {
    let sighting: Sighting
    let detail: String
}

/// Reads Screen Sharing's windows, whether or not it is in front.
func observeScreenSharing(pid: pid_t, margin: CGFloat) -> Observation {
    guard let windows = accessibilityWindows(pid: pid), !windows.isEmpty else {
        return Observation(sighting: .unreadable, detail: "windows=unreadable")
    }
    let bands = bandsForFullScreen(windows: windows, displays: activeDisplayBounds(), margin: margin)
    return Observation(sighting: .windows(bands), detail: describe(windows: windows))
}

/// Looks at the front app. Other apps are logged only as `other`, so the log
/// never records which apps you use.
@MainActor
func observeFront(margin: CGFloat) -> Observation {
    guard let front = NSWorkspace.shared.frontmostApplication else {
        return Observation(sighting: .notFront, detail: "front=none")
    }
    guard front.bundleIdentifier == SCREEN_SHARING_BUNDLE_ID else {
        return Observation(sighting: .notFront, detail: "front=other")
    }
    let seen = observeScreenSharing(pid: front.processIdentifier, margin: margin)
    return Observation(sighting: seen.sighting, detail: "front=screen-sharing \(seen.detail)")
}

func runningScreenSharing() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: SCREEN_SHARING_BUNDLE_ID).first
}
