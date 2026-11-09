package com.crossindie.sdk

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.MediaPlayer
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.TextUtils
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * CrossIndie cross-promotion banner.
 *
 * ```xml
 * <com.crossindie.sdk.CrossIndieBannerView
 *     android:layout_width="match_parent"
 *     android:layout_height="wrap_content"
 *     app:ciAppId="YOUR_APP_ID"
 *     app:ciCategory="game"
 *     app:ciFormat="mobile" />
 * ```
 *
 * The slot stays collapsed (zero height) until an ad is available. An
 * impression is reported only after the banner has been continuously >= 50 %
 * visible, with the window focused, for the server's minimum display time;
 * hidden slots make no network requests after their first fetch.
 */
class CrossIndieBannerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {

    // ------------------------------------------------------------------ config
    /** Your app id from Dashboard > Integration. */
    var appId: String = ""
        set(value) { if (field != value.trim()) { field = value.trim(); changed() } }

    /** Category pool to request: game | mobile_app | web_tool | saas. */
    var category: String = "game"
        set(value) { if (field != value) { field = value; changed() } }

    var format: BannerFormat = BannerFormat.MOBILE
        set(value) { if (field != value) { field = value; if (::card.isInitialized) buildLayout(); changed() } }

    /** Per-banner API base; null uses [CrossIndie.apiBase]. */
    var apiBase: String? = null
        set(value) { if (field != value) { field = value; changed() } }

    /** Rotate to a new ad this long after an impression (0 = never, min 15). */
    var refreshSeconds: Int = BannerState.DEFAULT_REFRESH_SECONDS
        set(value) { field = value; state.setRefreshSeconds(value) }

    /** Allow muted video creatives (requested only on unmetered networks). */
    var videoEnabled: Boolean = true
        set(value) { if (field != value) { field = value; changed() } }

    /** Show a small close button that hides the slot. */
    var closeable: Boolean = false
        set(value) { field = value; closeButton?.visibility = if (value) VISIBLE else GONE }

    /** Optional viewer country (ISO-3166 alpha-2) for region targeting. */
    var country: String? = null
        set(value) { if (field != value) { field = value; changed() } }

    var listener: CrossIndieBannerListener? = null

    // ------------------------------------------------------------------- state
    private val state = BannerState()
    private val main = Handler(Looper.getMainLooper())
    private var configGen = 0
    private var renderGen = 0
    private var ticking = false
    private var dismissed = false
    private var pendingVideoUrl = ""
    private var video: VideoPlayer? = null
    private var batching = false
    private var reloadPending = false

