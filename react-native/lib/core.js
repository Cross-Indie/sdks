"use strict";
// Platform-agnostic logic for the CrossIndie React Native SDK: URL building,
// the ad fetch, impression / click tracking and the visibility dwell timer.
// No React Native imports here, so it is unit-testable in plain Node.
Object.defineProperty(exports, "__esModule", { value: true });
exports.DwellTracker = exports.CrossIndieError = exports.VERSION = exports.DEFAULT_API_BASE = void 0;
exports.normalizeBase = normalizeBase;
exports.buildFetchUrl = buildFetchUrl;
exports.resolveMedia = resolveMedia;
exports.parseAd = parseAd;
exports.fetchAd = fetchAd;
exports.trackEvent = trackEvent;
exports.visibleFraction = visibleFraction;
exports.isOnScreen = isOnScreen;
exports.DEFAULT_API_BASE = "https://api.crossindie.com";
exports.VERSION = "1.0.0";
function normalizeBase(apiBase) {
    return (apiBase || exports.DEFAULT_API_BASE).replace(/\/+$/, "");
}
function buildFetchUrl(p) {
    const q = [
        ["app_id", p.appId],
        ["category", p.category],
        ["platform", p.platform],
    ];
    if (p.lang)
        q.push(["lang", p.lang]);
    if (p.country)
        q.push(["country", p.country]);
    if (p.packageName)
        q.push(["package", p.packageName]);
    const qs = q.map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join("&");
    return `${normalizeBase(p.apiBase)}/api/v1/ad/fetch?${qs}`;
}
/** Media may come back as a relative "/media/..." path: resolve it against the API. */
function resolveMedia(apiBase, url) {
    return url && url.charAt(0) === "/" ? normalizeBase(apiBase) + url : url;
}
class CrossIndieError extends Error {
    constructor(message, status) {
        super(message);
        this.name = "CrossIndieError";
        this.status = status;
    }
}
exports.CrossIndieError = CrossIndieError;
function getFetch(f) {
    const g = f || (typeof fetch === "function" ? fetch : undefined);
    if (!g)
        throw new CrossIndieError("fetch is not available");
    return g;
}
function withTimeout(p, ms) {
    return new Promise((resolve, reject) => {
        const t = setTimeout(() => reject(new CrossIndieError("request timed out")), ms);
        p.then((v) => {
            clearTimeout(t);
            resolve(v);
        }, (e) => {
            clearTimeout(t);
            reject(e);
        });
    });
}
function str(v) {
    return typeof v === "string" ? v : v == null ? "" : String(v);
}
function parseAd(json) {
    if (!json || typeof json !== "object")
        throw new CrossIndieError("invalid ad payload");
    const min = Number(json.min_display_ms);
    const ad = {
        ad_id: str(json.ad_id),
        name: str(json.name),
        description: str(json.description),
        target_url: str(json.target_url),
        banner_image_url: str(json.banner_image_url),
        tracking_token: str(json.tracking_token),
        min_display_ms: Number.isFinite(min) && min > 0 ? min : 1500,
    };
    if (!ad.tracking_token)
        throw new CrossIndieError("invalid ad payload: no tracking_token");
    return ad;
}
/** Fetch one eligible ad. Resolves null when the network has none (204). */
async function fetchAd(p, opts = {}) {
    var _a;
    const f = getFetch(opts.fetchImpl);
    let res;
    try {
        res = await withTimeout(f(buildFetchUrl(p), { headers: { Accept: "application/json" } }), (_a = opts.timeoutMs) !== null && _a !== void 0 ? _a : 10000);
    }
    catch (e) {
        throw new CrossIndieError("fetch failed: " + (e && e.message ? e.message : e));
    }
    if (res.status === 204)
        return null;
    if (!res.ok)
        throw new CrossIndieError(`fetch failed (HTTP ${res.status})`, res.status);
    let json;
    try {
        json = await res.json();
    }
    catch {
        throw new CrossIndieError("invalid ad payload");
    }
    return parseAd(json);
}
/**
 * Report an impression or click via POST /api/v1/ad/track. A 425 ("too
 * early") does not burn the token, so it is retried once. Never throws;
 * resolves true when the server accepted the event.
 */
async function trackEvent(apiBase, trackingToken, eventType, opts = {}) {
    var _a;
    for (let attempt = 0; attempt < 2; attempt++) {
        try {
            const f = getFetch(opts.fetchImpl);
            const res = await withTimeout(f(`${normalizeBase(apiBase)}/api/v1/ad/track`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ tracking_token: trackingToken, event_type: eventType }),
            }), (_a = opts.timeoutMs) !== null && _a !== void 0 ? _a : 10000);
            if (res.status === 425 && attempt === 0) {
                await new Promise((r) => { var _a; return setTimeout(r, (_a = opts.retryDelayMs) !== null && _a !== void 0 ? _a : 1000); });
                continue;
            }
            return res.ok;
        }
        catch {
            return false;
        }
    }
    return false;
}
/** Fraction (0..1) of `box` inside `clip`. Zero for an empty box. */
function visibleFraction(box, clip) {
    if (!(box.width > 0) || !(box.height > 0))
        return 0;
    const left = Math.max(box.x, clip.x);
    const top = Math.max(box.y, clip.y);
    const right = Math.min(box.x + box.width, clip.x + clip.width);
    const bottom = Math.min(box.y + box.height, clip.y + clip.height);
    const w = right - left;
    const h = bottom - top;
    if (w <= 0 || h <= 0)
        return 0;
    return (w * h) / (box.width * box.height);
}
/** Visible = non-zero size and at least half of it inside the window. */
function isOnScreen(box, windowSize) {
    return visibleFraction(box, { x: 0, y: 0, width: windowSize.width, height: windowSize.height }) >= 0.5;
}
/**
 * Continuous-visibility timer. Feed it samples; it returns true exactly once,
 * when the banner has been visible without a gap for `minMs`. Any invisible
 * sample resets the streak (same rule as the web widget).
 */
class DwellTracker {
    constructor(minMs) {
        this.minMs = minMs;
        this.since = null;
        this.fired = false;
    }
    sample(visible, now) {
        if (this.fired)
            return false;
        if (!visible) {
            this.since = null;
            return false;
        }
        if (this.since === null) {
            this.since = now;
            return false;
        }
        if (now - this.since >= this.minMs) {
            this.fired = true;
            return true;
        }
        return false;
    }
    get done() {
        return this.fired;
    }
}
exports.DwellTracker = DwellTracker;
