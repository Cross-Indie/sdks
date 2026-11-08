# CrossIndie SDKs

Official, open-source client SDKs for [CrossIndie](https://crossindie.com) — the
zero-bloat cross-promotion network for indie games, apps, web tools and
micro-SaaS. Drop in one banner, earn credits by hosting other indies, spend
them to get discovered.

These clients are intentionally thin and **contain no secrets** — they only call
public endpoints with your public `app_id`. All credit and anti-fraud logic is
enforced server-side. MIT licensed, so you can read exactly what runs in your
product and embed it freely.

## SDKs

| Platform | Path | Distribution |
|----------|------|--------------|
| **Web** | [`web/`](web) | npm `@crossindie/web`, or `<script src=".../embed.js">` |
| **Godot 4.x** | [`godot/`](godot) | copy the addon into `res://addons/` |
| **Unity** | [`unity/`](unity) | UPM: add from git URL (see below) |
| **Unreal Engine 5** | [`unreal/`](unreal) | copy the plugin into `Plugins/` |
| **Flutter** | [`flutter/`](flutter) | pub git dependency (`path: flutter`), pub.dev `crossindie` later |
| **React Native / Expo** | [`react-native/`](react-native) | vendor the folder (`npx degit`), npm `@crossindie/react-native` later |
| **Android (Kotlin / Java)** | [`android/`](android) | JitPack: `com.github.Cross-Indie.sdks:crossindie:<tag>` (+ `crossindie-compose`) |
| **iOS (Swift)** | [`ios/`](ios) | Swift Package Manager: this repo's URL |
| **Capacitor / Ionic / Cordova** | use [`web/`](web) | the web embed runs inside the app's WebView (see below) |

Each folder has its own README with setup steps.

## Quick install

**Web**
```html
<script src="https://api.your-host/embed.js" data-api-base="https://api.your-host" async></script>
<div data-ci-app-id="YOUR_APP_ID" data-ci-category="game" data-ci-format="leaderboard"></div>
```

**Unity (UPM)** — Package Manager → Add package from git URL:
```
https://github.com/Cross-Indie/sdks.git?path=unity/com.crossindie.banner
```

**Godot** — copy `godot/addons/cross_indie` into `res://addons/` and enable the plugin.

**Unreal** — copy `unreal/CrossIndie` into your project's `Plugins/` and rebuild.

**Flutter** — `pubspec.yaml`:
```yaml
dependencies:
  crossindie:
    git:
      url: https://github.com/Cross-Indie/sdks.git
      path: flutter
```
```dart
const CrossIndieBanner(appId: 'YOUR_APP_ID')
```

**React Native / Expo** (pure JS, works in Expo Go):
```bash
npx degit Cross-Indie/sdks/react-native vendor/crossindie-react-native
npm install ./vendor/crossindie-react-native
```
```tsx
<CrossIndieBanner appId="YOUR_APP_ID" />
```

**Android** — `settings.gradle.kts` → `maven("https://jitpack.io")`, then:
```kotlin
implementation("com.github.Cross-Indie.sdks:crossindie:1.2.0")          // View
implementation("com.github.Cross-Indie.sdks:crossindie-compose:1.2.0")  // + Jetpack Compose
```
```xml
<com.crossindie.sdk.CrossIndieBannerView
    android:layout_width="match_parent" android:layout_height="wrap_content"
    app:ciAppId="YOUR_APP_ID" />
```

**iOS** — Xcode → File → Add Package Dependencies →
`https://github.com/Cross-Indie/sdks.git` (from `1.2.0`), then:
```swift
CrossIndieBanner(appId: "YOUR_APP_ID")        // SwiftUI
CrossIndieBannerView(appId: "YOUR_APP_ID")    // UIKit
```

**Capacitor / Ionic / Cordova** — no separate SDK: your app is a web page in a
WebView, so the web embed works as-is. Add it to `index.html` (or a component
template):
```html
<script src="https://api.crossindie.com/embed.js" data-api-base="https://api.crossindie.com" async></script>
<div data-ci-app-id="YOUR_APP_ID" data-ci-category="mobile_app" data-ci-format="mobile"></div>
```
In single-page frameworks (Ionic Angular/React/Vue) call
`CrossIndie.initSlots("https://api.crossindie.com")` after the slot element
mounts. Banner links use `target="_blank"`: Capacitor opens them in the system
browser; on Cordova keep `<allow-intent href="https://*/*" />` in `config.xml`
(or use cordova-plugin-inappbrowser) so they leave the app. If you set
**Allowed web domains** on the app, add `localhost` — that is the WebView's
origin on Capacitor (`capacitor://localhost` / `https://localhost`) and
Cordova.

## How the network works

- Each banner you place is an independent **slot**. More slots means more
  earnings.
- Hosting an impression earns **+0.85 credits** (held briefly, then vests).
- Getting your own banner shown costs **−1.00 credit**.
- Games are shown to games; web tools and SaaS share a pool.

> The Unity and Unreal SDKs ship as idiomatic starters — verify against your
> engine version. Web and Godot are production-tested. Flutter and React Native
> are new (1.0.0) and covered by unit / widget tests. Android and iOS are new
> (1.2.0), covered by unit tests and checked end-to-end on an emulator /
> simulator.

## License

MIT — see [LICENSE](LICENSE).
