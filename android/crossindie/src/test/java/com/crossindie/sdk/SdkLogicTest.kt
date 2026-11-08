package com.crossindie.sdk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AdParsingTest {
    private val base = "https://api.crossindie.com/"

    @Test fun parsesFullPayloadAndResolvesRelativeMedia() {
        val ad = Ad.parse(
            """{"ad_id":"a1","name":"Cool Game","description":"Jump!","category":"game",
               "target_url":"https://play.google.com/store/apps/details?id=x&ci_ref=r",
               "banner_image_url":"/media/b.png","video_url":"https://cdn.x/v.mp4","video_ogv_url":"",
               "tracking_token":"tok","min_display_ms":1500}""",
            base,
        )
        assertNotNull(ad)
        ad!!
        assertEquals("Cool Game", ad.name)
        assertEquals("Jump!", ad.description)
        assertEquals("https://api.crossindie.com/media/b.png", ad.bannerImageUrl)
        assertEquals("https://cdn.x/v.mp4", ad.videoUrl)
        assertEquals("tok", ad.trackingToken)
        assertEquals(1500L, ad.minDisplayMs)
    }

    @Test fun defaultsMissingOptionalFields() {
        val ad = Ad.parse("""{"target_url":"https://x","tracking_token":"t"}""", base)!!
        assertEquals("", ad.bannerImageUrl)
        assertEquals("", ad.videoUrl)
        assertEquals(Ad.DEFAULT_MIN_DISPLAY_MS, ad.minDisplayMs)
    }

    @Test fun rejectsInvalidPayloads() {
        assertNull(Ad.parse("not json", base))
        assertNull(Ad.parse("""{"target_url":"https://x"}""", base)) // no token
        assertNull(Ad.parse("""{"tracking_token":"t"}""", base))     // no target
        assertNull(Ad.parse("", base))
    }

    @Test fun nonPositiveMinDisplayFallsBack() {
        val ad = Ad.parse("""{"target_url":"https://x","tracking_token":"t","min_display_ms":0}""", base)!!
        assertEquals(Ad.DEFAULT_MIN_DISPLAY_MS, ad.minDisplayMs)
    }

    @Test fun fetchUrlCarriesPlatformPackageAndOptions() {
        val url = AdRequests.fetchUrl(
            apiBase = "https://api.crossindie.com/", appId = "abc-123", category = "mobile_app",
            packageName = "com.dev.app", lang = "tr", country = "tr", video = true,
        )
        assertEquals(
            "https://api.crossindie.com/api/v1/ad/fetch?app_id=abc-123&category=mobile_app" +
                "&platform=android&package=com.dev.app&lang=tr&country=TR&video=1",
            url,
        )
        val minimal = AdRequests.fetchUrl("https://h", "id", "", "", null, null, false)
        assertEquals("https://h/api/v1/ad/fetch?app_id=id&category=game&platform=android", minimal)
    }

    @Test fun trackBodyMatchesBackendSchema() {
        assertEquals("https://h/api/v1/ad/track", AdRequests.trackUrl("https://h/"))
        val body = org.json.JSONObject(AdRequests.trackBody("tok", "impression"))
        assertEquals("tok", body.getString("tracking_token"))
        assertEquals("impression", body.getString("event_type"))
    }

    @Test fun formatParsing() {
        assertEquals(BannerFormat.CARD, BannerFormat.from("Card"))
        assertEquals(BannerFormat.MOBILE, BannerFormat.from(null))
        assertEquals(BannerFormat.MOBILE, BannerFormat.from("bogus"))
    }
}

class VisibilityTest {
    @Test fun requiresNonZeroSizeAndHalfVisible() {
        assertFalse(Visibility.isViewable(0, 0, 0, 0))
        assertFalse(Visibility.isViewable(100, 50, 0, 50))
        assertTrue(Visibility.isViewable(100, 50, 100, 50))
        assertTrue(Visibility.isViewable(100, 25, 100, 50))   // exactly 50 %
        assertFalse(Visibility.isViewable(100, 24, 100, 50))
        assertFalse(Visibility.isViewable(49, 50, 100, 50))
        assertEquals(1f, Visibility.fraction(500, 500, 100, 50), 0.0001f) // clamped
    }
}

class BannerStateTest {
    private fun ad(min: Long = 1500) = Ad("id", "n", "d", "https://x", "", "", "tok", min)