    private lateinit var card: FrameLayout
    private lateinit var mediaFrame: MediaFrame
    private lateinit var imageView: ImageView
    private lateinit var titleView: TextView
    private lateinit var descView: TextView
    private var badgeView: TextView? = null
    private var closeButton: TextView? = null

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!ticking) return
            try {
                tick()
            } catch (t: Throwable) {
                AdClient.log("tick failed", t)
            }
            main.postDelayed(this, TICK_MS)
        }
    }

    init {
        var initialAppId = ""
        if (attrs != null) {
            val a = context.obtainStyledAttributes(attrs, R.styleable.CrossIndieBannerView, defStyleAttr, 0)
            try {
                initialAppId = a.getString(R.styleable.CrossIndieBannerView_ciAppId).orEmpty().trim()
                a.getString(R.styleable.CrossIndieBannerView_ciCategory)?.let { category = it }
                format = BannerFormat.from(a.getString(R.styleable.CrossIndieBannerView_ciFormat))
                apiBase = a.getString(R.styleable.CrossIndieBannerView_ciApiBase)
                refreshSeconds = a.getInt(R.styleable.CrossIndieBannerView_ciRefreshSeconds, refreshSeconds)
                videoEnabled = a.getBoolean(R.styleable.CrossIndieBannerView_ciVideo, true)
                closeable = a.getBoolean(R.styleable.CrossIndieBannerView_ciCloseable, false)
                country = a.getString(R.styleable.CrossIndieBannerView_ciCountry)
            } finally {
                a.recycle()
            }
        }
        buildLayout()
        appId = initialAppId
    }

    /** Set everything at once (one reload). Used by the Compose wrapper. */
    fun configure(
        appId: String,
        category: String = "game",
        format: BannerFormat = BannerFormat.MOBILE,
        apiBase: String? = null,
        refreshSeconds: Int = BannerState.DEFAULT_REFRESH_SECONDS,
        videoEnabled: Boolean = true,
        closeable: Boolean = false,
        country: String? = null,
    ) {
        batching = true
        try {
            this.appId = appId
            this.category = category
            this.format = format
            this.apiBase = apiBase
            this.videoEnabled = videoEnabled
            this.country = country
            this.refreshSeconds = refreshSeconds
            this.closeable = closeable
        } finally {
            batching = false
        }
        if (reloadPending) reload()
    }

    private fun changed() {
        if (batching) reloadPending = true else reload()
    }

    /** Drop the current ad and fetch a new one now. */
    fun reload() {
        if (!::card.isInitialized) return
        reloadPending = false
        configGen++
        renderGen++
        state.reset()
        dismissed = false
        releaseVideo()
        pendingVideoUrl = ""
        card.visibility = GONE
        if (ticking) {
            main.removeCallbacks(tickRunnable)
            main.post(tickRunnable)
        }
    }

    // ---------------------------------------------------------------- lifecycle
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!ticking) {
            ticking = true
            main.post(tickRunnable)
        }
    }

    override fun onDetachedFromWindow() {
        ticking = false
        main.removeCallbacks(tickRunnable)
        releaseVideo()
        super.onDetachedFromWindow()
    }

    private fun tick() {
        if (appId.isEmpty() || dismissed) return
        val now = SystemClock.elapsedRealtime()
        val onScreen = isOnScreen()
        val viewable = onScreen && isViewable()
        if (state.shouldFetch(now, onScreen, viewable)) fetch()
        if (state.tick(now, viewable)) {
            state.ad?.let { ad ->
                AdClient.track(resolvedBase(), ad.trackingToken, "impression")
                listener?.onImpression(ad)
            }
        }
        // Video: lazy-load only once actually viewable; pause when not.
        if (viewable && video == null && pendingVideoUrl.isNotEmpty()) startVideo(pendingVideoUrl)
        video?.setPlaying(viewable)
    }

    private fun isOnScreen(): Boolean =
        isAttachedToWindow && windowVisibility == VISIBLE && isShown && !dismissed

    private fun isViewable(): Boolean {
        if (!hasWindowFocus() || card.visibility != VISIBLE) return false
        if (card.width <= 0 || card.height <= 0 || alpha <= 0.01f) return false
        val r = Rect()
        if (!card.getGlobalVisibleRect(r)) return false
        return Visibility.isViewable(r.width(), r.height(), card.width, card.height)
    }

    // -------------------------------------------------------------- networking
    private fun resolvedBase(): String =
        Ad.normalizeBase(apiBase?.takeIf { it.isNotBlank() } ?: CrossIndie.apiBase)

    private fun fetch() {
        val gen = configGen
        val base = resolvedBase()
        val url = AdRequests.fetchUrl(
            apiBase = base,
            appId = appId,
            category = category,
            packageName = context.packageName.orEmpty(),
            lang = Locale.getDefault().language,
            country = country,
            video = videoEnabled && format.hasMedia && canStreamVideo(),
        )
        state.onFetchStarted()
        AdClient.fetchAd(url, base) { result ->
            if (gen != configGen) return@fetchAd
            val hadAd = state.ad != null
            state.onFetchResult(SystemClock.elapsedRealtime(), result)
            when (result) {
                is BannerState.Result.Loaded -> render(result.ad)
                BannerState.Result.NoFill -> if (!hadAd) listener?.onNoFill()
                BannerState.Result.Error -> listener?.onAdFailed("ad fetch failed")
            }
        }
    }

    /** Only stream video on unmetered networks (needs the host's ACCESS_NETWORK_STATE). */
    private fun canStreamVideo(): Boolean = try {
        if (context.checkCallingOrSelfPermission(Manifest.permission.ACCESS_NETWORK_STATE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            false
        } else {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            cm != null && !cm.isActiveNetworkMetered
        }
    } catch (t: Throwable) {
        false
    }

    // --------------------------------------------------------------- rendering
    private fun render(ad: Ad) {
        val gen = ++renderGen
        releaseVideo()
        pendingVideoUrl = ""
        val apply = { bmp: android.graphics.Bitmap? ->
            if (gen == renderGen) {
                imageView.setImageBitmap(bmp)
                titleView.text = ad.name
                descView.text = ad.description
                descView.visibility =
                    if (format.showDescription && ad.description.isNotBlank()) VISIBLE else GONE
                imageView.contentDescription = ad.name
                if (format.hasMedia) pendingVideoUrl = ad.videoUrl
                card.visibility = VISIBLE
                relayout()
                state.onRendered()
                listener?.onAdLoaded(ad)
            }
        }
        if (format.hasMedia && ad.bannerImageUrl.isNotEmpty()) {
            val w = if (mediaFrame.width > 0) mediaFrame.width else dp(format.maxWidthDp)
            val h = if (mediaFrame.height > 0) mediaFrame.height else dp(180)
            AdClient.loadImage(ad.bannerImageUrl, w, h) { bmp -> apply(bmp) }
        } else {
            apply(null)
        }
    }

    /**
     * The slot grows from 0 to the banner's height. Make sure that reaches the
     * host layout even if an ancestor was measured but never laid out (e.g. a
     * Compose LazyColumn prefetch), which would otherwise swallow requestLayout().
     */
    private fun relayout() {
        var v: View? = this
        while (v != null) {
            v.requestLayout()
            v = v.parent as? View
        }
    }

    private fun onBannerClicked() {
        val ad = state.ad ?: return
        if (state.consumeClick(SystemClock.elapsedRealtime())) {
            AdClient.track(resolvedBase(), ad.trackingToken, "click")
        }
        openUrl(ad.targetUrl)
        listener?.onClick(ad)
    }

    private fun openUrl(url: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE)
            if (findActivity(context) == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (t: Throwable) {
            AdClient.log("could not open $url", t)
        }
    }

    private fun dismiss() {
        dismissed = true
        renderGen++
        releaseVideo()
        pendingVideoUrl = ""
        card.visibility = GONE
        relayout()
        listener?.onClosed()
    }

    // ------------------------------------------------------------------ layout
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maxW = dp(format.maxWidthDp)
        val wMode = MeasureSpec.getMode(widthMeasureSpec)
        val wSize = MeasureSpec.getSize(widthMeasureSpec)
        val ownW = if (wMode == MeasureSpec.UNSPECIFIED) maxW else wSize
        val cardW = min(ownW, maxW)
        var contentH = 0
        if (card.visibility != GONE) {
            val hSpec = if (format.heightDp > 0) {
                MeasureSpec.makeMeasureSpec(dp(format.heightDp), MeasureSpec.EXACTLY)
            } else {
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            }
            card.measure(MeasureSpec.makeMeasureSpec(cardW, MeasureSpec.EXACTLY), hSpec)
            contentH = card.measuredHeight
        }
        val w = when {
            wMode == MeasureSpec.EXACTLY -> wSize
            card.visibility == GONE -> 0
            else -> cardW
        }
        setMeasuredDimension(w, resolveSize(contentH + paddingTop + paddingBottom, heightMeasureSpec))
    }

    private fun buildLayout() {
        removeAllViews()
        val f = format
        val ctx = context
        val small = f.heightDp in 1..50

        card = FrameLayout(ctx).apply {
            background = GradientDrawable().apply {
                setColor(BG)
                cornerRadius = dpf(if (small) 8 else 12)
                setStroke(dp(1).coerceAtLeast(1), BORDER)
            }
            clipToOutline = true
            visibility = GONE
        }
        val row = LinearLayout(ctx).apply {
            orientation = if (f.horizontal) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
            isClickable = true
            isFocusable = true
            setOnClickListener { onBannerClicked() }
        }
        mediaFrame = MediaFrame(ctx).apply {
            setBackgroundColor(MEDIA_BG)
            fixedHeightPx = if (!f.horizontal && f.mediaHeightDp > 0) dp(f.mediaHeightDp) else 0
            ratio = if (!f.horizontal && f.mediaHeightDp == 0) 9f / 16f else 0f
        }
        imageView = ImageView(ctx).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
        mediaFrame.addView(imageView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        if (f.hasMedia) {
            val lp = if (f.horizontal) {
                LinearLayout.LayoutParams(dp(f.mediaWidthDp), LinearLayout.LayoutParams.MATCH_PARENT)
            } else {
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            }
            row.addView(mediaFrame, lp)
        }

        val textBox = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            if (small) setPadding(dp(10), dp(6), dp(26), dp(6)) else setPadding(dp(12), dp(10), dp(12), dp(10))
        }
        titleView = TextView(ctx).apply {
            setTextColor(FG)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, if (small) 13f else 14f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        descView = TextView(ctx).apply {
            setTextColor(MUTED)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            maxLines = if (f.horizontal) 1 else 2
            ellipsize = TextUtils.TruncateAt.END
            setPadding(0, dp(2), 0, if (f.showBadge && !f.horizontal) dp(14) else 0)
            visibility = GONE
        }
        textBox.addView(titleView)
        textBox.addView(descView)
        row.addView(
            textBox,
            if (f.horizontal) LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f)
            else LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT),
        )
        card.addView(row, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        // Ad label, always visible so the banner is never mistaken for app content.
        // Bigger formats carry the full attribution, its own link to crossindie.com
        // (never tracked as an ad click); the 320x50 strip gets a compact "AD" chip.
        badgeView = TextView(ctx).apply {
            text = if (f.showBadge) "AD \u00B7 PROMOTED WITH CROSSINDIE" else "AD"
            letterSpacing = 0.1f
            setTextSize(TypedValue.COMPLEX_UNIT_SP, if (f.showBadge) 9f else 8f)
            setTextColor(BADGE_FG)
            background = GradientDrawable().apply { setColor(OVERLAY); cornerRadius = dpf(if (f.showBadge) 6 else 4) }
            if (f.showBadge) setPadding(dp(6), dp(2), dp(6), dp(2)) else setPadding(dp(4), dp(1), dp(4), dp(1))
            contentDescription = "Advertisement"
            if (f.showBadge) setOnClickListener { openUrl("https://crossindie.com") }
        }.also {
            val m = if (f.showBadge) dp(6) else dp(4)
            card.addView(it, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.END).apply {
                setMargins(0, 0, m, m)
            })
        }

        // Small universal close button; dismissing before the dwell time records nothing.
        closeButton = TextView(ctx).apply {
            text = "×"
            gravity = Gravity.CENTER
            setTextColor(FG)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            includeFontPadding = false
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(CLOSE_BG) }
            contentDescription = "Close"
            visibility = if (closeable) VISIBLE else GONE
            setOnClickListener { dismiss() }
        }.also {
            card.addView(it, LayoutParams(dp(18), dp(18), Gravity.TOP or Gravity.END).apply { setMargins(0, dp(5), dp(5), 0) })
        }

        addView(card, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL))
    }

    // ------------------------------------------------------------------- video
    private fun startVideo(url: String) {
        if (!format.hasMedia || !isHardwareAccelerated) {
            pendingVideoUrl = ""
            return
        }
        val gen = renderGen
        val player = VideoPlayer(url) {
            // On any playback error fall back to the static poster for this ad.
            if (gen == renderGen) {
                releaseVideo()
                pendingVideoUrl = ""
            }
        }
        video = player
        mediaFrame.addView(player.view, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    private fun releaseVideo() {
        val v = video ?: return
        video = null
        v.release()
        try { (v.view.parent as? FrameLayout)?.removeView(v.view) } catch (_: Throwable) {}
    }

    /** Muted, looping MP4 on a TextureView (scrolls cleanly inside lists). */
    private inner class VideoPlayer(
        private val url: String,
        private val onError: () -> Unit,
    ) : TextureView.SurfaceTextureListener {
        val view = TextureView(context)
        private var player: MediaPlayer? = null
        private var surface: Surface? = null
        private var prepared = false
        private var wantPlay = false
        private var released = false
        private var videoW = 0
        private var videoH = 0

        init {
            view.alpha = 0f // keep the poster image visible until the first frame
            view.surfaceTextureListener = this
            view.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applyCrop() }
        }

        fun setPlaying(play: Boolean) {
            wantPlay = play
            val p = player ?: return
            if (!prepared) return
            try {
                if (play && !p.isPlaying) p.start() else if (!play && p.isPlaying) p.pause()
            } catch (t: Throwable) {
                fail(t)
            }
        }

        override fun onSurfaceTextureAvailable(st: SurfaceTexture, width: Int, height: Int) {
            if (released) return
            try {
                surface = Surface(st)
                player = MediaPlayer().apply {
                    setSurface(surface)
                    setVolume(0f, 0f)
                    isLooping = true
                    setOnPreparedListener {
                        prepared = true
                        if (wantPlay) it.start()
                    }
                    setOnVideoSizeChangedListener { _, w, h -> videoW = w; videoH = h; applyCrop() }
                    setOnInfoListener { _, what, _ ->
                        if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) view.alpha = 1f
                        false
                    }
                    setOnErrorListener { _, _, _ -> fail(null); true }
                    setDataSource(url)
                    prepareAsync()
                }
            } catch (t: Throwable) {
                fail(t)
            }
        }

        override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, width: Int, height: Int) = applyCrop()
        override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
            release()
            return true
        }
        override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}

        /** Scale like centerCrop (TextureView stretches by default). */
        private fun applyCrop() {
            val w = view.width.toFloat()
            val h = view.height.toFloat()
            if (w <= 0f || h <= 0f || videoW <= 0 || videoH <= 0) return
            val scale = max(w / videoW, h / videoH)
            val m = Matrix()
            m.setScale(videoW * scale / w, videoH * scale / h, w / 2f, h / 2f)
            view.setTransform(m)
        }

        private fun fail(t: Throwable?) {
            AdClient.log("video playback failed", t)
            main.post { onError() }
        }

        fun release() {
            if (released) return
            released = true
            try { player?.release() } catch (_: Throwable) {}
            try { surface?.release() } catch (_: Throwable) {}
            player = null
            surface = null
        }
    }

    // ----------------------------------------------------------------- helpers
    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).roundToInt()
    private fun dpf(v: Int): Float = v * resources.displayMetrics.density

    private fun findActivity(c: Context?): Activity? {
        var cur = c
        while (cur is ContextWrapper) {
            if (cur is Activity) return cur
            cur = cur.baseContext
        }
        return null
    }

    /** Media area: fixed height, or a width-relative aspect ratio (16:9). */
    private class MediaFrame(context: Context) : FrameLayout(context) {
        var fixedHeightPx = 0
        var ratio = 0f

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val w = MeasureSpec.getSize(widthMeasureSpec)
            val hSpec = when {
                fixedHeightPx > 0 -> MeasureSpec.makeMeasureSpec(fixedHeightPx, MeasureSpec.EXACTLY)
                ratio > 0f && w > 0 -> MeasureSpec.makeMeasureSpec((w * ratio).roundToInt(), MeasureSpec.EXACTLY)
                else -> heightMeasureSpec
            }
            super.onMeasure(widthMeasureSpec, hSpec)
        }
    }

    private companion object {
        const val TICK_MS = 250L
        val BG = Color.parseColor("#141210")
        val BORDER = Color.parseColor("#27272a")
        val FG = Color.parseColor("#f5f3ef")
        val MUTED = Color.parseColor("#a8a29a")
        val MEDIA_BG = Color.parseColor("#0a0a0c")
        val BADGE_FG = Color.parseColor("#d6d3cd")
        val OVERLAY = Color.argb(184, 10, 10, 12)
        val CLOSE_BG = Color.argb(140, 10, 10, 12)
    }
}
