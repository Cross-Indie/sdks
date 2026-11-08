import Foundation

/// Background networking for the banner. URLSession (ephemeral: no cookies, no
/// cache on disk); completions are delivered on the main queue. Every failure
/// is swallowed - the SDK must never crash or block the host app.
enum AdClient {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.httpAdditionalHeaders = ["User-Agent": "CrossIndie-iOS/\(CrossIndie.version)"]
        return URLSession(configuration: c)
    }()

    private static let imageCache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.totalCostLimit = 8 * 1024 * 1024
        return c
    }()

    /// GET /api/v1/ad/fetch -> loaded / noFill (204) / error (anything else).
    static func fetchAd(url: String, apiBase: String, completion: @escaping (BannerState.Result) -> Void) {
        guard let u = URL(string: url) else {
            DispatchQueue.main.async { completion(.error) }
            return
        }
        var req = URLRequest(url: u)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: req) { data, response, error in
            var result = BannerState.Result.error
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code == 204 {
                result = .noFill
            } else if code == 200, let data = data, let ad = CrossIndieAd.parse(data, apiBase: apiBase) {
                result = .loaded(ad)
            } else {
                CrossIndie.log("ad fetch failed: HTTP \(code) \(error?.localizedDescription ?? "")"
                    + (code == 403 ? " (app pending review, not approved, or origin locked)" : ""))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// POST /api/v1/ad/track. A 425 ("too early") does not burn the token, so
    /// it is retried once after a second, as the backend allows.
    static func track(apiBase: String, token: String, eventType: String, retry: Bool = true) {
        guard let u = URL(string: AdRequests.trackURL(apiBase: apiBase)) else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = AdRequests.trackBody(token: token, eventType: eventType)
        session.dataTask(with: req) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code >= 400 || error != nil {
                CrossIndie.log("track \(eventType) -> HTTP \(code) \(error?.localizedDescription ?? "")")
            }
            if code == 425 && retry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    track(apiBase: apiBase, token: token, eventType: eventType, retry: false)
                }
            }
        }.resume()
    }

    /// Download image bytes (cached in memory). Decoding happens in the view.
    static func loadImageData(url: String, completion: @escaping (Data?) -> Void) {
        if let hit = imageCache.object(forKey: url as NSString) {
            completion(hit as Data)
            return
        }
        guard let u = URL(string: url) else {
            completion(nil)
            return
        }
        session.dataTask(with: u) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            var out: Data?
            if code == 200, let d = data, d.count <= 8 * 1024 * 1024 {
                imageCache.setObject(d as NSData, forKey: url as NSString, cost: d.count)
                out = d
            }
            DispatchQueue.main.async { completion(out) }
        }.resume()
    }
}
