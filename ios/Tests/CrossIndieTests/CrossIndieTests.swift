import XCTest
@testable import CrossIndie

final class AdParsingTests: XCTestCase {
    let base = "https://api.crossindie.com/"

    func testParsesFullPayloadAndResolvesRelativeMedia() throws {
        let json = """
        {"ad_id":"a1","name":"Cool Game","description":"Jump!","category":"game",
         "target_url":"https://apps.apple.com/app/id1?ci_ref=r","banner_image_url":"/media/b.png",
         "video_url":"https://cdn.x/v.mp4","video_ogv_url":"","tracking_token":"tok","min_display_ms":1500}
        """
        let ad = try XCTUnwrap(CrossIndieAd.parse(Data(json.utf8), apiBase: base))
        XCTAssertEqual(ad.name, "Cool Game")
        XCTAssertEqual(ad.description, "Jump!")
        XCTAssertEqual(ad.bannerImageURL, "https://api.crossindie.com/media/b.png")
        XCTAssertEqual(ad.videoURL, "https://cdn.x/v.mp4")
        XCTAssertEqual(ad.trackingToken, "tok")
        XCTAssertEqual(ad.minDisplayMs, 1500)
    }

    func testDefaultsAndInvalidPayloads() {
        let ad = CrossIndieAd.parse(Data(#"{"target_url":"https://x","tracking_token":"t","min_display_ms":0}"#.utf8), apiBase: base)
        XCTAssertEqual(ad?.minDisplayMs, CrossIndieAd.defaultMinDisplayMs)
        XCTAssertEqual(ad?.bannerImageURL, "")
        XCTAssertNil(CrossIndieAd.parse(Data("nope".utf8), apiBase: base))
        XCTAssertNil(CrossIndieAd.parse(Data(#"{"target_url":"https://x"}"#.utf8), apiBase: base))
        XCTAssertNil(CrossIndieAd.parse(Data(#"{"tracking_token":"t"}"#.utf8), apiBase: base))
        XCTAssertNil(CrossIndieAd.parse(Data("[]".utf8), apiBase: base))
    }

    func testFetchURLCarriesPlatformBundleIdAndOptions() {
        let url = AdRequests.fetchURL(apiBase: "https://api.crossindie.com/", appId: "abc-123",
                                      category: "mobile_app", bundleId: "com.dev.app",
                                      lang: "tr-TR", country: "tr", video: true)
        XCTAssertEqual(url, "https://api.crossindie.com/api/v1/ad/fetch?app_id=abc-123&category=mobile_app"
            + "&platform=ios&package=com.dev.app&lang=tr&country=TR&video=1")
        XCTAssertEqual(AdRequests.fetchURL(apiBase: "https://h", appId: "id", category: "", bundleId: "",
                                           lang: nil, country: nil, video: false),
                       "https://h/api/v1/ad/fetch?app_id=id&category=game&platform=ios")
    }

    func testTrackRequestMatchesBackendSchema() throws {
        XCTAssertEqual(AdRequests.trackURL(apiBase: "https://h/"), "https://h/api/v1/ad/track")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(
            with: AdRequests.trackBody(token: "tok", eventType: "impression")) as? [String: String])
        XCTAssertEqual(body, ["tracking_token": "tok", "event_type": "impression"])
    }

    func testFormatParsing() {
        XCTAssertEqual(CrossIndieFormat(apiName: "Card"), .card)
        XCTAssertEqual(CrossIndieFormat(apiName: nil), .mobile)
        XCTAssertEqual(CrossIndieFormat(apiName: "bogus"), .mobile)
    }
}

final class VisibilityTests: XCTestCase {
    func testRequiresNonZeroSizeAndHalfVisible() {
        XCTAssertFalse(Visibility.isViewable(visibleWidth: 0, visibleHeight: 0, width: 0, height: 0))
        XCTAssertFalse(Visibility.isViewable(visibleWidth: 100, visibleHeight: 50, width: 0, height: 50))
        XCTAssertTrue(Visibility.isViewable(visibleWidth: 100, visibleHeight: 50, width: 100, height: 50))
        XCTAssertTrue(Visibility.isViewable(visibleWidth: 100, visibleHeight: 25, width: 100, height: 50))
        XCTAssertFalse(Visibility.isViewable(visibleWidth: 100, visibleHeight: 24, width: 100, height: 50))
        XCTAssertEqual(Visibility.fraction(visibleWidth: 500, visibleHeight: 500, width: 100, height: 50), 1)
    }
}

final class BannerStateTests: XCTestCase {
    func ad(_ min: Int64 = 1500) -> CrossIndieAd {
        CrossIndieAd(adId: "id", name: "n", description: "d", targetURL: "https://x",
                     bannerImageURL: "", videoURL: "", trackingToken: "tok", minDisplayMs: min)
    }

    func loaded(_ s: BannerState, at now: Int64) {
        s.onFetchStarted()
        s.onFetchResult(now: now, .loaded(ad()))
        s.onRendered()
    }

    func testFirstFetchNeedsOnlyOnScreen() {
        let s = BannerState()
        XCTAssertFalse(s.shouldFetch(now: 0, onScreen: false, viewable: false))
        XCTAssertTrue(s.shouldFetch(now: 0, onScreen: true, viewable: false))
        s.onFetchStarted()
        XCTAssertFalse(s.shouldFetch(now: 0, onScreen: true, viewable: true))
    }

    func testImpressionAfterContinuousVisibilityOnlyOnce() {
        let s = BannerState()
        loaded(s, at: 0)
        XCTAssertFalse(s.tick(now: 0, viewable: true))
        XCTAssertFalse(s.tick(now: 1000, viewable: true))
        XCTAssertTrue(s.tick(now: 1500, viewable: true))
        XCTAssertFalse(s.tick(now: 3000, viewable: true))
    }

    func testGoingOutOfViewResetsDwell() {
        let s = BannerState()
        loaded(s, at: 0)
        _ = s.tick(now: 0, viewable: true)
        _ = s.tick(now: 1400, viewable: true)
        _ = s.tick(now: 1450, viewable: false)
        XCTAssertFalse(s.tick(now: 1500, viewable: true))
        XCTAssertFalse(s.tick(now: 2900, viewable: true))
        XCTAssertTrue(s.tick(now: 3000, viewable: true))
    }

    func testNeverCountsBeforeRenderOrWhileHidden() {
        let s = BannerState()
        s.onFetchStarted()
        s.onFetchResult(now: 0, .loaded(ad()))
        XCTAssertFalse(s.tick(now: 5000, viewable: true))
        s.onRendered()
        for t in stride(from: Int64(5000), through: 20000, by: 250) {
            XCTAssertFalse(s.tick(now: t, viewable: false))
        }
    }

    func testStaleTokenRefetchedOnlyWhenViewable() {
        let s = BannerState()
        loaded(s, at: 0)
        XCTAssertFalse(s.shouldFetch(now: 30_000, onScreen: true, viewable: true))
        XCTAssertFalse(s.shouldFetch(now: 56_000, onScreen: true, viewable: false))
        XCTAssertTrue(s.shouldFetch(now: 56_000, onScreen: true, viewable: true))
        _ = s.tick(now: 55_000, viewable: true)
        XCTAssertFalse(s.tick(now: 57_000, viewable: true))
    }

    func testRotatesAfterImpression() {
        let s = BannerState(refreshSeconds: 30)
        loaded(s, at: 0)
        _ = s.tick(now: 0, viewable: true)
        XCTAssertTrue(s.tick(now: 1500, viewable: true))
        XCTAssertFalse(s.shouldFetch(now: 29_000, onScreen: true, viewable: true))
        XCTAssertTrue(s.shouldFetch(now: 30_000, onScreen: true, viewable: true))
        XCTAssertFalse(s.shouldFetch(now: 30_000, onScreen: true, viewable: false))
        s.onFetchStarted()
        s.onFetchResult(now: 30_000, .loaded(ad()))
        XCTAssertFalse(s.impressionSent)
    }

    func testRefreshClampAndDisable() {
        XCTAssertEqual(BannerState.refreshMs(for: 0), 0)
        XCTAssertEqual(BannerState.refreshMs(for: 5), 15_000)
        XCTAssertEqual(BannerState.refreshMs(for: 60), 60_000)
        let s = BannerState(refreshSeconds: 0)
        loaded(s, at: 0)
        _ = s.tick(now: 0, viewable: true)
        _ = s.tick(now: 1500, viewable: true)
        XCTAssertFalse(s.shouldFetch(now: 600_000, onScreen: true, viewable: true))
    }

    func testNoFillAndErrorBackoff() {
        let s = BannerState()
        s.onFetchStarted(); s.onFetchResult(now: 0, .noFill)
        XCTAssertFalse(s.shouldFetch(now: 59_999, onScreen: true, viewable: true))
        XCTAssertTrue(s.shouldFetch(now: 60_000, onScreen: true, viewable: false))
        s.onFetchStarted(); s.onFetchResult(now: 60_000, .error)
        XCTAssertFalse(s.shouldFetch(now: 74_999, onScreen: true, viewable: true))
        XCTAssertTrue(s.shouldFetch(now: 75_000, onScreen: true, viewable: true))
        XCTAssertEqual(BannerState.backoffMs(failures: 1), 15_000)
        XCTAssertEqual(BannerState.backoffMs(failures: 2), 30_000)
        XCTAssertEqual(BannerState.backoffMs(failures: 20), 300_000)
    }

    func testClickReportedOncePerAdWhileTokenValid() {
        let s = BannerState()
        XCTAssertFalse(s.consumeClick(now: 0))
        loaded(s, at: 0)
        XCTAssertTrue(s.consumeClick(now: 1000))
        XCTAssertFalse(s.consumeClick(now: 2000))
        let s2 = BannerState()
        loaded(s2, at: 0)
        XCTAssertFalse(s2.consumeClick(now: 56_000))
    }
}
