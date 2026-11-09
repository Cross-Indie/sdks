# CrossIndie Android SDK

Cross-promotion banner for native Android apps and games: a classic `View`
(XML or code) and an optional Jetpack Compose composable.

- **No dependencies.** The core artifact uses only `HttpURLConnection` and
  `org.json` from the platform (plus the Kotlin stdlib). Compose lives in a
  separate artifact, so View-only apps never pull in Compose.
- **minSdk 21**, compiled against API 35.
- **Never crashes your app.** All networking runs on two low-priority daemon
  threads and every error is swallowed (turn on `CrossIndie.debugLogging = true`
  to see them in Logcat under the tag `CrossIndie`).

## Install (JitPack)

The SDK is built by [JitPack](https://jitpack.io/#Cross-Indie/sdks) from the
`android/` folder of the [Cross-Indie/sdks](https://github.com/Cross-Indie/sdks)
repo. Add the repository in `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
    }
}
```

Then, in your app module:

```kotlin
dependencies {
    implementation("com.github.Cross-Indie.sdks:crossindie:1.2.0")
    // Jetpack Compose apps, additionally:
    implementation("com.github.Cross-Indie.sdks:crossindie-compose:1.2.0")
}
```

The version is the repository's git tag. (Groovy: `implementation 'com.github.Cross-Indie.sdks:crossindie:1.2.0'`.)

## Your app id

Copy it from **Dashboard › Integration** on [crossindie.com](https://crossindie.com).

## XML layout

```xml
<com.crossindie.sdk.CrossIndieBannerView
    android:id="@+id/banner"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    app:ciAppId="YOUR_APP_ID"
    app:ciCategory="game"
    app:ciFormat="mobile" />
```

(`xmlns:app="http://schemas.android.com/apk/res-auto"` on the root element.)

| Attribute | Default | Meaning |
|-----------|---------|---------|
| `ciAppId` | — | your app id (required) |
| `ciCategory` | `game` | pool to request: `game`, `mobile_app`, `web_tool`, `saas` |
| `ciFormat` | `mobile` | `mobile` (320×50), `card` (16:9 art + text), `rectangle` (300×250), `leaderboard` (728×90, tablets), `text` |
| `ciRefreshSeconds` | `30` | rotate to a new ad this long after an impression (`0` = never, minimum 15) |
| `ciVideo` | `true` | allow muted video creatives (see *Data use*) |
| `ciCloseable` | `false` | show a small × that hides the slot |
| `ciCountry` | — | viewer country (ISO alpha-2) for region targeting |
| `ciApiBase` | `https://api.crossindie.com` | only for self-hosted backends |

## Code (View)

```kotlin
val banner = CrossIndieBannerView(context).apply {
    appId = "YOUR_APP_ID"
    format = BannerFormat.CARD
    listener = object : CrossIndieBannerListener {
        override fun onImpression(ad: Ad) { /* you just earned credits */ }
    }
}
container.addView(banner, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
```

## Jetpack Compose

```kotlin
import com.crossindie.sdk.compose.CrossIndieBanner

CrossIndieBanner(appId = "YOUR_APP_ID")
CrossIndieBanner(appId = "YOUR_APP_ID", format = BannerFormat.CARD, modifier = Modifier.fillMaxWidth())
```

Works inside `LazyColumn` / `LazyRow`; the banner keeps its ad when the list
recycles the item.

## Behaviour

Same protocol and rules as the web, Unity and Godot SDKs:

- `GET /api/v1/ad/fetch?app_id=…&category=…&platform=android&package=<your applicationId>&lang=…`.
  `platform` + `package` power the **SDK active** badge on your dashboard and
  let the network confirm the banner runs inside your Play Store app.
- The slot has **zero height until an ad is available** (no empty boxes).
- An **impression** is reported (`POST /api/v1/ad/track`) only after the banner
  has been *continuously* on screen — non-zero size, at least 50 % visible, its
  window focused — for the server's minimum display time (`min_display_ms`,
  1.5 s). Scrolling it away resets the timer.
- A **click** reports `event_type=click` once per ad and opens the link in the
  browser / Play Store (`ACTION_VIEW`). The "Promoted with CrossIndie" badge is a
  separate link and is never counted.
- **Rotation**: a new ad every 30 s after an impression, only while the slot
  is visible. An ad that was never counted is re-fetched before its 60 s
  tracking token expires. Hidden slots make no further requests. No fill →
  retry in 60 s; errors back off from 15 s to 5 min.

Each banner is an independent slot that earns credits for every valid
impression, so more placements means more earnings.

## Privacy & data use

- **No device identifiers.** No advertising ID, Android ID, IMEI, cookies or
  local storage. Requests carry only your public app id, your package name,
  the device language, and an optional country you pass in. The server sees
  the IP address (used briefly for fraud checks, stored only as a hash).
- Only the `INTERNET` permission is declared.
- Video banners (muted, looping MP4) are requested only if your app already
  holds `ACCESS_NETWORK_STATE` *and* the connection is unmetered; otherwise you
  get the static image. They load only once the slot is visible and pause when
  it is not.
- Play Console data-safety: the SDK does not collect or share personal data
  beyond the IP address needed to serve the request.

## Sample & development

```bash
cd android
./gradlew :crossindie:testDebugUnitTest            # unit tests (parsing, visibility, rotation)
./gradlew :sample:installDebug -PciAppId=<your app id>   # demo app (View + Compose)
# local backend from the emulator: add -PapiBase=http://10.0.2.2:8010
```

Releasing: tag the sdks repo (e.g. `git tag 1.2.0 && git push origin 1.2.0`);
JitPack builds it on first request using `../jitpack.yml`.

## License

MIT

## Store policy

- Every banner carries an "AD" label so it is never mistaken for your content.
- Not for apps or games directed at children (Google Play Families program, App Store Kids category): CrossIndie is not a Families self-certified ad SDK.
- Never reward your users for viewing or tapping a banner.
