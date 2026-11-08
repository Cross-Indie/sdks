# CrossIndie for Flutter

Free cross-promotion banner for indie apps and games built with Flutter
(Android, iOS, web, desktop). Drop in one widget, show other indies' banners,
earn credits, spend them to get your own app discovered.

- Pure Dart widget, no native code of its own.
- Dependencies: [`http`](https://pub.dev/packages/http) and
  [`url_launcher`](https://pub.dev/packages/url_launcher) (both from the Dart /
  Flutter teams; url_launcher is the only way to open the external browser).
- No tracking IDs, no device identifiers, no cookies. Only your public
  `appId` is sent.

## Install

Not on pub.dev yet. Add it as a git dependency:

```yaml
dependencies:
  crossindie:
    git:
      url: https://github.com/Cross-Indie/sdks.git
      path: flutter
```

Then `flutter pub get`.

Android release builds need internet access. Make sure
`android/app/src/main/AndroidManifest.xml` has
`<uses-permission android:name="android.permission.INTERNET"/>` (Flutter's
template only adds it to the debug manifest).

## Usage

```dart
import 'package:crossindie/crossindie.dart';

// Anywhere in your widget tree:
const CrossIndieBanner(appId: 'YOUR_APP_ID')
```

All options:

```dart
CrossIndieBanner(
  appId: 'YOUR_APP_ID',                      // from crossindie.com/dashboard/apps
  category: CrossIndieCategory.mobileApp,    // game | webTool | saas | mobileApp
  format: CrossIndieFormat.mobile,           // card | rectangle | leaderboard | mobile | text
  packageName: 'com.example.myapp',          // optional, see below
  country: 'US',                             // optional targeting
  closeable: true,                           // small ✕ (a dismissed slot earns nothing)
  refreshInterval: const Duration(minutes: 1), // optional rotation (min 30 s); off by default
  onAdLoaded: (ad) {},
  onNoAd: () {},
  onImpression: (ad) {},
  onClick: (ad) {},
  onError: (e) {},
)
```

Formats match the web widget: `card` (320 wide, 16:9 image), `rectangle`
(300x250), `leaderboard` (728x90), `mobile` (320x50), `text` (no image). The
banner takes at most the format's width and shrinks to narrower parents.

Each banner you place is an independent slot that earns credits on every valid
impression.

### Package name

The dashboard shows "SDK active" once the banner has called the network, and
can confirm it runs inside your store app when it knows your package name /
bundle id. Pure Dart can't read it without a plugin, so pass it in. If you
already use [`package_info_plus`](https://pub.dev/packages/package_info_plus):

```dart
final info = await PackageInfo.fromPlatform();
CrossIndieBanner(appId: 'YOUR_APP_ID', packageName: info.packageName);
```

The `platform` sent is `flutter-android`, `flutter-ios`, `flutter-web`, etc.

## How it stays honest

- An impression is reported only once the banner has been **continuously**
  visible for the server's minimum display time (`min_display_ms`, 1.5 s):
  non-zero size, at least 50% inside the screen and any scroll view, app in the
  foreground, its route on top and not in an offstage tab. Scrolling away resets
  the timer.
- One impression and at most one click per fetched ad (single-use token). A tap
  opens the ad in the external browser.
- All credit and anti-fraud checks run on the server. Errors are swallowed: on
  any failure the banner renders nothing and your app keeps running.

## Tests

```bash
flutter test
```

## License

MIT
