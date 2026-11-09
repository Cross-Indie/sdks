import { useCallback, useEffect, useRef, useState } from "react";
import {
  AppState,
  Dimensions,
  Image,
  Linking,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import type { AppStateStatus, LayoutChangeEvent, StyleProp, ViewStyle } from "react-native";

import {
  CrossIndieAd,
  CrossIndieCategory,
  CrossIndieFormat,
  DwellTracker,
  fetchAd,
  isOnScreen,
  resolveMedia,
  trackEvent,
} from "./core";

declare const require: (id: string) => any;

export interface CrossIndieBannerProps {
  /** Your app id from the CrossIndie dashboard (public, not a secret). */
  appId: string;
  /** Category pool. Default "mobile_app". */
  category?: CrossIndieCategory;
  /** Slot format. Default "card". */
  format?: CrossIndieFormat;
  /** Backend base URL. Default "https://api.crossindie.com". */
  apiBase?: string;
  /** Android package name / iOS bundle id. Read automatically from
   *  expo-application when installed; pass it otherwise (optional). */
  packageName?: string;
  /** Viewer country (e.g. "US") for targeting. Optional. */
  country?: string;
  /** Viewer language (2 letters). Defaults to the device locale. */
  lang?: string;
  /** Show a small ✕ that dismisses the slot (a dismissed slot earns nothing). Default true. */
  closeable?: boolean;
  /** Set false while the screen is not focused (e.g. `useIsFocused()` from
   *  React Navigation) or the banner is covered. Default true. */
  visible?: boolean;
  /** Rotate to a new ad this many seconds after the impression counted
   *  (minimum 30). Off by default, like the other SDKs. */
  refreshSeconds?: number;
  style?: StyleProp<ViewStyle>;
  onAdLoaded?: (ad: CrossIndieAd) => void;
  onNoAd?: () => void;
  onImpression?: (ad: CrossIndieAd) => void;
  onClick?: (ad: CrossIndieAd) => void;
  onError?: (err: Error) => void;
}

type Spec = {
  w: number;
  h?: number;
  horizontal?: boolean;
  imgW?: number;
  imgH?: number;
  img?: boolean;
  desc?: boolean;
  badge?: boolean;
};

const SPECS: Record<CrossIndieFormat, Spec> = {
  card: { w: 320, desc: true, badge: true },
  rectangle: { w: 300, h: 250, imgH: 150, desc: true, badge: true },
  leaderboard: { w: 728, h: 90, horizontal: true, imgW: 150, desc: true, badge: true },
  mobile: { w: 320, h: 50, horizontal: true, imgW: 50, desc: false, badge: false },
  text: { w: 320, img: false, desc: true, badge: true },
};

const TICK_MS = 250;

let cachedPackage: string | undefined | null = null;

/** Bundle id via expo-application when the host app has it (optional dep). */
function detectPackage(): string | undefined {
  if (cachedPackage !== null) return cachedPackage;
  cachedPackage = undefined;
  try {
    // Metro treats a require inside try/catch as optional: no error when the
    // module is not installed.
    const mod = require("expo-application");
    const id = mod && (mod.applicationId as string | null | undefined);
    // Inside Expo Go the id is Expo Go's own, not the host app's.
    if (id && id !== "host.exp.Exponent") cachedPackage = id;
  } catch {
    // not installed
  }
  return cachedPackage || undefined;
}

function deviceLang(): string | undefined {
  try {
    const loc = Intl.DateTimeFormat().resolvedOptions().locale;
    return loc ? loc.slice(0, 2) : undefined;
  } catch {
    return undefined;
  }
}

/**
 * CrossIndie cross-promotion banner.
 *
 *   <CrossIndieBanner appId="YOUR_APP_ID" />
 *
 * Reports an impression only after the banner has been continuously visible
 * (non-zero size, at least 50% inside the window, app active, `visible` prop
 * true) for the server's minimum display time. A tap opens the ad in the
 * external browser and reports a click. Never throws into the host app.
 */
export function CrossIndieBanner(props: CrossIndieBannerProps) {
  const {
    appId,
    category = "mobile_app",
    format = "card",
    apiBase,
    country,
    closeable = true,
    style,
  } = props;

  const [ad, setAd] = useState<CrossIndieAd | null>(null);
  const [dismissed, setDismissed] = useState(false);
  const [generation, setGeneration] = useState(0);

  const viewRef = useRef<View>(null);
  const sizeRef = useRef({ width: 0, height: 0 });
  const appStateRef = useRef<AppStateStatus>(AppState.currentState);
  const propsRef = useRef(props);
  propsRef.current = props;
  const clickedRef = useRef(false);
  const refreshDueRef = useRef(false);

  const report = useCallback((e: unknown) => {
    try {
      const err = e instanceof Error ? e : new Error(String(e));
      if (propsRef.current.onError) propsRef.current.onError(err);
      else console.warn("[CrossIndie]", err.message);
    } catch {
      // never throw into the host
    }
  }, []);

  const safe = useCallback(
    (f: () => void) => {
      try {
        f();
      } catch (e) {
        report(e);
      }
    },
    [report]
  );

  // Track foreground / background.
  useEffect(() => {
    let sub: { remove(): void } | undefined;
    try {
      sub = AppState.addEventListener("change", (s) => {
        appStateRef.current = s;
      });
    } catch (e) {
      report(e);
    }
    return () => {
      try {
        sub && sub.remove();
      } catch {
        // ignore
      }
    };
  }, [report]);

  // Fetch (again on param change or rotation).
  useEffect(() => {
    if (dismissed) return;
    if (!appId || !appId.trim()) {
      report(new Error("appId is required"));
      return;
    }
    let cancelled = false;
    refreshDueRef.current = false;
    (async () => {
      try {
        const next = await fetchAd({
          apiBase,
          appId: appId.trim(),
          category,
          platform: `react-native-${Platform.OS}`,
          packageName: propsRef.current.packageName || detectPackage(),
          lang: propsRef.current.lang || deviceLang(),
          country,
        });
        if (cancelled) return;
        clickedRef.current = false;
        setAd(next);
        if (next) safe(() => propsRef.current.onAdLoaded?.(next));
        else safe(() => propsRef.current.onNoAd?.());
      } catch (e) {
        if (!cancelled) report(e); // keep a previous ad on a failed rotation
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [appId, category, apiBase, country, generation, dismissed, report, safe]);

  // Visibility polling: impression after continuous dwell, then optional rotation.
  useEffect(() => {
    if (!ad || dismissed) return;
    let refreshTimer: ReturnType<typeof setTimeout> | undefined;
    let measuring = false;
    const dwell = new DwellTracker(ad.min_display_ms);

    const check = (cb: (visible: boolean) => void) => {
      const p = propsRef.current;
      const sz = sizeRef.current;
      if (
        appStateRef.current !== "active" ||
        p.visible === false ||
        !(sz.width > 0 && sz.height > 0) ||
        !viewRef.current ||
        measuring
      ) {
        cb(false);
        return;
      }
      measuring = true;
      try {
        viewRef.current.measureInWindow((x, y, width, height) => {
          measuring = false;
          try {
            cb(isOnScreen({ x, y, width, height }, Dimensions.get("window")));
          } catch (e) {
            report(e);
          }
        });
      } catch (e) {
        measuring = false;
        report(e);
        cb(false);
      }
    };

    const interval = setInterval(() => {
      if (dwell.done && !refreshDueRef.current) return;
      check((visible) => {
        if (refreshDueRef.current) {
          if (visible) {
            refreshDueRef.current = false;
            setGeneration((g) => g + 1);
          }
          return;
        }
        if (dwell.sample(visible, Date.now())) {
          trackEvent(apiBase, ad.tracking_token, "impression").then((ok) => {
            if (ok) safe(() => propsRef.current.onImpression?.(ad));
          });
          const secs = propsRef.current.refreshSeconds;
          if (secs && secs > 0) {
            refreshTimer = setTimeout(() => {
              refreshDueRef.current = true;
            }, Math.max(30, secs) * 1000);
          }
        }
      });
    }, TICK_MS);

    return () => {
      clearInterval(interval);
      if (refreshTimer) clearTimeout(refreshTimer);
    };
  }, [ad, dismissed, apiBase, report, safe]);

  const open = useCallback(
    (url: string) => {
      Linking.openURL(url).catch(report);
    },
    [report]
  );

  const onPress = useCallback(() => {
    if (!ad || !ad.target_url) return;
    try {
      if (!clickedRef.current) {
        clickedRef.current = true;
        trackEvent(apiBase, ad.tracking_token, "click");
        safe(() => propsRef.current.onClick?.(ad));
      }
      open(ad.target_url);
    } catch (e) {
      report(e);
    }
  }, [ad, apiBase, open, report, safe]);

  const onLayout = useCallback((e: LayoutChangeEvent) => {
    const { width, height } = e.nativeEvent.layout;
    sizeRef.current = { width, height };
  }, []);

  if (!ad || dismissed) return null;

  try {
    const f = SPECS[format] || SPECS.card;
    const compact = !!f.h && f.h <= 50;
    const img = f.img !== false && ad.banner_image_url ? resolveMedia(apiBase, ad.banner_image_url) : "";

    const media = img ? (
      <Image
        source={{ uri: img }}
        accessibilityIgnoresInvertColors
        resizeMode="cover"
        style={
          f.horizontal
            ? { width: f.imgW, height: "100%" }
            : f.imgH
            ? { width: "100%", height: f.imgH }
            : { width: "100%", aspectRatio: 16 / 9 }
        }
      />
    ) : null;

    return (
      <View
        ref={viewRef}
        onLayout={onLayout}
        collapsable={false}
        style={[
          styles.card,
          {
            maxWidth: f.w,
            height: f.h,
            borderRadius: compact ? 8 : 12,
          },
          style,
        ]}
      >
        <Pressable
          onPress={onPress}
          accessibilityRole="link"
          accessibilityLabel={ad.name}
          style={[styles.main, f.horizontal ? styles.row : styles.col]}
        >
          {media}
          <View
            style={[
              styles.body,
              compact ? styles.bodyCompact : null,
              f.h ? styles.flex : null,
              f.badge && !f.horizontal ? styles.bodyBadge : null,
            ]}
          >
            <Text numberOfLines={1} style={[styles.title, { fontSize: compact ? 13 : 14 }]}>
              {ad.name}
            </Text>
            {f.desc && ad.description ? (
              <Text numberOfLines={f.horizontal ? 1 : 2} style={styles.desc}>
                {ad.description}
              </Text>
            ) : null}
          </View>
        </Pressable>
        {/* Ad label, always visible so the banner is never mistaken for app content.
            Bigger formats carry the full attribution, its own link to crossindie.com
            (never tracked as an ad click); the 320x50 strip gets a compact "AD" chip. */}
        {f.badge ? (
          <Pressable
            onPress={() => open("https://crossindie.com")}
            style={styles.badge}
            accessibilityRole="link"
            accessibilityLabel="Advertisement, promoted with CrossIndie"
          >
            <Text style={styles.badgeText}>AD · PROMOTED WITH CROSSINDIE</Text>
          </Pressable>
        ) : (
          <View style={styles.adChip} pointerEvents="none" accessibilityLabel="Advertisement">
            <Text style={styles.adChipText}>AD</Text>
          </View>
        )}
        {closeable ? (
          <Pressable
            onPress={() => setDismissed(true)}
            accessibilityRole="button"
            accessibilityLabel="Close"
            hitSlop={8}
            style={styles.close}
            testID="crossindie-close"
          >
            <Text style={styles.closeText}>×</Text>
          </Pressable>
        ) : null}
      </View>
    );
  } catch (e) {
    report(e);
    return null;
  }
}

const styles = StyleSheet.create({
  card: {
    width: "100%",
    alignSelf: "center",
    overflow: "hidden",
    backgroundColor: "#141210",
    borderWidth: 1,
    borderColor: "#27272a",
  },
  main: { flex: 1 },
  row: { flexDirection: "row", alignItems: "stretch" },
  col: { flexDirection: "column" },
  flex: { flex: 1 },
  body: { justifyContent: "center", paddingHorizontal: 12, paddingVertical: 10, flexShrink: 1 },
  // Right inset leaves room for the close button and the "AD" chip.
  bodyCompact: { paddingLeft: 10, paddingRight: 26, paddingVertical: 6 },
  bodyBadge: { paddingBottom: 24 },
  title: { color: "#f5f3ef", fontWeight: "600" },
  desc: { color: "#a8a29a", fontSize: 12, marginTop: 2 },
  badge: {
    position: "absolute",
    right: 6,
    bottom: 6,
    backgroundColor: "rgba(10,10,12,0.72)",
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 6,
  },
  badgeText: { color: "#d6d3cd", fontSize: 9, letterSpacing: 0.9 },
  adChip: {
    position: "absolute",
    right: 4,
    bottom: 4,
    backgroundColor: "rgba(10,10,12,0.72)",
    paddingHorizontal: 4,
    paddingVertical: 1,
    borderRadius: 4,
  },
  adChipText: { color: "#d6d3cd", fontSize: 8, letterSpacing: 0.8 },
  close: {
    position: "absolute",
    top: 5,
    right: 5,
    width: 18,
    height: 18,
    borderRadius: 9,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "rgba(10,10,12,0.55)",
  },
  closeText: { color: "#f5f3ef", fontSize: 14, lineHeight: 16 },
});

export default CrossIndieBanner;