    private fun loaded(s: BannerState, now: Long, a: Ad = ad()) {
        assertTrue(s.shouldFetch(now, onScreen = true, viewable = false) || s.ad != null)
        s.onFetchStarted()
        s.onFetchResult(now, BannerState.Result.Loaded(a))
        s.onRendered()
    }

    @Test fun firstFetchNeedsOnlyOnScreen() {
        val s = BannerState()
        assertFalse(s.shouldFetch(0, onScreen = false, viewable = false))
        assertTrue(s.shouldFetch(0, onScreen = true, viewable = false))
        s.onFetchStarted()
        assertFalse(s.shouldFetch(0, true, true)) // in flight
    }

    @Test fun impressionAfterContinuousVisibility() {
        val s = BannerState()
        loaded(s, 0)
        assertFalse(s.tick(0, true))
        assertFalse(s.tick(1000, true))
        assertTrue(s.tick(1500, true))
        assertFalse(s.tick(3000, true)) // only once
        assertTrue(s.impressionSent)
    }

    @Test fun goingOutOfViewResetsDwell() {
        val s = BannerState()
        loaded(s, 0)
        s.tick(0, true)
        s.tick(1400, true)
        s.tick(1450, false)           // scrolled away
        assertFalse(s.tick(1500, true))
        assertFalse(s.tick(2900, true))
        assertTrue(s.tick(3000, true))
    }

    @Test fun neverCountsBeforeRenderOrWhenHidden() {
        val s = BannerState()
        s.onFetchStarted()
        s.onFetchResult(0, BannerState.Result.Loaded(ad()))
        assertFalse(s.tick(5000, true)) // image not rendered yet
        s.onRendered()
        for (t in 5000L..20000L step 250) assertFalse(s.tick(t, false))
    }

    @Test fun staleTokenIsRefetchedOnlyWhenViewableAndNeverCounted() {
        val s = BannerState()
        loaded(s, 0)
        assertFalse(s.shouldFetch(30_000, true, true))
        assertFalse(s.shouldFetch(56_000, true, false)) // hidden: no request
        assertTrue(s.shouldFetch(56_000, true, true))
        s.tick(55_000, true)
        assertFalse(s.tick(57_000, true)) // stale token never reported
    }

    @Test fun rotatesAfterImpression() {
        val s = BannerState(refreshSeconds = 30)
        loaded(s, 0)
        s.tick(0, true); assertTrue(s.tick(1500, true))
        assertFalse(s.shouldFetch(29_000, true, true))
        assertTrue(s.shouldFetch(30_000, true, true))
        assertFalse(s.shouldFetch(30_000, true, false))
        s.onFetchStarted()
        s.onFetchResult(30_000, BannerState.Result.Loaded(ad()))
        assertFalse(s.impressionSent) // new ad, new impression cycle
    }

    @Test fun refreshDisabledAndClamped() {
        assertEquals(0L, BannerState.refreshMsFor(0))
        assertEquals(15_000L, BannerState.refreshMsFor(5))
        assertEquals(60_000L, BannerState.refreshMsFor(60))
        val s = BannerState(refreshSeconds = 0)
        loaded(s, 0)
        s.tick(0, true); s.tick(1500, true)
        assertFalse(s.shouldFetch(600_000, true, true))
    }

    @Test fun noFillAndErrorBackoff() {
        val s = BannerState()
        s.onFetchStarted(); s.onFetchResult(0, BannerState.Result.NoFill)
        assertFalse(s.shouldFetch(59_999, true, true))
        assertTrue(s.shouldFetch(60_000, true, false))
        s.onFetchStarted(); s.onFetchResult(60_000, BannerState.Result.Error)
        assertFalse(s.shouldFetch(74_999, true, true))
        assertTrue(s.shouldFetch(75_000, true, true))
        assertEquals(15_000L, BannerState.backoffMs(1))
        assertEquals(30_000L, BannerState.backoffMs(2))
        assertEquals(300_000L, BannerState.backoffMs(20))
    }

    @Test fun clickReportedOncePerAdWhileTokenValid() {
        val s = BannerState()
        assertFalse(s.consumeClick(0)) // no ad
        loaded(s, 0)
        assertTrue(s.consumeClick(1000))
        assertFalse(s.consumeClick(2000))
        val s2 = BannerState(); loaded(s2, 0)
        assertFalse(s2.consumeClick(56_000)) // expired token: just open the URL
    }

    @Test fun resetForgetsEverything() {
        val s = BannerState()
        loaded(s, 0)
        s.reset()
        assertNull(s.ad)
        assertTrue(s.shouldFetch(1, true, false))
    }
}
