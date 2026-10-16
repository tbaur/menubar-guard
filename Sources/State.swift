/// What one look at Screen Sharing found.
enum Sighting: Equatable, Sendable {
    /// Another app, or no app, is in front.
    case notFront
    /// Screen Sharing is in front, but its windows could not be read, or it
    /// listed none. Both happen for a moment during the full-screen animation.
    case unreadable
    /// Screen Sharing is in front and its windows were read. The bands are
    /// empty when no window is full screen.
    case windows([TopBand])
}

/// Keeps bands in place through brief unreadable moments, and drops them at
/// once when a read shows no full-screen window or another app is in front.
struct Hold: Sendable {
    let releaseAfterMisses: Int
    private(set) var bands: [TopBand] = []
    private var misses = 0

    init(releaseAfterMisses: Int) {
        self.releaseAfterMisses = releaseAfterMisses
    }

    /// Applies one sighting. Returns true when the held bands changed.
    mutating func update(_ sighting: Sighting) -> Bool {
        let before = bands
        switch sighting {
        case .notFront:
            bands = []
            misses = 0
        case .windows(let observed):
            bands = observed
            misses = 0
        case .unreadable:
            guard !bands.isEmpty else { break }
            misses += 1
            if misses >= releaseAfterMisses {
                bands = []
                misses = 0
            }
        }
        return bands != before
    }
}

/// Trips when `limit` events land within `window` seconds.
/// `now` must come from a clock that never goes backward.
struct TripWire: Sendable {
    let limit: Int
    let window: Double
    private var times: [Double] = []

    init(limit: Int, window: Double) {
        self.limit = limit
        self.window = window
    }

    /// Records `count` events at time `now`. Returns true when the wire trips.
    mutating func record(_ count: Int, at now: Double) -> Bool {
        if count > 0 {
            times.append(contentsOf: repeatElement(now, count: count))
        }
        times.removeAll { now - $0 > window }
        return times.count >= limit
    }
}

/// How often macOS has switched the tap off since start.
struct TapDisables: Equatable, Sendable {
    var byTimeout = 0
    var byUserInput = 0
}

/// What changed in the tap's health since the last check.
struct TapReport: Equatable, Sendable {
    var newTimeouts = 0
    var newUserInputs = 0
    var isTripped = false

    var isChanged: Bool { newTimeouts > 0 || newUserInputs > 0 }
}

/// Turns running totals of tap disables into per-check news, and trips when
/// timeouts come too often.
struct TapHealth: Sendable {
    private var wire: TripWire
    private(set) var totals = TapDisables()

    init(timeoutLimit: Int, window: Double) {
        wire = TripWire(limit: timeoutLimit, window: window)
    }

    mutating func check(_ current: TapDisables, at now: Double) -> TapReport {
        var report = TapReport()
        report.newTimeouts = max(0, current.byTimeout - totals.byTimeout)
        report.newUserInputs = max(0, current.byUserInput - totals.byUserInput)
        totals = current
        report.isTripped = wire.record(report.newTimeouts, at: now)
        return report
    }
}

/// Why the guard must stay off whatever Screen Sharing shows, or nil.
func offReason(isTrusted: Bool, isSessionActive: Bool, isDisplayChanging: Bool) -> String? {
    if !isTrusted { return "accessibility=revoked" }
    if !isSessionActive { return "session=inactive" }
    if isDisplayChanging { return "displays=changing" }
    return nil
}

/// True while a display change that began at `startedAt` is still under way.
/// A change that never reports its end stops counting after `timeout` seconds.
func isDisplayChanging(startedAt: Double?, now: Double, timeout: Double) -> Bool {
    guard let startedAt else { return false }
    return now - startedAt < timeout
}
