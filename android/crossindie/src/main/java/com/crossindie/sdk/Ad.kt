package com.crossindie.sdk

import org.json.JSONObject
import java.net.URLEncoder

/** One ad served by `GET /api/v1/ad/fetch`. */
data class Ad(
    val adId: String,
    val name: String,
    val description: String,
    val targetUrl: String,
    val bannerImageUrl: String,
    val videoUrl: String,
    val trackingToken: String,
    val minDisplayMs: Long,
) {
    companion object {
        /** Same default as the web / Unity / Godot SDKs when the server omits it. */
        const val DEFAULT_MIN_DISPLAY_MS = 1500L

        /**
         * Parse a fetch response body. Media URLs that come back relative
         * ("/media/...") are resolved against [apiBase]. Returns null for an
         * invalid payload (no tracking token or no target URL) - never throws.
         */
        @JvmStatic
        fun parse(json: String, apiBase: String): Ad? = try {
            val o = JSONObject(json)
            val token = o.optString("tracking_token", "")
            val target = o.optString("target_url", "")
            if (token.isEmpty() || target.isEmpty()) {
                null
            } else {
                val min = o.optLong("min_display_ms", DEFAULT_MIN_DISPLAY_MS)
                Ad(
                    adId = o.optString("ad_id", ""),
                    name = o.optString("name", ""),
                    description = o.optString("description", ""),
                    targetUrl = target,
                    bannerImageUrl = resolveMedia(apiBase, o.optString("banner_image_url", "")),
                    videoUrl = resolveMedia(apiBase, o.optString("video_url", "")),
                    trackingToken = token,
                    minDisplayMs = if (min > 0) min else DEFAULT_MIN_DISPLAY_MS,
                )
            }
        } catch (t: Throwable) {
            null
        }

        /** "/media/x.png" -> "https://api.crossindie.com/media/x.png"; absolute URLs pass through. */
        @JvmStatic
        fun resolveMedia(apiBase: String, url: String?): String {
            if (url.isNullOrBlank() || url == "null") return ""
            return if (url.startsWith("/")) normalizeBase(apiBase) + url else url
        }

        @JvmStatic
        fun normalizeBase(apiBase: String): String = apiBase.trim().trimEnd('/')
    }
}

/** Request builders for the public ad API (pure functions, unit-tested). */
object AdRequests {
    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8")

    /**
     * Build the fetch URL. `platform` + `package` feed the dashboard's
     * "SDK active" heartbeat (and let the network confirm the SDK runs inside
     * the store app). `video=1` only on connections that can spare it.
     */
    @JvmStatic
    fun fetchUrl(
        apiBase: String,
        appId: String,
        category: String,
        packageName: String,
        lang: String?,
        country: String?,
        video: Boolean,
        platform: String = "android",
    ): String {
        val sb = StringBuilder(Ad.normalizeBase(apiBase))
            .append("/api/v1/ad/fetch?app_id=").append(enc(appId.trim()))
            .append("&category=").append(enc(category.ifBlank { "game" }))
            .append("&platform=").append(enc(platform))
        if (packageName.isNotBlank()) sb.append("&package=").append(enc(packageName))
        if (!lang.isNullOrBlank()) sb.append("&lang=").append(enc(lang.take(2).lowercase()))
        if (!country.isNullOrBlank()) sb.append("&country=").append(enc(country.uppercase()))
        if (video) sb.append("&video=1")
        return sb.toString()
    }

    @JvmStatic
    fun trackUrl(apiBase: String): String = Ad.normalizeBase(apiBase) + "/api/v1/ad/track"

    /** `{"tracking_token": ..., "event_type": "impression" | "click"}` */
    @JvmStatic
    fun trackBody(token: String, eventType: String): String =
        JSONObject().put("tracking_token", token).put("event_type", eventType).toString()
}
