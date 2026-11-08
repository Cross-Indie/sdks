# CrossIndie for React Native / Expo

Free cross-promotion banner for indie React Native and Expo apps. Drop in one
component, show other indies' banners, earn credits, spend them to get your own
app discovered.

- Pure JS/TS, **no native modules**: works in Expo Go, Expo dev builds and bare
  React Native (iOS, Android, react-native-web).
- No dependencies beyond `react` / `react-native`. `expo-application` is used
  automatically when present (optional).
- No tracking IDs, no device identifiers, no cookies. Only your public `appId`
  is sent.

## Install

Not on npm yet. Vendor the package from the SDK repo and add it as a local
dependency (`lib/` is prebuilt, no build step needed):

```bash
npx degit Cross-Indie/sdks/react-native vendor/crossindie-react-native
npm install ./vendor/crossindie-react-native
```

(or copy the `react-native/` folder of https://github.com/Cross-Indie/sdks by
hand). Once published it will be `npm install @crossindie/react-native`.

Optional, so the dashboard can confirm the SDK runs inside your store app:

```bash
npx expo install expo-application
```

## Usage

```tsx
import { CrossIndieBanner } from "@crossindie/react-native";

export function Screen() {
  return (
    <View>
      {/* your content */}
      <CrossIndieBanner appId="YOUR_APP_ID" />
    </View>
  );
}
```

All props:

```tsx
<CrossIndieBanner
  appId="YOUR_APP_ID"          // from crossindie.com/dashboard/apps
  category="mobile_app"        // game | web_tool | saas | mobile_app (default mobile_app)
  format="mobile"              // card | rectangle | leaderboard | mobile | text (default card)
  packageName="com.example.app" // optional; auto-detected with expo-application
  country="US"                 // optional targeting
  visible={isFocused}          // optional, e.g. useIsFocused() from React Navigation
  closeable                    // small ✕ (a dismissed slot earns nothing); default true
  refreshSeconds={60}          // optional rotation (min 30); off by default
  onAdLoaded={(ad) => {}}
  onNoAd={() => {}}
  onImpression={(ad) => {}}
  onClick={(ad) => {}}
  onError={(err) => {}}
  style={{ marginVertical: 12 }}
/>
```

Formats match the web widget: `card` (320 wide, 16:9 image), `rectangle`
(300x250), `leaderboard` (728x90), `mobile` (320x50), `text` (no image). The
banner fills its parent's width up to the format's width.

The `platform` sent is `react-native-ios`, `react-native-android`, etc. Each
banner you place is an independent slot that earns credits on every valid
impression.

### With React Navigation

Screens in a stack stay mounted when you navigate away. Pass the focus state so
a hidden screen never counts as an impression:

```tsx
import { useIsFocused } from "@react-navigation/native";

const isFocused = useIsFocused();
<CrossIndieBanner appId="YOUR_APP_ID" visible={isFocused} />;
```

## How it stays honest

- An impression is reported only once the banner has been **continuously**
  visible for the server's minimum display time (`min_display_ms`, 1.5 s):
  non-zero size (`onLayout`), at least 50% inside the window
  (`measureInWindow` against the window size), app active (`AppState`) and
  `visible` not false. Any gap resets the timer.
- One impression and at most one click per fetched ad (single-use token). A tap
  opens the ad in the external browser (`Linking.openURL`).
- All credit and anti-fraud checks run on the server. Errors are caught: on any
  failure the banner renders nothing and your app keeps running.

## Development

```bash
npm install
npm test          # jest, core logic
npm run build     # tsc -> lib/
```

## License

MIT
