package com.crossindie.sdk

/** Global SDK settings. All optional - a banner only needs its app id. */
object CrossIndie {
    const val DEFAULT_API_BASE = "https://api.crossindie.com"

    /** SDK version (the git tag it was built from when installed via JitPack). */
    @JvmField
    val VERSION: String = BuildConfig.SDK_VERSION

    /** Default API base for every banner that doesn't set its own. */
    @JvmStatic
    @Volatile
    var apiBase: String = DEFAULT_API_BASE

    /** Log swallowed network errors to Logcat (tag "CrossIndie"). Off by default. */
    @JvmStatic
    @Volatile
    var debugLogging: Boolean = false
}

/** Callbacks for a banner slot. All methods are optional and run on the main thread. */
interface CrossIndieBannerListener {
    fun onAdLoaded(ad: Ad) {}
    /** The network had no eligible ad right now; the slot stays collapsed and retries later. */
    fun onNoFill() {}
    fun onAdFailed(reason: String) {}
    /** A viewable impression was reported (your app earns credits for it). */
    fun onImpression(ad: Ad) {}
    fun onClick(ad: Ad) {}
    /** The viewer dismissed the slot with the close button. */
    fun onClosed() {}
}

/**
 * Banner layouts, the same set as the web SDK. Sizes are maximum widths /
 * fixed heights in dp; the banner shrinks to the available width.
 */
enum class BannerFormat(
    internal val maxWidthDp: Int,
    internal val heightDp: Int,      // 0 = wrap content
    internal val horizontal: Boolean,
    internal val mediaWidthDp: Int,  // horizontal formats
    internal val mediaHeightDp: Int, // vertical formats; 0 = 16:9 of the width
    internal val hasMedia: Boolean,
    internal val showDescription: Boolean,
    internal val showBadge: Boolean,
) {
    /** 320x50 strip: icon + headline. The classic in-app banner (default). */
    MOBILE(320, 50, true, 50, 0, true, false, false),
    /** 320 wide, 16:9 artwork with headline + description below. */
    CARD(320, 0, false, 0, 0, true, true, true),
    /** 300x250 medium rectangle. */
    RECTANGLE(300, 250, false, 0, 150, true, true, true),
    /** 728x90 leaderboard (tablets). */
    LEADERBOARD(728, 90, true, 150, 0, true, true, true),
    /** Text only: headline + description. */
    TEXT(320, 0, false, 0, 0, false, true, true);

    val apiName: String get() = name.lowercase()

    companion object {
        @JvmStatic
        fun from(value: String?): BannerFormat =
            entries.firstOrNull { it.apiName == value?.trim()?.lowercase() } ?: MOBILE
    }
}
