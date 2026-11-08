package com.crossindie.sdk

/**
 * Viewability rule shared by all CrossIndie SDKs: a banner counts as seen only
 * while it has a non-zero size and at least half of it is on screen.
 */
object Visibility {
    const val MIN_FRACTION = 0.5f

    /** Fraction of a [width]x[height] view that is visible, given its visible-rect size. */
    @JvmStatic
    fun fraction(visibleWidth: Int, visibleHeight: Int, width: Int, height: Int): Float {
        if (width <= 0 || height <= 0 || visibleWidth <= 0 || visibleHeight <= 0) return 0f
        val vis = visibleWidth.toLong().coerceAtMost(width.toLong()) *
            visibleHeight.toLong().coerceAtMost(height.toLong())
        return (vis.toDouble() / (width.toLong() * height.toLong()).toDouble()).toFloat()
    }

    @JvmStatic
    fun isViewable(visibleWidth: Int, visibleHeight: Int, width: Int, height: Int): Boolean =
        fraction(visibleWidth, visibleHeight, width, height) >= MIN_FRACTION
}

/**
 * The banner's fetch / impression / rotation state machine. Pure and
 * clock-injected (all times in ms) so it can be unit-tested; the view drives it
 * from a 250 ms main-thread tick.
 *
 * Rules (mirroring the web SDK and the backend):
 *  - An impression is reported once, after the banner has been *continuously*
 *    viewable for the ad's `min_display_ms` (server default 1.5 s). Going out
 *    of view resets the dwell timer.
 *  - Tracking tokens expire 60 s after fetch, so an ad that has not been
 *    counted yet is re-fetched once it is ~55 s old (only while viewable).
 *  - After an impression the slot rotates to a new ad every [refreshMs]
 *    (0 = never), again only while viewable - hidden slots make no requests.
 *  - No fill: retry after 60 s. Errors: exponential backoff 15 s .. 5 min.
 */
class BannerState(
    refreshSeconds: Int = DEFAULT_REFRESH_SECONDS,
    private val tokenTtlMs: Long = TOKEN_REFRESH_MS,
) {
    sealed class Result {
        data class Loaded(val ad: Ad) : Result()
        object NoFill : Result()
        object Error : Result()
    }

    var refreshMs: Long = refreshMsFor(refreshSeconds)
        private set

    var ad: Ad? = null
        private set
    var loading = false
        private set
    var impressionSent = false
        private set
    var failures = 0
        private set

    private var fetchedAt = -1L
    private var nextFetchAt = 0L
    private var rendered = false
    private var visibleSince = -1L
    private var clickSent = false

    fun setRefreshSeconds(seconds: Int) {
        refreshMs = refreshMsFor(seconds)
    }

    /** Whether a fetch should start now. [onScreen] = attached and shown; [viewable] = >= 50% visible. */
    fun shouldFetch(now: Long, onScreen: Boolean, viewable: Boolean): Boolean {
        if (loading || !onScreen || now < nextFetchAt) return false
        val current = ad ?: return true // first load (or retry after no fill / error)
        if (!viewable) return false
        if (impressionSent) return refreshMs > 0 && now - fetchedAt >= refreshMs
        return isStale(now) // token about to expire before it was counted
    }

    fun onFetchStarted() {
        loading = true
    }

    fun onFetchResult(now: Long, result: Result) {
        loading = false
        when (result) {
            is Result.Loaded -> {
                failures = 0
                nextFetchAt = 0
                ad = result.ad
                fetchedAt = now
                rendered = false
                visibleSince = -1
                impressionSent = false
                clickSent = false
            }
            Result.NoFill -> {
                failures = 0
                nextFetchAt = now + NO_FILL_RETRY_MS
            }
            Result.Error -> {
                failures++
                nextFetchAt = now + backoffMs(failures)
            }
        }
    }

    /** The creative is on screen (image decoded, or failed): the dwell clock may start. */
    fun onRendered() {
        rendered = true
    }

    /** Advance the dwell clock; returns true exactly once, when the impression is due. */
    fun tick(now: Long, viewable: Boolean): Boolean {
        val current = ad ?: return false
        if (!rendered || impressionSent) return false
        if (!viewable || isStale(now)) {
            visibleSince = -1
            return false
        }
        if (visibleSince < 0) visibleSince = now
        if (now - visibleSince >= current.minDisplayMs && now - fetchedAt >= current.minDisplayMs) {
            impressionSent = true
            return true
        }
        return false
    }

    /** A click should be reported (once per ad, and only while its token is still valid). */
    fun consumeClick(now: Long): Boolean {
        if (ad == null || clickSent || isStale(now)) return false
        clickSent = true
        return true
    }

    fun isStale(now: Long): Boolean = ad != null && now - fetchedAt >= tokenTtlMs

    /** Forget the current ad (config change / dismissed). */
    fun reset() {
        ad = null
        loading = false
        failures = 0
        fetchedAt = -1
        nextFetchAt = 0
        rendered = false
        visibleSince = -1
        impressionSent = false
        clickSent = false
    }

    companion object {
        const val DEFAULT_REFRESH_SECONDS = 30
        const val MIN_REFRESH_SECONDS = 15
        /** Server tracking tokens live 60 s; refetch an uncounted ad a bit before that. */
        const val TOKEN_REFRESH_MS = 55_000L
        const val NO_FILL_RETRY_MS = 60_000L
        const val MAX_BACKOFF_MS = 300_000L

        @JvmStatic
        fun refreshMsFor(seconds: Int): Long =
            if (seconds <= 0) 0L else maxOf(seconds, MIN_REFRESH_SECONDS) * 1000L

        @JvmStatic
        fun backoffMs(failures: Int): Long {
            val n = (failures - 1).coerceIn(0, 10)
            return minOf(15_000L shl n, MAX_BACKOFF_MS)
        }
    }
}
