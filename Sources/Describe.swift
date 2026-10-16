import CoreGraphics
import Foundation

// These strings appear in the log. docs/reading-logs.md documents them, so change both together.

/// `WIDTHxHEIGHT@X,Y`, in whole points.
func describe(_ rect: CGRect) -> String {
    "\(Int(rect.width))x\(Int(rect.height))@\(Int(rect.minX)),\(Int(rect.minY))"
}

/// `x=MIN..MAX,y=TOP`, in whole points.
func describe(_ band: TopBand) -> String {
    "x=\(Int(band.minX))..\(Int(band.maxX)),y=\(Int(band.top))"
}

/// A frame followed by `:full`, `:window`, or `:unknown` when the app does not
/// report full-screen state.
func describe(_ window: WindowInfo) -> String {
    let flag: String
    switch window.isFullScreen {
    case .some(true): flag = "full"
    case .some(false): flag = "window"
    case .none: flag = "unknown"
    }
    return "\(describe(window.frame)):\(flag)"
}

/// A margin without a trailing `.0` for whole numbers: `8`, `7.5`.
func describe(margin: CGFloat) -> String {
    String(format: "%g", Double(margin))
}

/// The `windows=[...]` part of a state line.
func describe(windows: [WindowInfo]) -> String {
    "windows=[\(windows.map { describe($0) }.joined(separator: " "))]"
}

/// The state part of a log line: `state=off`, or `state=on bands=... margin=...`.
func describeState(bands: [TopBand], margin: CGFloat) -> String {
    if bands.isEmpty { return "state=off" }
    let text = bands.map { describe($0) }.joined(separator: ";")
    return "state=on bands=\(text) margin=\(describe(margin: margin))"
}
