import {
  DwellTracker,
  buildFetchUrl,
  fetchAd,
  isOnScreen,
  resolveMedia,
  trackEvent,
  visibleFraction,
} from "../src/core";

const AD = {
  ad_id: "a1",
  name: "Hyperbase",
  description: "The instant backend",
  category: "saas",
  target_url: "https://example.com/?ci_ref=r1",
  banner_image_url: "/media/a.png",
  video_url: "",
  video_ogv_url: "",
  tracking_token: "tok-1",
  min_display_ms: 1500,
};

function res(status: number, body?: unknown) {
  return Promise.resolve({
    status,
    ok: status >= 200 && status < 300,
    json: () => Promise.resolve(body),
  });
}

describe("buildFetchUrl", () => {
  it("defaults to api.crossindie.com and sends platform + package", () => {
    const url = buildFetchUrl({
      appId: "app 1",
      category: "mobile_app",
      platform: "react-native-android",
      packageName: "com.example.app",
      lang: "de",
      country: "DE",
    });
    expect(url).toBe(
      "https://api.crossindie.com/api/v1/ad/fetch?app_id=app%201&category=mobile_app" +
        "&platform=react-native-android&lang=de&country=DE&package=com.example.app"
    );
  });

  it("strips trailing slashes and omits empty optionals", () => {
    const url = buildFetchUrl({
      apiBase: "https://api.example.com//",
      appId: "x",
      category: "game",
      platform: "react-native-ios",
    });
    expect(url).toBe("https://api.example.com/api/v1/ad/fetch?app_id=x&category=game&platform=react-native-ios");
  });
});

describe("resolveMedia", () => {
  it("resolves relative media against the API base", () => {
    expect(resolveMedia(undefined, "/media/a.png")).toBe("https://api.crossindie.com/media/a.png");
    expect(resolveMedia("https://x.dev/", "https://cdn/b.png")).toBe("https://cdn/b.png");
  });
});

describe("fetchAd", () => {
  const p = { appId: "x", category: "game" as const, platform: "react-native-ios" };

  it("parses an ad", async () => {
    const ad = await fetchAd(p, { fetchImpl: () => res(200, AD) });
    expect(ad).toMatchObject({ name: "Hyperbase", tracking_token: "tok-1", min_display_ms: 1500 });
  });

  it("returns null on 204", async () => {
    expect(await fetchAd(p, { fetchImpl: () => res(204) })).toBeNull();
  });

  it("rejects on HTTP errors, network errors and bad payloads", async () => {
    await expect(fetchAd(p, { fetchImpl: () => res(403) })).rejects.toThrow("HTTP 403");
    await expect(fetchAd(p, { fetchImpl: () => Promise.reject(new Error("offline")) })).rejects.toThrow("offline");
    await expect(fetchAd(p, { fetchImpl: () => res(200, { name: "no token" }) })).rejects.toThrow("tracking_token");
  });

  it("falls back to 1500 ms when min_display_ms is missing", async () => {
    const ad = await fetchAd(p, { fetchImpl: () => res(200, { ...AD, min_display_ms: undefined }) });
    expect(ad!.min_display_ms).toBe(1500);
  });
});

describe("trackEvent", () => {
  it("posts the token and event type", async () => {
    const calls: any[] = [];
    const ok = await trackEvent(undefined, "tok-1", "impression", {
      fetchImpl: (url, init) => {
        calls.push({ url, init });
        return res(200, {});
      },
    });
    expect(ok).toBe(true);
    expect(calls[0].url).toBe("https://api.crossindie.com/api/v1/ad/track");
    expect(calls[0].init.method).toBe("POST");
    expect(JSON.parse(calls[0].init.body)).toEqual({ tracking_token: "tok-1", event_type: "impression" });
  });

  it("retries once on 425 (too early)", async () => {
    let n = 0;
    const ok = await trackEvent(undefined, "t", "impression", {
      retryDelayMs: 0,
      fetchImpl: () => res(++n === 1 ? 425 : 200),
    });
    expect(ok).toBe(true);
    expect(n).toBe(2);
  });

  it("never throws", async () => {
    await expect(
      trackEvent(undefined, "t", "click", { fetchImpl: () => Promise.reject(new Error("x")) })
    ).resolves.toBe(false);
    await expect(trackEvent(undefined, "t", "click", { fetchImpl: () => res(409) })).resolves.toBe(false);
  });
});

describe("visibility", () => {
  const win = { width: 400, height: 800 };

  it("computes the visible fraction", () => {
    expect(visibleFraction({ x: 0, y: 0, width: 100, height: 100 }, { x: 0, y: 0, ...win })).toBe(1);
    expect(visibleFraction({ x: 0, y: 750, width: 100, height: 100 }, { x: 0, y: 0, ...win })).toBe(0.5);
    expect(visibleFraction({ x: 0, y: 0, width: 0, height: 0 }, { x: 0, y: 0, ...win })).toBe(0);
  });

  it("needs non-zero size and at least 50% on screen", () => {
    expect(isOnScreen({ x: 0, y: 740, width: 320, height: 100 }, win)).toBe(true);
    expect(isOnScreen({ x: 0, y: 760, width: 320, height: 100 }, win)).toBe(false);
    expect(isOnScreen({ x: 0, y: -1000, width: 320, height: 100 }, win)).toBe(false);
    expect(isOnScreen({ x: 0, y: 10, width: 0, height: 50 }, win)).toBe(false);
  });
});

describe("DwellTracker", () => {
  it("fires once after continuous visibility for minMs", () => {
    const d = new DwellTracker(1500);
    expect(d.sample(true, 0)).toBe(false);
    expect(d.sample(true, 1000)).toBe(false);
    expect(d.sample(true, 1500)).toBe(true);
    expect(d.sample(true, 5000)).toBe(false);
    expect(d.done).toBe(true);
  });

  it("resets the streak on any invisible sample", () => {
    const d = new DwellTracker(1500);
    d.sample(true, 0);
    d.sample(true, 1400);
    d.sample(false, 1450);
    expect(d.sample(true, 1600)).toBe(false);
    expect(d.sample(true, 3000)).toBe(false);
    expect(d.sample(true, 3100)).toBe(true);
  });

  it("never fires while invisible", () => {
    const d = new DwellTracker(1500);
    for (let t = 0; t < 10000; t += 250) expect(d.sample(false, t)).toBe(false);
  });
});
