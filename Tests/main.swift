import CoreGraphics
import Foundation

private var failures = 0
private var passes = 0

@MainActor
private func check(_ condition: Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
    if condition {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(name) (\(file):\(line))")
    }
}

private let MAIN = CGRect(x: 0, y: 0, width: 1600, height: 1000)
private let RIGHT = CGRect(x: 1600, y: 0, width: 1920, height: 1080)
private let ABOVE = CGRect(x: 0, y: -1080, width: 1920, height: 1080)

private func band(_ display: CGRect, margin: CGFloat = 2) -> TopBand {
    TopBand(minX: display.minX, maxX: display.maxX, top: display.minY, margin: margin)
}

// Clamping inside one band.
do {
    let main = band(MAIN)
    check(main.clamped(CGPoint(x: 100, y: 0)) == CGPoint(x: 100, y: 2), "top edge moves to margin")
    check(main.clamped(CGPoint(x: 100, y: 1.5)) == CGPoint(x: 100, y: 2), "fractional point in strip moves")
    check(main.clamped(CGPoint(x: 100, y: 2)) == nil, "point at margin is left alone")
    check(main.clamped(CGPoint(x: 100, y: 400)) == nil, "point lower on display is left alone")
    check(main.clamped(CGPoint(x: 0, y: 0)) == CGPoint(x: 0, y: 2), "left edge belongs to the display")
    check(main.clamped(CGPoint(x: 1600, y: 0)) == nil, "right edge belongs to the next display")
    check(main.clamped(CGPoint(x: -1, y: 0)) == nil, "point left of display is left alone")
    check(main.clamped(CGPoint(x: 100, y: -1)) == nil, "point on a display above is left alone")
}

// Clamping across displays.
do {
    let bands = [band(RIGHT)]
    check(clamp(CGPoint(x: 100, y: 0), bands: bands) == nil, "display without a band is left alone")
    check(clamp(CGPoint(x: 1700, y: 0), bands: bands) == CGPoint(x: 1700, y: 2), "banded display clamps")
    check(clamp(CGPoint(x: 100, y: 0), bands: []) == nil, "no bands means no clamp")
    check(clamp(CGPoint(x: 100, y: -1080), bands: [band(ABOVE)]) == CGPoint(x: 100, y: -1078), "display with negative origin clamps")
}

// The tap's decision, including Shift.
do {
    let bands = [band(MAIN, margin: 8)]
    let top = CGPoint(x: 100, y: 0)
    check(adjustedLocation(top, isShiftDown: false, bands: bands) == CGPoint(x: 100, y: 8), "pointer at the top is moved")
    check(adjustedLocation(top, isShiftDown: true, bands: bands) == nil, "Shift leaves the pointer alone")
    check(adjustedLocation(top, isShiftDown: false, bands: []) == nil, "no bands leaves the pointer alone")
    check(adjustedLocation(CGPoint(x: 100, y: 8), isShiftDown: false, bands: bands) == nil, "pointer below the strip is left alone")
}

// Only real screen edges get a band.
do {
    check(topBands(for: MAIN, displays: [MAIN], margin: 2) == [band(MAIN)], "lone display gets its whole top edge")
    check(topBands(for: MAIN, displays: [MAIN, RIGHT], margin: 2) == [band(MAIN)], "display beside it does not change the edge")
    check(topBands(for: MAIN, displays: [MAIN, ABOVE], margin: 2).isEmpty, "display fully above leaves the edge open")

    let narrowAbove = CGRect(x: 400, y: -600, width: 600, height: 600)
    let split = topBands(for: MAIN, displays: [MAIN, narrowAbove], margin: 2)
    check(split == [
        TopBand(minX: 0, maxX: 400, top: 0, margin: 2),
        TopBand(minX: 1000, maxX: 1600, top: 0, margin: 2),
    ], "partly covered edge keeps the open parts")
    check(clamp(CGPoint(x: 500, y: 0), bands: split) == nil, "pointer can move up into the display above")
    check(clamp(CGPoint(x: 100, y: 0), bands: split) == CGPoint(x: 100, y: 2), "open part still clamps")

    let leftOverhang = CGRect(x: -300, y: -500, width: 500, height: 500)
    check(topBands(for: MAIN, displays: [MAIN, leftOverhang], margin: 2) == [
        TopBand(minX: 200, maxX: 1600, top: 0, margin: 2),
    ], "display overhanging the left side covers only its overlap")

    let gapAbove = CGRect(x: 0, y: -1100, width: 1600, height: 1000)
    check(topBands(for: MAIN, displays: [MAIN, gapAbove], margin: 2) == [band(MAIN)], "display that does not touch the edge is ignored")

    let first = CGRect(x: 200, y: -500, width: 600, height: 500)
    let overlapping = CGRect(x: 500, y: -400, width: 500, height: 400)
    check(topBands(for: MAIN, displays: [MAIN, overlapping, first], margin: 2) == [
        TopBand(minX: 0, maxX: 200, top: 0, margin: 2),
        TopBand(minX: 1000, maxX: 1600, top: 0, margin: 2),
    ], "overlapping displays above merge into one open span")

    let nearlyTouching = CGRect(x: 0, y: -1000.5, width: 1600, height: 1000)
    check(topBands(for: MAIN, displays: [MAIN, nearlyTouching], margin: 2).isEmpty, "display within the tolerance counts as touching")
}

