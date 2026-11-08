package com.crossindie.sdk

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.LruCache
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory
import java.util.concurrent.atomic.AtomicInteger

/**
 * Background networking for the banner: HttpURLConnection on a tiny daemon
 * thread pool, results delivered on the main thread. Every failure is
 * swallowed (logged only when [CrossIndie.debugLogging] is on) - the SDK must
 * never crash or block the host app.
 */
internal object AdClient {
    private const val TAG = "CrossIndie"
    private const val CONNECT_TIMEOUT_MS = 10_000
    private const val READ_TIMEOUT_MS = 15_000
    private const val MAX_IMAGE_BYTES = 8 * 1024 * 1024

    private val main = Handler(Looper.getMainLooper())

    private val executor: ExecutorService by lazy {
        val n = AtomicInteger()
        Executors.newFixedThreadPool(2, ThreadFactory { r ->
            Thread(r, "crossindie-" + n.incrementAndGet()).apply {
                isDaemon = true
                priority = Thread.MIN_PRIORITY
            }
        })
    }

    private val images = object : LruCache<String, Bitmap>(4 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    fun log(msg: String, t: Throwable? = null) {
        if (CrossIndie.debugLogging) Log.w(TAG, msg, t)
    }

    private fun runSafely(block: () -> Unit) {
        try {
            executor.execute {
                try {
                    block()
                } catch (t: Throwable) {
                    log("background task failed", t)
                }
            }
        } catch (t: Throwable) {
            log("could not schedule background task", t)
        }
    }

    private fun onMain(block: () -> Unit) {
        main.post {
            try {
                block()
            } catch (t: Throwable) {
                log("callback failed", t)
            }
        }
    }

    private fun open(url: String, method: String = "GET"): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            instanceFollowRedirects = true
            useCaches = false
            setRequestProperty("User-Agent", "CrossIndie-Android/${BuildConfig.SDK_VERSION}")
        }

    private fun readAll(input: InputStream, limit: Int): ByteArray? {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(16 * 1024)
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            out.write(buf, 0, n)
            if (out.size() > limit) return null
        }
        return out.toByteArray()
    }

    /** GET /api/v1/ad/fetch -> Loaded / NoFill (204) / Error (anything else). */
    fun fetchAd(url: String, apiBase: String, callback: (BannerState.Result) -> Unit) {
        runSafely {
            var result: BannerState.Result = BannerState.Result.Error
            var conn: HttpURLConnection? = null
            try {
                conn = open(url)
                conn.setRequestProperty("Accept", "application/json")
                val code = conn.responseCode
                result = when (code) {
                    204 -> BannerState.Result.NoFill
                    200 -> {
                        val body = conn.inputStream.use { readAll(it, 256 * 1024) }
                        val ad = body?.let { Ad.parse(String(it, Charsets.UTF_8), apiBase) }
                        if (ad != null) BannerState.Result.Loaded(ad) else BannerState.Result.Error
                    }
                    else -> {
                        log("ad fetch failed: HTTP $code" +
                            if (code == 403) " (app pending review, not approved, or origin locked)" else "")
                        BannerState.Result.Error
                    }
                }
            } catch (t: Throwable) {
                log("ad fetch failed", t)
            } finally {
                try { conn?.disconnect() } catch (_: Throwable) {}
            }
            val r = result
            onMain { callback(r) }
        }
    }

    /**
     * POST /api/v1/ad/track. A 425 ("too early") does not burn the token, so an
     * impression is retried once after a second, as the backend allows.
     */
    fun track(apiBase: String, token: String, eventType: String, retry: Boolean = true) {
        runSafely {
            var conn: HttpURLConnection? = null
            var code = -1
            try {
                conn = open(AdRequests.trackUrl(apiBase), "POST")
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.outputStream.use { it.write(AdRequests.trackBody(token, eventType).toByteArray(Charsets.UTF_8)) }
                code = conn.responseCode
                try { (if (code < 400) conn.inputStream else conn.errorStream)?.use { readAll(it, 16 * 1024) } } catch (_: Throwable) {}
                if (code >= 400) log("track $eventType -> HTTP $code")
            } catch (t: Throwable) {
                log("track $eventType failed", t)
            } finally {
                try { conn?.disconnect() } catch (_: Throwable) {}
            }
            if (code == 425 && retry) {
                main.postDelayed({ track(apiBase, token, eventType, retry = false) }, 1000)
            }
        }
    }

    /** Download + decode an image, downsampled to roughly [targetW]x[targetH] px. */
    fun loadImage(url: String, targetW: Int, targetH: Int, callback: (Bitmap?) -> Unit) {
        images.get(url)?.let { cached ->
            callback(cached)
            return
        }
        runSafely {
            var bmp: Bitmap? = null
            var conn: HttpURLConnection? = null
            try {
                conn = open(url)
                if (conn.responseCode == 200) {
                    val bytes = conn.inputStream.use { readAll(it, MAX_IMAGE_BYTES) }
                    if (bytes != null) bmp = decode(bytes, targetW, targetH)
                }
            } catch (t: Throwable) {
                log("image load failed", t)
            } finally {
                try { conn?.disconnect() } catch (_: Throwable) {}
            }
            bmp?.let { images.put(url, it) }
            val b = bmp
            onMain { callback(b) }
        }
    }

    private fun decode(bytes: ByteArray, targetW: Int, targetH: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, targetW, targetH)
        }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    }

    /** Largest power-of-two sample size that keeps the image >= the target size. */
    @JvmStatic
    fun sampleSize(w: Int, h: Int, targetW: Int, targetH: Int): Int {
        if (targetW <= 0 || targetH <= 0) return 1
        var s = 1
        while (w / (s * 2) >= targetW && h / (s * 2) >= targetH) s *= 2
        return s
    }
}
