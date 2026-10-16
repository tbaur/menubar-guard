import CoreGraphics

/// Frames this far from a display edge still count as touching it.
let FILL_TOLERANCE: CGFloat = 1

/// Frames with a coordinate beyond this are treated as garbage.
private let MAX_COORDINATE: CGFloat = 1_000_000

/// A strip along the top edge of a display that the pointer is kept out of.
/// Coordinates are global display coordinates: origin at the top left of the
/// main display, Y growing downward. Event locations and Accessibility window
/// frames use the same space.
struct TopBand: Equatable, Sendable {
    let minX: CGFloat
    let maxX: CGFloat
    let top: CGFloat
    let margin: CGFloat

    /// The point moved to just below the strip, or nil when the point is not in it.
    func clamped(_ point: CGPoint) -> CGPoint? {
        let isInSpan = point.x >= minX && point.x < maxX
        let isInStrip = point.y >= top && point.y < top + margin
        guard isInSpan && isInStrip else { return nil }
        return CGPoint(x: point.x, y: top + margin)
    }
}

/// Bands for the parts of `display`'s top edge that are a real screen edge.
/// Where another display sits directly above, the pointer can keep moving up,
/// so that part of the edge is left open and the pointer is never trapped.
func topBands(for display: CGRect, displays: [CGRect], margin: CGFloat) -> [TopBand] {
    let covered = displays
        .filter { other in
            other != display
                && abs(other.maxY - display.minY) <= FILL_TOLERANCE
                && other.minX < display.maxX && other.maxX > display.minX
        }
        .map { (max($0.minX, display.minX), min($0.maxX, display.maxX)) }
        .sorted { $0.0 < $1.0 }
    var bands: [TopBand] = []
    var start = display.minX
    for (coverStart, coverEnd) in covered {
        if coverStart > start {
            bands.append(TopBand(minX: start, maxX: coverStart, top: display.minY, margin: margin))
        }
        start = max(start, coverEnd)
    }
    if start < display.maxX {
        bands.append(TopBand(minX: start, maxX: display.maxX, top: display.minY, margin: margin))
    }
    return bands
}

/// The first band's clamp of `point`, or nil when no band applies.
func clamp(_ point: CGPoint, bands: [TopBand]) -> CGPoint? {
    for band in bands {
        if let moved = band.clamped(point) {
            return moved
        }
    }
    return nil
}

/// Where the event tap should move a pointer event, or nil to leave it alone.
/// Holding Shift always leaves it alone.
func adjustedLocation(_ point: CGPoint, isShiftDown: Bool, bands: [TopBand]) -> CGPoint? {
    guard !isShiftDown, !bands.isEmpty else { return nil }
    return clamp(point, bands: bands)
}

/// One window as read through Accessibility.
/// `isFullScreen` is nil when the app does not report the attribute.
struct WindowInfo: Equatable, Sendable {
    let frame: CGRect
    let isFullScreen: Bool?
}

/// True when a frame read from another process is finite, of real size, and
/// within any plausible display arrangement.
func isUsable(_ frame: CGRect) -> Bool {
    let values = [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]
    guard values.allSatisfy({ $0.isFinite && abs($0) < MAX_COORDINATE }) else { return false }
    return frame.width > 1 && frame.height > 1
}

/// True when `frame` matches `display` on every edge.
func fills(_ display: CGRect, with frame: CGRect) -> Bool {
    abs(frame.minX - display.minX) <= FILL_TOLERANCE
        && abs(frame.minY - display.minY) <= FILL_TOLERANCE
        && abs(frame.maxX - display.maxX) <= FILL_TOLERANCE
        && abs(frame.maxY - display.maxY) <= FILL_TOLERANCE
}

/// The displays that hold a full-screen window.
/// A window that reports full screen counts for the display under its center.
/// A window that does not report it counts only when it fills a display exactly.
func fullScreenDisplays(windows: [WindowInfo], displays: [CGRect]) -> [CGRect] {
    displays.filter { display in
        windows.contains { window in
            switch window.isFullScreen {
            case .some(true):
                return display.contains(CGPoint(x: window.frame.midX, y: window.frame.midY))
            case .some(false):
                return false
            case .none:
                return fills(display, with: window.frame)
            }
        }
    }
}

/// Bands for every display that holds a full-screen window.
func bandsForFullScreen(windows: [WindowInfo], displays: [CGRect], margin: CGFloat) -> [TopBand] {
    fullScreenDisplays(windows: windows, displays: displays)
        .flatMap { topBands(for: $0, displays: displays, margin: margin) }
}