// Frame sanity.
do {
    check(isUsable(CGRect(x: 0, y: 0, width: 800, height: 600)), "normal frame is usable")
    check(!isUsable(CGRect(x: 0, y: 0, width: 1, height: 600)), "one-point-wide frame is not usable")
    check(!isUsable(CGRect(x: CGFloat.nan, y: 0, width: 800, height: 600)), "NaN origin is not usable")
    check(!isUsable(CGRect(x: 0, y: CGFloat.infinity, width: 800, height: 600)), "infinite origin is not usable")
    check(!isUsable(CGRect(x: 2_000_000, y: 0, width: 800, height: 600)), "far-away origin is not usable")
}

// Filling a display.
do {
    check(fills(MAIN, with: MAIN), "exact frame fills")
    check(fills(MAIN, with: MAIN.offsetBy(dx: 1, dy: 0)), "frame off by the tolerance fills")
    check(!fills(MAIN, with: MAIN.offsetBy(dx: 1.5, dy: 0)), "frame off by more than the tolerance does not fill")
    check(!fills(MAIN, with: MAIN.insetBy(dx: 0, dy: 2)), "frame short at top and bottom does not fill")
}

// Full-screen detection.
do {
    let fullOnMain = WindowInfo(frame: MAIN, isFullScreen: true)
    check(fullScreenDisplays(windows: [fullOnMain], displays: [MAIN, RIGHT]) == [MAIN], "full-screen window picks its display")

    let fullOnRight = WindowInfo(frame: RIGHT.insetBy(dx: 40, dy: 40), isFullScreen: true)
    check(fullScreenDisplays(windows: [fullOnRight], displays: [MAIN, RIGHT]) == [RIGHT], "mid-animation frame uses its center")
    check(fullScreenDisplays(windows: [fullOnMain, fullOnRight], displays: [MAIN, RIGHT]) == [MAIN, RIGHT], "two full-screen windows pick both displays")

    let windowed = WindowInfo(frame: MAIN, isFullScreen: false)
    check(fullScreenDisplays(windows: [windowed], displays: [MAIN]).isEmpty, "window that says not full screen is ignored")
    check(fullScreenDisplays(windows: [windowed, fullOnRight], displays: [MAIN, RIGHT]) == [RIGHT], "only the full-screen window counts")

    let unknownFilling = WindowInfo(frame: MAIN, isFullScreen: nil)
    check(fullScreenDisplays(windows: [unknownFilling], displays: [MAIN]) == [MAIN], "unknown flag counts when frame fills display")

    let unknownSmall = WindowInfo(frame: CGRect(x: 100, y: 100, width: 800, height: 500), isFullScreen: nil)
    check(fullScreenDisplays(windows: [unknownSmall], displays: [MAIN]).isEmpty, "unknown flag with small frame is ignored")

    check(fullScreenDisplays(windows: [], displays: [MAIN]).isEmpty, "no windows means no displays")
    check(bandsForFullScreen(windows: [fullOnMain], displays: [MAIN, ABOVE], margin: 8).isEmpty, "full screen under another display gets no band")
    check(bandsForFullScreen(windows: [fullOnRight], displays: [MAIN, RIGHT], margin: 8) == [band(RIGHT, margin: 8)], "full screen on the right display bands that display")
}

