// Type definitions for the CrossIndie Web SDK.

export type CrossIndieCategory = "game" | "web_tool" | "saas" | "mobile_app";

/** Standard banner slot formats. */
export type CrossIndieFormat =
  | "card" // 320px, image + title + description
  | "rectangle" // 300x250 medium rectangle
  | "leaderboard" // 728x90 horizontal
  | "mobile" // 320x50 compact
  | "text"; // no image

export interface CreateBannerOptions {
  /** Target element or its id / CSS selector. Defaults to "crossindie-banner". */
  el?: string | HTMLElement;
  /** Your app id from the CrossIndie dashboard. */
  appId: string;
  /** Category pool to request. Defaults to "game". */
  category?: CrossIndieCategory;
  /** Banner format / size. Defaults to "card". */
  format?: CrossIndieFormat;
  /** Viewer language for targeting (2-letter). Defaults to navigator.language. */
  lang?: string;
  /** Viewer country code for targeting (e.g. "US"). */
  country?: string;
  /** Base URL of your CrossIndie backend, e.g. "https://api.crossindie.dev". */
  apiBase: string;
  /** Called on fetch/render errors instead of console.warn. */
  onError?: (err: Error) => void;
}

export interface CrossIndieSDK {
  /** Fetch one eligible ad and render it into one slot. Resolves true if shown.
   *  Each call is an independent earning slot: place more to earn more. */
  createBanner(opts: CreateBannerOptions): Promise<boolean>;
  /** Initialise every [data-ci-app-id] slot element on the page. */
  initSlots(defaultApiBase?: string): void;
  /** Available format names. */
  readonly formats: CrossIndieFormat[];
  readonly version: string;
}

declare global {
  interface Window {
    CrossIndie: CrossIndieSDK;
  }
}

export {};
