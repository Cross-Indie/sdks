package com.crossindie.sdk.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.layout.layout
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.crossindie.sdk.Ad
import com.crossindie.sdk.BannerFormat
import com.crossindie.sdk.BannerState
import com.crossindie.sdk.CrossIndieBannerListener
import com.crossindie.sdk.CrossIndieBannerView

/**
 * CrossIndie cross-promotion banner for Jetpack Compose.
 *
 * ```kotlin
 * CrossIndieBanner(appId = "YOUR_APP_ID", category = "game")
 * ```
 *
 * Wraps [CrossIndieBannerView], so behaviour is identical: the slot is
 * collapsed until an ad loads, impressions are counted only while >= 50 % of
 * the banner is on screen for the minimum display time, and it rotates after
 * [refreshSeconds] (0 = never).
 */
@Composable
fun CrossIndieBanner(
    appId: String,
    modifier: Modifier = Modifier,
    category: String = "game",
    format: BannerFormat = BannerFormat.MOBILE,
    apiBase: String? = null,
    refreshSeconds: Int = BannerState.DEFAULT_REFRESH_SECONDS,
    video: Boolean = true,
    closeable: Boolean = false,
    country: String? = null,
    listener: CrossIndieBannerListener? = null,
) {
    // Bump on load/close so Compose re-measures the slot (it grows from zero
    // height). A View growing on its own isn't always noticed by lazy lists.
    var layoutVersion by remember { mutableIntStateOf(0) }
    val currentListener by rememberUpdatedState(listener)
    val bridge = remember {
        object : CrossIndieBannerListener {
            override fun onAdLoaded(ad: Ad) { layoutVersion++; currentListener?.onAdLoaded(ad) }
            override fun onNoFill() { currentListener?.onNoFill() }
            override fun onAdFailed(reason: String) { currentListener?.onAdFailed(reason) }
            override fun onImpression(ad: Ad) { currentListener?.onImpression(ad) }
            override fun onClick(ad: Ad) { currentListener?.onClick(ad) }
            override fun onClosed() { layoutVersion++; currentListener?.onClosed() }
        }
    }
    AndroidView(
        modifier = modifier.layout { measurable, constraints ->
            layoutVersion // read: re-measure when it changes
            val p = measurable.measure(constraints)
            layout(p.width, p.height) { p.place(0, 0) }
        },
        factory = { context -> CrossIndieBannerView(context) },
        // Keep the View (and its loaded ad) when a lazy list recycles the item.
        onReset = { },
        update = { view ->
            view.listener = bridge
            view.configure(
                appId = appId,
                category = category,
                format = format,
                apiBase = apiBase,
                refreshSeconds = refreshSeconds,
                videoEnabled = video,
                closeable = closeable,
                country = country,
            )
        },
    )
}
