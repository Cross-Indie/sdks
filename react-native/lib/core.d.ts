export declare const DEFAULT_API_BASE = "https://api.crossindie.com";
export declare const VERSION = "1.0.0";
export type CrossIndieCategory = "game" | "web_tool" | "saas" | "mobile_app";
/** Standard slot formats, identical to the web widget. */
export type CrossIndieFormat = "card" | "rectangle" | "leaderboard" | "mobile" | "text";
/** One ad as returned by GET /api/v1/ad/fetch. */
export interface CrossIndieAd {
    ad_id: string;
    name: string;
    description: string;
    target_url: string;
    banner_image_url: string;
    tracking_token: string;
    /** Server-mandated minimum visible time before an impression counts. */
    min_display_ms: number;
}
export interface FetchParams {
    apiBase?: string;
    appId: string;
    category: CrossIndieCategory;
    /** e.g. "react-native-android" */
    platform: string;
    packageName?: string;
    lang?: string;
    country?: string;
}
export declare function normalizeBase(apiBase?: string): string;
export declare function buildFetchUrl(p: FetchParams): string;
/** Media may come back as a relative "/media/..." path: resolve it against the API. */
export declare function resolveMedia(apiBase: string | undefined, url: string): string;
export declare class CrossIndieError extends Error {
    status?: number;
    constructor(message: string, status?: number);
}
type FetchLike = (url: string, init?: any) => Promise<{
    status: number;
    ok: boolean;
    json(): Promise<any>;
}>;
export declare function parseAd(json: any): CrossIndieAd;
/** Fetch one eligible ad. Resolves null when the network has none (204). */
export declare function fetchAd(p: FetchParams, opts?: {
    fetchImpl?: FetchLike;
    timeoutMs?: number;
}): Promise<CrossIndieAd | null>;
/**
 * Report an impression or click via POST /api/v1/ad/track. A 425 ("too
 * early") does not burn the token, so it is retried once. Never throws;
 * resolves true when the server accepted the event.
 */
export declare function trackEvent(apiBase: string | undefined, trackingToken: string, eventType: "impression" | "click", opts?: {
    fetchImpl?: FetchLike;
    retryDelayMs?: number;
    timeoutMs?: number;
}): Promise<boolean>;
export interface Rect {
    x: number;
    y: number;
    width: number;
    height: number;
}
/** Fraction (0..1) of `box` inside `clip`. Zero for an empty box. */
export declare function visibleFraction(box: Rect, clip: Rect): number;
/** Visible = non-zero size and at least half of it inside the window. */
export declare function isOnScreen(box: Rect, windowSize: {
    width: number;
    height: number;
}): boolean;
/**
 * Continuous-visibility timer. Feed it samples; it returns true exactly once,
 * when the banner has been visible without a gap for `minMs`. Any invisible
 * sample resets the streak (same rule as the web widget).
 */
export declare class DwellTracker {
    readonly minMs: number;
    private since;
    private fired;
    constructor(minMs: number);
    sample(visible: boolean, now: number): boolean;
    get done(): boolean;
}
export {};
