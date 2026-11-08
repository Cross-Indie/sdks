import Foundation

/// One ad served by `GET /api/v1/ad/fetch`.
public struct CrossIndieAd: Equatable {
    public let adId: String
    public let name: String
    public let description: String
    public let targetURL: String
    public let bannerImageURL: String
    public let videoURL: String
    public let trackingToken: String
    public let minDisplayMs: Int64

    /// Same default as the web / Unity / Godot SDKs when the server omits it.
    public static let defaultMinDisplayMs: Int64 = 1500

    public init(adId: String, name: String, description: String, targetURL: String,
                bannerImageURL: String, videoURL: String, trackingToken: String, minDisplayMs: Int64) {
        self.adId = adId
        self.name = name
        self.description = description
        self.targetURL = targetURL
        self.bannerImageURL = bannerImageURL
        self.videoURL = videoURL
        self.trackingToken = trackingToken
        self.minDisplayMs = minDisplayMs
    }

    /// Parse a fetch response body. Relative media ("/media/...") is resolved
    /// against `apiBase`. Returns nil for an invalid payload (no tracking token
    /// or no target URL); never throws.
    public static func parse(_ data: Data, apiBase: String) -> CrossIndieAd? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func str(_ key: String) -> String { (obj[key] as? String) ?? "" }
        let token = str("tracking_token")
        let target = str("target_url")
        guard !token.isEmpty, !target.isEmpty else { return nil }
        var minMs = defaultMinDisplayMs
        if let n = obj["min_display_ms"] as? NSNumber, n.int64Value > 0 { minMs = n.int64Value }
        return CrossIndieAd(
            adId: str("ad_id"),
            name: str("name"),
            description: str("description"),
            targetURL: target,
            bannerImageURL: resolveMedia(apiBase: apiBase, str("banner_image_url")),
            videoURL: resolveMedia(apiBase: apiBase, str("video_url")),
            trackingToken: token,
            minDisplayMs: minMs
        )
    }

    /// "/media/x.png" -> "https://api.crossindie.com/media/x.png"; absolute URLs pass through.
    public static func resolveMedia(apiBase: String, _ url: String) -> String {
        let u = url.trimmingCharacters(in: .whitespaces)
        if u.isEmpty { return "" }
        return u.hasPrefix("/") ? normalizeBase(apiBase) + u : u
    }

    public static func normalizeBase(_ apiBase: String) -> String {
        var s = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

/// Request builders for the public ad API (pure functions, unit-tested).
public enum AdRequests {
    private static let allowed: CharacterSet = {
        var c = CharacterSet.alphanumerics
        c.insert(charactersIn: "-._~")
        return c
    }()

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// `platform` + `package` feed the dashboard's "SDK active" heartbeat and
    /// let the network confirm the SDK runs inside the store app.
    public static func fetchURL(apiBase: String, appId: String, category: String, bundleId: String,
                                lang: String?, country: String?, video: Bool,
                                platform: String = "ios") -> String {
        var s = CrossIndieAd.normalizeBase(apiBase)
        s += "/api/v1/ad/fetch?app_id=" + enc(appId.trimmingCharacters(in: .whitespaces))
        s += "&category=" + enc(category.isEmpty ? "game" : category)
        s += "&platform=" + enc(platform)
        if !bundleId.isEmpty { s += "&package=" + enc(bundleId) }
        if let l = lang, !l.isEmpty { s += "&lang=" + enc(String(l.prefix(2)).lowercased()) }
        if let c = country, !c.isEmpty { s += "&country=" + enc(c.uppercased()) }
        if video { s += "&video=1" }
        return s
    }

    public static func trackURL(apiBase: String) -> String {
        CrossIndieAd.normalizeBase(apiBase) + "/api/v1/ad/track"
    }

    /// `{"tracking_token": ..., "event_type": "impression" | "click"}`
    public static func trackBody(token: String, eventType: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["tracking_token": token, "event_type": eventType])) ?? Data()
    }
}