// Holding through unreadable moments.
do {
    let seen = [band(MAIN)]
    var hold = Hold(releaseAfterMisses: 3)
    check(hold.update(.windows(seen)), "first sighting turns on")
    check(!hold.update(.unreadable), "first unreadable look keeps band")
    check(!hold.update(.unreadable), "second unreadable look keeps band")
    check(hold.update(.unreadable), "third unreadable look releases")
    check(hold.bands.isEmpty, "released hold is empty")

    var switched = Hold(releaseAfterMisses: 3)
    _ = switched.update(.windows(seen))
    check(switched.update(.notFront), "other app in front releases at once")

    var windowed = Hold(releaseAfterMisses: 3)
    _ = windowed.update(.windows(seen))
    check(windowed.update(.windows([])), "readable look with no full-screen window releases at once")

    var recovered = Hold(releaseAfterMisses: 3)
    _ = recovered.update(.windows(seen))
    _ = recovered.update(.unreadable)
    _ = recovered.update(.windows(seen))
    _ = recovered.update(.unreadable)
    _ = recovered.update(.unreadable)
    check(recovered.bands == seen, "a sighting resets the miss count")

    var idle = Hold(releaseAfterMisses: 3)
    check(!idle.update(.unreadable), "unreadable look with nothing held changes nothing")
    check(!idle.update(.notFront), "other app in front with nothing held changes nothing")
}

// Tap timeouts.
do {
    var wire = TripWire(limit: 3, window: 60)
    check(!wire.record(1, at: 0), "one timeout does not trip")
    check(!wire.record(1, at: 10), "two timeouts do not trip")
    check(wire.record(1, at: 20), "third timeout in a minute trips")

    var spread = TripWire(limit: 3, window: 60)
    _ = spread.record(1, at: 0)
    _ = spread.record(1, at: 50)
    check(!spread.record(1, at: 100), "timeouts spread over two minutes do not trip")
    check(!spread.record(0, at: 200), "quiet time clears old timeouts")

    var boundary = TripWire(limit: 3, window: 60)
    _ = boundary.record(1, at: 0)
    _ = boundary.record(1, at: 30)
    check(boundary.record(1, at: 60), "timeout exactly at the window edge still counts")

    var burst = TripWire(limit: 3, window: 60)
    check(burst.record(3, at: 5), "three at once trips")
}

// Tap health.
do {
    var health = TapHealth(timeoutLimit: 3, window: 60)
    check(health.check(TapDisables(), at: 0) == TapReport(), "no disables reports nothing")

    let first = health.check(TapDisables(byTimeout: 1, byUserInput: 0), at: 1)
    check(first.newTimeouts == 1 && first.isChanged && !first.isTripped, "one timeout is reported")

    let user = health.check(TapDisables(byTimeout: 1, byUserInput: 1), at: 2)
    check(user.newUserInputs == 1 && user.newTimeouts == 0, "user-input disable is reported on its own")

    let same = health.check(TapDisables(byTimeout: 1, byUserInput: 1), at: 3)
    check(!same.isChanged, "unchanged totals report nothing new")

    let tripped = health.check(TapDisables(byTimeout: 3, byUserInput: 1), at: 4)
    check(tripped.newTimeouts == 2 && tripped.isTripped, "third timeout in a minute trips")
    check(health.totals == TapDisables(byTimeout: 3, byUserInput: 1), "totals follow the latest counts")
}

// Reasons to stay off.
do {
    check(offReason(isTrusted: true, isSessionActive: true, isDisplayChanging: false) == nil, "all clear allows the guard")
    check(offReason(isTrusted: false, isSessionActive: true, isDisplayChanging: false) == "accessibility=revoked", "missing permission keeps it off")
    check(offReason(isTrusted: true, isSessionActive: false, isDisplayChanging: false) == "session=inactive", "inactive session keeps it off")
    check(offReason(isTrusted: true, isSessionActive: true, isDisplayChanging: true) == "displays=changing", "display change keeps it off")
    check(offReason(isTrusted: false, isSessionActive: false, isDisplayChanging: true) == "accessibility=revoked", "permission is reported first")

    check(!isDisplayChanging(startedAt: nil, now: 10, timeout: 5), "no change under way")
    check(isDisplayChanging(startedAt: 10, now: 12, timeout: 5), "recent change is under way")
    check(!isDisplayChanging(startedAt: 10, now: 15, timeout: 5), "change without an end stops counting after the timeout")
}

