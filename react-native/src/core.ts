// Platform-agnostic logic for the CrossIndie React Native SDK: URL building,
// the ad fetch, impression / click tracking and the visibility dwell timer.
// No React Native imports here, so it is unit-testable in plain Node.

export const DEFAULT_API_BASE = "https://api.crossindie.com";
export const VERSION = "1.0.0";

export type CrossIndieCategory = "game" | "web_tool" | "saas" | "mobile_app";

/** Standard slot formats, identical to the web widget. */
export type CrossIndieFormat =
  | "card" // 320 wide, 16:9 image + title + description
  | "rectangle" // 300 x 250
  | "leaderboard" // 728 x 90
  | "mobile" // 320 x 50
  | "text"; // no image

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

export function normalizeBase(apiBase?: string): string {
  return (apiBase || DEFAULT_API_BASE).replace(/\/+$/, "");
}

export function buildFetchUrl(p: FetchParams): string {
  const q: [string, string][] = [
    ["app_id", p.appId],
    ["category", p.category],
    ["platform", p.platform],
  ];
  if (p.lang) q.push(["lang", p.lang]);
  if (p.country) q.push(["country", p.country]);
  if (p.packageName) q.push(["package", p.packageName]);
  const qs = q.map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join("&");
  return `${normalizeBase(p.apiBase)}/api/v1/ad/fetch?${qs}`;
}

/** Media may come back as a relative "/media/..." path: resolve it against the API. */
export function resolveMedia(apiBase: string | undefined, url: string): string {
  return url && url.charAt(0) === "/" ? normalizeBase(apiBase) + url : url;
}

export class CrossIndieError extends Error {
  status?: number;
  constructor(message: string, status?: number) {
    super(message);
    this.name = "CrossIndieError";
    this.status = status;
  }
}

type FetchLike = (url: string, init?: any) => Promise<{
  status: number;
  ok: boolean;
  json(): Promise<any>;
}>;

function getFetch(f?: FetchLike): FetchLike {
  const g = f || (typeof fetch === "function" ? (fetch as unknown as FetchLike) : undefined);
  if (!g) throw new CrossIndieError("fetch is not available");
  return g;
}

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new CrossIndieError("request timed out")), ms);
    p.then(
      (v) => {
        clearTimeout(t);
        resolve(v);
      },
      (e) => {
        clearTimeout(t);
        reject(e);
      }
    );
  });
}

function str(v: unknown): string {
  return typeof v === "string" ? v : v == null ? "" : String(v);
}

export function parseAd(json: any): CrossIndieAd {
  if (!json || typeof json !== "object") throw new CrossIndieError("invalid ad payload");
  const min = Number(json.min_display_ms);
  const ad: CrossIndieAd = {
    ad_id: str(json.ad_id),
    name: str(json.name),
    description: str(json.description),
    target_url: str(json.target_url),
    banner_image_url: str(json.banner_image_url),
    tracking_token: str(json.tracking_token),
    min_display_ms: Number.isFinite(min) && min > 0 ? min : 1500,
  };
  if (!ad.tracking_token) throw new CrossIndieError("invalid ad payload: no tracking_token");
  return ad;
}

/** Fetch one eligible ad. Resolves null when the network has none (204). */
export async function fetchAd(
  p: FetchParams,
  opts: { fetchImpl?: FetchLike; timeoutMs?: number } = {}
): Promise<CrossIndieAd | null> {
  const f = getFetch(opts.fetchImpl);
  let res;
  try {
    res = await withTimeout(
      f(buildFetchUrl(p), { headers: { Accept: "application/json" } }),
      opts.timeoutMs ?? 10000
    );
  } catch (e: any) {
    throw new CrossIndieError("fetch failed: " + (e && e.message ? e.message : e));
  }
  if (res.status === 204) return null;
  if (!res.ok) throw new CrossIndieError(`fetch failed (HTTP ${res.status})`, res.status);
  let json;
  try {
    json = await res.json();
  } catch {
    throw new CrossIndieError("invalid ad payload");
  }
  return parseAd(json);
}

/**
 * Report an impression or click via POST /api/v1/ad/track. A 425 ("too
 * early") does not burn the token, so it is retried once. Never throws;
 * resolves true when the server accepted the event.
 */
export async function trackEvent(
  apiBase: string | undefined,
  trackingToken: string,
  eventType: "impression" | "click",
  opts: { fetchImpl?: FetchLike; retryDelayMs?: number; timeoutMs?: number } = {}
): Promise<boolean> {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const f = getFetch(opts.fetchImpl);
      const res = await withTimeout(
        f(`${normalizeBase(apiBase)}/api/v1/ad/track`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ tracking_token: trackingToken, event_type: eventType }),
        }),
        opts.timeoutMs ?? 10000
      );
      if (res.status === 425 && attempt === 0) {
        await new Promise((r) => setTimeout(r, opts.retryDelayMs ?? 1000));
        continue;
      }
      return res.ok;
    } catch {
      return false;
    }
  }
  return false;
}

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** Fraction (0..1) of `box` inside `clip`. Zero for an empty box. */
export function visibleFraction(box: Rect, clip: Rect): number {
  if (!(box.width > 0) || !(box.height > 0)) return 0;
  const left = Math.max(box.x, clip.x);
  const top = Math.max(box.y, clip.y);
  const right = Math.min(box.x + box.width, clip.x + clip.width);
  const bottom = Math.min(box.y + box.height, clip.y + clip.height);
  const w = right - left;
  const h = bottom - top;
  if (w <= 0 || h <= 0) return 0;
  return (w * h) / (box.width * box.height);
}

/** Visible = non-zero size and at least half of it inside the window. */
export function isOnScreen(box: Rect, windowSize: { width: number; height: number }): boolean {
  return visibleFraction(box, { x: 0, y: 0, width: windowSize.width, height: windowSize.height }) >= 0.5;
}

/**
 * Continuous-visibility timer. Feed it samples; it returns true exactly once,
 * when the banner has been visible without a gap for `minMs`. Any invisible
 * sample resets the streak (same rule as the web widget).
 */
export class DwellTracker {
  private since: number | null = null;
  private fired = false;
  constructor(public readonly minMs: number) {}

  sample(visible: boolean, now: number): boolean {
    if (this.fired) return false;
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

  get done(): boolean {
    return this.fired;
  }
}
