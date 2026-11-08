import Foundation

/// Viewability rule shared by all CrossIndie SDKs: a banner counts as seen only
/// while it has a non-zero size and at least half of it is on screen.
public enum Visibility {
    public static let minFraction: Double = 0.5

    public static func fraction(visibleWidth: Double, visibleHeight: Double,
                                width: Double, height: Double) -> Double {
        guard width > 0, height > 0, visibleWidth > 0, visibleHeight > 0 else { return 0 }
        return (min(visibleWidth, width) * min(visibleHeight, height)) / (width * height)
    }

    public static func isViewable(visibleWidth: Double, visibleHeight: Double,
                                  width: Double, height: Double) -> Bool {
        fraction(visibleWidth: visibleWidth, visibleHeight: visibleHeight,
                 width: width, height: height) >= minFraction
    }
}

/// The banner's fetch / impression / rotation state machine. Pure and
/// clock-injected (times in ms) so it can be unit-tested; the view drives it
/// from a 250 ms main-thread timer.
///
/// Rules (same as the web and Android SDKs, and the backend):
///  - An impression is reported once, after the banner has been *continuously*
///    viewable for the ad's `min_display_ms` (server default 1.5 s).
///  - Tracking tokens expire 60 s after fetch, so an ad not counted yet is
///    re-fetched once it is ~55 s old (only while viewable).
///  - After an impression the slot rotates every `refreshMs` (0 = never),
///    again only while viewable: hidden slots make no requests.
///  - No fill: retry after 60 s. Errors: exponential backoff 15 s ... 5 min.
public final class BannerState {
    public enum Result: Equatable {
        case loaded(CrossIndieAd)
        case noFill
        case error
    }

    public static let defaultRefreshSeconds = 30
    public static let minRefreshSeconds = 15
    public static let tokenRefreshMs: Int64 = 55_000
    public static let noFillRetryMs: Int64 = 60_000
    public static let maxBackoffMs: Int64 = 300_000

    public private(set) var refreshMs: Int64
    public private(set) var ad: CrossIndieAd?
    public private(set) var loading = false
    public private(set) var impressionSent = false
    public private(set) var failures = 0

    private let tokenTtlMs: Int64
    private var fetchedAt: Int64 = -1
    private var nextFetchAt: Int64 = 0
    private var rendered = false
    private var visibleSince: Int64 = -1
    private var clickSent = false

    public init(refreshSeconds: Int = BannerState.defaultRefreshSeconds,
                tokenTtlMs: Int64 = BannerState.tokenRefreshMs) {
        self.refreshMs = BannerState.refreshMs(for: refreshSeconds)
        self.tokenTtlMs = tokenTtlMs
    }

    public static func refreshMs(for seconds: Int) -> Int64 {
        seconds <= 0 ? 0 : Int64(max(seconds, minRefreshSeconds)) * 1000
    }

    public static func backoffMs(failures: Int) -> Int64 {
        let n = min(max(failures - 1, 0), 10)
        return min(Int64(15_000) << Int64(n), maxBackoffMs)
    }

    public func setRefreshSeconds(_ seconds: Int) {
        refreshMs = BannerState.refreshMs(for: seconds)
    }

    /// `onScreen` = in a window and not hidden; `viewable` = >= 50 % visible.
    public func shouldFetch(now: Int64, onScreen: Bool, viewable: Bool) -> Bool {
        if loading || !onScreen || now < nextFetchAt { return false }
        guard ad != nil else { return true } // first load, or retry after no fill / error
        if !viewable { return false }
        if impressionSent { return refreshMs > 0 && now - fetchedAt >= refreshMs }
        return isStale(now: now)
    }

    public func onFetchStarted() { loading = true }

    public func onFetchResult(now: Int64, _ result: Result) {
        loading = false
        switch result {
        case .loaded(let newAd):
            failures = 0
            nextFetchAt = 0
            ad = newAd
            fetchedAt = now
            rendered = false
            visibleSince = -1
            impressionSent = false
            clickSent = false
        case .noFill:
            failures = 0
            nextFetchAt = now + BannerState.noFillRetryMs
        case .error:
            failures += 1
            nextFetchAt = now + BannerState.backoffMs(failures: failures)
        }
    }

    /// The creative is on screen (image decoded, or failed): the dwell clock may start.
    public func onRendered() { rendered = true }

    /// Advance the dwell clock; returns true exactly once, when the impression is due.
    public func tick(now: Int64, viewable: Bool) -> Bool {
        guard let current = ad, rendered, !impressionSent else { return false }
        if !viewable || isStale(now: now) {
            visibleSince = -1
            return false
        }
        if visibleSince < 0 { visibleSince = now }
        if now - visibleSince >= current.minDisplayMs && now - fetchedAt >= current.minDisplayMs {
            impressionSent = true
            return true
        }
        return false
    }

    /// A click should be reported (once per ad, and only while its token is valid).
    public func consumeClick(now: Int64) -> Bool {
        if ad == nil || clickSent || isStale(now: now) { return false }
        clickSent = true
        return true
    }

    public func isStale(now: Int64) -> Bool {
        ad != nil && now - fetchedAt >= tokenTtlMs
    }

    public func reset() {
        ad = nil
        loading = false
        failures = 0
        fetchedAt = -1
        nextFetchAt = 0
        rendered = false
        visibleSince = -1
        impressionSent = false
        clickSent = false
    }
}
