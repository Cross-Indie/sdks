import type { StyleProp, ViewStyle } from "react-native";
import { CrossIndieAd, CrossIndieCategory, CrossIndieFormat } from "./core";
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
export declare function CrossIndieBanner(props: CrossIndieBannerProps): import("react").JSX.Element | null;
export default CrossIndieBanner;
