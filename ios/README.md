# CrossIndie iOS SDK

Cross-promotion banner for native iOS apps and games: a UIKit view
(`CrossIndieBannerView`) and a SwiftUI view (`CrossIndieBanner`).

- **No dependencies**: Foundation, UIKit, SwiftUI, AVFoundation, Network.
- **iOS 13+**, Swift 5.9+ (Xcode 15+).
- **Never crashes your app**: ephemeral `URLSession`, every error swallowed
  (set `CrossIndie.debugLogging = true` to see them in the console).

## Install (Swift Package Manager)

Xcode → **File › Add Package Dependencies…** → enter

```
https://github.com/Cross-Indie/sdks.git
```

and choose *Up to Next Major Version* from `1.2.0`. Add the **CrossIndie**
library to your app target.

Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Cross-Indie/sdks.git", from: "1.2.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "CrossIndie", package: "sdks")]),
]
```

(SwiftPM reads the `Package.swift` at the repository root, which points at
`ios/Sources`.)

## Your app id

Copy it from **Dashboard › Integration** on [crossindie.com](https://crossindie.com).

## SwiftUI

```swift
import CrossIndie

CrossIndieBanner(appId: "YOUR_APP_ID")

CrossIndieBanner(appId: "YOUR_APP_ID", category: "game", format: .card)
    .onImpression { ad in print("earned credits for", ad.name) }
```

## UIKit

```swift
import CrossIndie

let banner = CrossIndieBannerView(appId: "YOUR_APP_ID", format: .mobile)
banner.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(banner)
NSLayoutConstraint.activate([
    banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
    banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
]) // height is intrinsic: 0 until an ad loads
banner.delegate = self  // optional CrossIndieBannerDelegate
```

In a storyboard, set the view's class to `CrossIndieBannerView` (module
`CrossIndie`) and set `ibAppId` (plus optionally `ibFormat`, `ibCategory`) in
the Attributes inspector.

| Property | Default | Meaning |
|----------|---------|---------|
| `appId` | — | your app id (required) |
| `category` | `"game"` | pool to request: `game`, `mobile_app`, `web_tool`, `saas` |
| `format` | `.mobile` | `.mobile` (320×50), `.card` (16:9 art + text), `.rectangle` (300×250), `.leaderboard` (728×90, iPad), `.text` |
| `refreshSeconds` | `30` | rotate this long after an impression (`0` = never, minimum 15) |
| `videoEnabled` | `true` | allow muted video creatives (see *Data use*) |
| `closeable` | `false` | show a small × that hides the slot |
| `country` | `nil` | viewer country (ISO alpha-2) for region targeting |
| `apiBase` | `CrossIndie.apiBase` (`https://api.crossindie.com`) | only for self-hosted backends |

`CrossIndie.opensLinksInApp = true` opens ad links in an
`SFSafariViewController` instead of Safari (App Store links always open the
App Store).

## Behaviour

Same protocol and rules as the web, Android, Unity and Godot SDKs:

- `GET /api/v1/ad/fetch?app_id=…&category=…&platform=ios&package=<bundle id>&lang=…`.
  `platform` + `package` power the **SDK active** badge on your dashboard; the
  bundle id is matched against your App Store listing.
- **Zero height until an ad is available.**
- An **impression** is reported only after the banner has been *continuously*
  on screen — non-zero size, at least 50 % visible (clipping scroll views and
  the window are taken into account), app active — for the server's minimum
  display time (`min_display_ms`, 1.5 s). Scrolling away resets the timer.
- A **click** reports `event_type=click` once per ad and opens the link with
  `UIApplication.open`. The "Promoted with CrossIndie" badge is a separate link
  and is never counted.
- **Rotation** every 30 s after an impression, only while visible; an uncounted
  ad is re-fetched before its 60 s tracking token expires; hidden slots make no
  further requests. No fill → retry in 60 s; errors back off 15 s → 5 min.

## Privacy & data use

- **No device identifiers**: no IDFA (no App Tracking Transparency prompt
  needed), no IDFV, no cookies (ephemeral session), nothing stored on disk.
  Requests carry only your public app id, bundle id, the preferred language and
  an optional country. The server sees the IP address (used briefly for fraud
  checks, stored only as a hash).
- Video banners (muted, looping) are requested only on Wi-Fi-like connections
  (not expensive, not Low Data Mode), load only once the slot is visible and
  pause when it is not.
- App Privacy label: the SDK does not track users and collects no data linked
  to them.

## Development

```bash
cd ios
swift test                                   # unit tests on macOS (logic only)
xcodebuild test -scheme CrossIndie \
  -destination 'platform=iOS Simulator,name=iPhone 16'   # full build + tests on iOS
```

Releasing: push a semver tag on the sdks repo (`1.2.0`); SwiftPM resolves it
directly — no registry.

## License

MIT