// Log formats documented in docs/reading-logs.md.
do {
    check(describe(MAIN) == "1600x1000@0,0", "display format")
    check(describe(ABOVE) == "1920x1080@0,-1080", "negative origin format")
    check(describe(TopBand(minX: 0, maxX: 1920, top: 0, margin: 8)) == "x=0..1920,y=0", "band format")
    check(describe(WindowInfo(frame: MAIN, isFullScreen: true)) == "1600x1000@0,0:full", "full-screen window format")
    check(describe(WindowInfo(frame: MAIN, isFullScreen: false)) == "1600x1000@0,0:window", "normal window format")
    check(describe(WindowInfo(frame: MAIN, isFullScreen: nil)) == "1600x1000@0,0:unknown", "unknown window format")
    check(describe(windows: [WindowInfo(frame: MAIN, isFullScreen: true), WindowInfo(frame: RIGHT, isFullScreen: false)])
        == "windows=[1600x1000@0,0:full 1920x1080@1600,0:window]", "window list format")
    check(describe(margin: 8) == "8", "whole margin has no decimal point")
    check(describe(margin: 7.5) == "7.5", "fractional margin keeps its decimal")
    check(describeState(bands: [], margin: 8) == "state=off", "off state format")
    check(describeState(bands: [band(MAIN, margin: 8), band(RIGHT, margin: 8)], margin: 8)
        == "state=on bands=x=0..1600,y=0;x=1600..3520,y=0 margin=8", "on state format")
}

// Options.
do {
    check((try? parseOptions([])) == Options(), "no arguments gives defaults")
    check((try? parseOptions(["--margin", "8"]))?.margin == 8, "margin is read")
    check((try? parseOptions(["--margin", "1"]))?.margin == 1, "lowest margin is accepted")
    check((try? parseOptions(["--margin", "40"]))?.margin == 40, "highest margin is accepted")
    check((try? parseOptions(["--margin", "7.5"]))?.margin == 7.5, "fractional margin is accepted")
    check((try? parseOptions(["--check", "--verbose"])).map { $0.isCheck && $0.isVerbose } == true, "flags are read")
    check((try? parseOptions(["--version"]))?.isVersion == true, "version flag is read")
    check((try? parseOptions(["-h"]))?.isHelp == true, "short help flag is read")
    check((try? parseOptions(["--help"]))?.isHelp == true, "long help flag is read")
    check(throwsError(["--margin"]) == .missingValue("--margin"), "margin without value fails")
    check(throwsError(["--margin", "0"]) == .badMargin("0"), "margin below range fails")
    check(throwsError(["--margin", "41"]) == .badMargin("41"), "margin above range fails")
    check(throwsError(["--margin", "abc"]) == .badMargin("abc"), "non-number margin fails")
    check(throwsError(["--margin", "0x10"]) == .badMargin("0x10"), "hex margin fails")
    check(throwsError(["--margin", "1e1"]) == .badMargin("1e1"), "exponent margin fails")
    check(throwsError(["--margin", "-5"]) == .badMargin("-5"), "negative margin fails")
    check(throwsError(["--margin", "1.2.3"]) == .badMargin("1.2.3"), "margin with two points fails")
    check(throwsError(["--margin", ""]) == .badMargin(""), "empty margin fails")
    check(throwsError(["--margin", "８"]) == .badMargin("８"), "non-ASCII digit fails")
    check(throwsError(["--bogus"]) == .unknown("--bogus"), "unknown option fails")
    check(throwsError(["--margin", "8", "--bogus"]) == .unknown("--bogus"), "bad option after a good one fails")
}

private func throwsError(_ args: [String]) -> OptionsError? {
    do {
        _ = try parseOptions(args)
        return nil
    } catch let error as OptionsError {
        return error
    } catch {
        return nil
    }
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
