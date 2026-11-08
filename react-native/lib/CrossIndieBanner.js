"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CrossIndieBanner = CrossIndieBanner;
const jsx_runtime_1 = require("react/jsx-runtime");
const react_1 = require("react");
const react_native_1 = require("react-native");
const core_1 = require("./core");
const SPECS = {
    card: { w: 320, desc: true, badge: true },
    rectangle: { w: 300, h: 250, imgH: 150, desc: true, badge: true },
    leaderboard: { w: 728, h: 90, horizontal: true, imgW: 150, desc: true, badge: true },
    mobile: { w: 320, h: 50, horizontal: true, imgW: 50, desc: false, badge: false },
    text: { w: 320, img: false, desc: true, badge: true },
};
const TICK_MS = 250;
let cachedPackage = null;
/** Bundle id via expo-application when the host app has it (optional dep). */
function detectPackage() {
    if (cachedPackage !== null)
        return cachedPackage;
    cachedPackage = undefined;
    try {
        // Metro treats a require inside try/catch as optional: no error when the
        // module is not installed.
        const mod = require("expo-application");
        const id = mod && mod.applicationId;
        // Inside Expo Go the id is Expo Go's own, not the host app's.
        if (id && id !== "host.exp.Exponent")
            cachedPackage = id;
    }
    catch {
        // not installed
    }
    return cachedPackage || undefined;
}
function deviceLang() {
    try {
        const loc = Intl.DateTimeFormat().resolvedOptions().locale;
        return loc ? loc.slice(0, 2) : undefined;
    }
    catch {
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
function CrossIndieBanner(props) {
    const { appId, category = "mobile_app", format = "card", apiBase, country, closeable = true, style, } = props;
    const [ad, setAd] = (0, react_1.useState)(null);
    const [dismissed, setDismissed] = (0, react_1.useState)(false);
    const [generation, setGeneration] = (0, react_1.useState)(0);
    const viewRef = (0, react_1.useRef)(null);
    const sizeRef = (0, react_1.useRef)({ width: 0, height: 0 });
    const appStateRef = (0, react_1.useRef)(react_native_1.AppState.currentState);
    const propsRef = (0, react_1.useRef)(props);
    propsRef.current = props;
    const clickedRef = (0, react_1.useRef)(false);
    const refreshDueRef = (0, react_1.useRef)(false);
    const report = (0, react_1.useCallback)((e) => {
        try {
            const err = e instanceof Error ? e : new Error(String(e));
            if (propsRef.current.onError)
                propsRef.current.onError(err);
            else
                console.warn("[CrossIndie]", err.message);
        }
        catch {
            // never throw into the host
        }
    }, []);
    const safe = (0, react_1.useCallback)((f) => {
        try {
            f();
        }
        catch (e) {
            report(e);
        }
    }, [report]);
    // Track foreground / background.
    (0, react_1.useEffect)(() => {
        let sub;
        try {
            sub = react_native_1.AppState.addEventListener("change", (s) => {
                appStateRef.current = s;
            });
        }
        catch (e) {
            report(e);
        }
        return () => {
            try {
                sub && sub.remove();
            }
            catch {
                // ignore
            }
        };
    }, [report]);
    // Fetch (again on param change or rotation).
    (0, react_1.useEffect)(() => {
        if (dismissed)
            return;
        if (!appId || !appId.trim()) {
            report(new Error("appId is required"));
            return;
        }
        let cancelled = false;
        refreshDueRef.current = false;
        (async () => {
            try {
                const next = await (0, core_1.fetchAd)({
                    apiBase,
                    appId: appId.trim(),
                    category,
                    platform: `react-native-${react_native_1.Platform.OS}`,
                    packageName: propsRef.current.packageName || detectPackage(),
                    lang: propsRef.current.lang || deviceLang(),
                    country,
                });
                if (cancelled)
                    return;
                clickedRef.current = false;
                setAd(next);
                if (next)
                    safe(() => { var _a, _b; return (_b = (_a = propsRef.current).onAdLoaded) === null || _b === void 0 ? void 0 : _b.call(_a, next); });
                else
                    safe(() => { var _a, _b; return (_b = (_a = propsRef.current).onNoAd) === null || _b === void 0 ? void 0 : _b.call(_a); });
            }
            catch (e) {
                if (!cancelled)
                    report(e); // keep a previous ad on a failed rotation
            }
        })();
        return () => {
            cancelled = true;
        };
    }, [appId, category, apiBase, country, generation, dismissed, report, safe]);
    // Visibility polling: impression after continuous dwell, then optional rotation.
    (0, react_1.useEffect)(() => {
        if (!ad || dismissed)
            return;
        let refreshTimer;
        let measuring = false;
        const dwell = new core_1.DwellTracker(ad.min_display_ms);
        const check = (cb) => {
            const p = propsRef.current;
            const sz = sizeRef.current;
            if (appStateRef.current !== "active" ||
                p.visible === false ||
                !(sz.width > 0 && sz.height > 0) ||
                !viewRef.current ||
                measuring) {
                cb(false);
                return;
            }
            measuring = true;
            try {
                viewRef.current.measureInWindow((x, y, width, height) => {
                    measuring = false;
                    try {
                        cb((0, core_1.isOnScreen)({ x, y, width, height }, react_native_1.Dimensions.get("window")));
                    }
                    catch (e) {
                        report(e);
                    }
                });
            }
            catch (e) {
                measuring = false;
                report(e);
                cb(false);
            }
        };
        const interval = setInterval(() => {
            if (dwell.done && !refreshDueRef.current)
                return;
            check((visible) => {
                if (refreshDueRef.current) {
                    if (visible) {
                        refreshDueRef.current = false;
                        setGeneration((g) => g + 1);
                    }
                    return;
                }
                if (dwell.sample(visible, Date.now())) {
                    (0, core_1.trackEvent)(apiBase, ad.tracking_token, "impression").then((ok) => {
                        if (ok)
                            safe(() => { var _a, _b; return (_b = (_a = propsRef.current).onImpression) === null || _b === void 0 ? void 0 : _b.call(_a, ad); });
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
            if (refreshTimer)
                clearTimeout(refreshTimer);
        };
    }, [ad, dismissed, apiBase, report, safe]);
    const open = (0, react_1.useCallback)((url) => {
        react_native_1.Linking.openURL(url).catch(report);
    }, [report]);
    const onPress = (0, react_1.useCallback)(() => {
        if (!ad || !ad.target_url)
            return;
        try {
            if (!clickedRef.current) {
                clickedRef.current = true;
                (0, core_1.trackEvent)(apiBase, ad.tracking_token, "click");
                safe(() => { var _a, _b; return (_b = (_a = propsRef.current).onClick) === null || _b === void 0 ? void 0 : _b.call(_a, ad); });
            }
            open(ad.target_url);
        }
        catch (e) {
            report(e);
        }
    }, [ad, apiBase, open, report, safe]);
    const onLayout = (0, react_1.useCallback)((e) => {
        const { width, height } = e.nativeEvent.layout;
        sizeRef.current = { width, height };
    }, []);
    if (!ad || dismissed)
        return null;
    try {
        const f = SPECS[format] || SPECS.card;
        const compact = !!f.h && f.h <= 50;
        const img = f.img !== false && ad.banner_image_url ? (0, core_1.resolveMedia)(apiBase, ad.banner_image_url) : "";
        const media = img ? ((0, jsx_runtime_1.jsx)(react_native_1.Image, { source: { uri: img }, accessibilityIgnoresInvertColors: true, resizeMode: "cover", style: f.horizontal
                ? { width: f.imgW, height: "100%" }
                : f.imgH
                    ? { width: "100%", height: f.imgH }
                    : { width: "100%", aspectRatio: 16 / 9 } })) : null;
        return ((0, jsx_runtime_1.jsxs)(react_native_1.View, { ref: viewRef, onLayout: onLayout, collapsable: false, style: [
                styles.card,
                {
                    maxWidth: f.w,
                    height: f.h,
                    borderRadius: compact ? 8 : 12,
                },
                style,
            ], children: [(0, jsx_runtime_1.jsxs)(react_native_1.Pressable, { onPress: onPress, accessibilityRole: "link", accessibilityLabel: ad.name, style: [styles.main, f.horizontal ? styles.row : styles.col], children: [media, (0, jsx_runtime_1.jsxs)(react_native_1.View, { style: [
                                styles.body,
                                compact ? styles.bodyCompact : null,
                                f.h ? styles.flex : null,
                                f.badge && !f.horizontal ? styles.bodyBadge : null,
                            ], children: [(0, jsx_runtime_1.jsx)(react_native_1.Text, { numberOfLines: 1, style: [styles.title, { fontSize: compact ? 13 : 14 }], children: ad.name }), f.desc && ad.description ? ((0, jsx_runtime_1.jsx)(react_native_1.Text, { numberOfLines: f.horizontal ? 1 : 2, style: styles.desc, children: ad.description })) : null] })] }), f.badge ? ((0, jsx_runtime_1.jsx)(react_native_1.Pressable, { onPress: () => open("https://crossindie.com"), style: styles.badge, accessibilityRole: "link", children: (0, jsx_runtime_1.jsx)(react_native_1.Text, { style: styles.badgeText, children: "PROMOTED WITH CROSSINDIE" }) })) : null, closeable ? ((0, jsx_runtime_1.jsx)(react_native_1.Pressable, { onPress: () => setDismissed(true), accessibilityRole: "button", accessibilityLabel: "Close", hitSlop: 8, style: styles.close, testID: "crossindie-close", children: (0, jsx_runtime_1.jsx)(react_native_1.Text, { style: styles.closeText, children: "\u00D7" }) })) : null] }));
    }
    catch (e) {
        report(e);
        return null;
    }
}
const styles = react_native_1.StyleSheet.create({
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
    bodyCompact: { paddingHorizontal: 10, paddingVertical: 6 },
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
exports.default = CrossIndieBanner;
