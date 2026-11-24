# CrossIndie Ads (Godot 4.2+)

One ad API for Godot that keeps working across engine versions: **Google AdMob
on Android** with automatic **CrossIndie cross-promo fallback** whenever AdMob
has no fill, errors, is limited, or does not exist on the platform (editor,
desktop, iOS for now).

- Banner (top / bottom, anchored adaptive), interstitial, rewarded.
- Provider chain per format: `admob -> crossindie` (configurable).
- Google Mobile Ads is **pulled from Maven at export time**, not bundled as
  jars, and the native bridge is a ~15 KB AAR compiled against the oldest
  supported APIs. That is what keeps it from breaking on engine upgrades.
- GDPR / US-state consent via Google UMP is built in.

## Supported versions

| Godot | Android Gradle template | play-services-ads picked automatically |
|-------|-------------------------|----------------------------------------|
| 4.2   | AGP 7.2, compileSdk 33, minSdk 21 | 22.6.0 |
| 4.3 – 4.4 | AGP 8.2, compileSdk 34, minSdk 21 | 23.6.0 |
| 4.5+ (tested up to 4.7.2) | AGP 8.6+, compileSdk 35+, minSdk 24 | 25.5.0 |

Verified end to end with Godot 4.7.2 on an Android 16 (API 36) arm64 emulator and a
physical Samsung Galaxy M10 (Android 10, 32-bit armeabi-v7a): adaptive banner,
interstitial and rewarded (Google test units) load, show, close and reward.
4.2 – 4.6 are build-verified (AAR compiles against each template's SDK levels).

Override with Project Settings → `crossindie_ads/android/play_services_ads_version`.
The bridge AAR is built against Godot 4.2.0 + play-services-ads 22.6.0 and
also compiles cleanly against 4.5 + 24.9.0 and 4.7.2 + 25.5.0.

## Install

1. Copy **both** `addons/crossindie_ads/` and `addons/cross_indie/` into your
   project's `res://addons/` (the fallback reuses the stock `CrossIndieBanner`).
2. Project → Project Settings → Plugins: enable **CrossIndie Ads** (and
   CrossIndie). Enabling adds the `CrossIndieAds` autoload and the
   `crossindie_ads/*` Project Settings.
3. Android export:
   - Project → Install Android Build Template.
   - In the Android export preset enable **Gradle Build → Use Gradle Build**
     (v2 plugins with Maven dependencies need it), and the **Internet**
     permission.
4. Set your ids (below) and turn `crossindie_ads/general/test_mode` **off** for
   release builds.

## Configure

Project Settings → `crossindie_ads/…` (or pass the same keys to `initialize()`):

| Setting | Config key | Default | Notes |
|---|---|---|---|
| `general/test_mode` | `test_mode` | `true` | Uses Google's official test ad units. |
| `general/provider_chain` | `provider_chain` | `admob,crossindie` | Order = priority. |
| `general/auto_reload_fullscreen` | `auto_reload` | `true` | Reload interstitial/rewarded after close. |
| `general/banner_retry_sec` | `banner_retry_sec` | `60` | Retry / upgrade back to AdMob after a fallback. |
| `admob/android_app_id` | – | `""` | **Required for release.** Injected into the manifest at export; empty → Google test app id + export warning. |
| `admob/android_banner_id` | `admob_android_banner_id` | `""` | Empty → that format goes straight to fallback. |
| `admob/android_interstitial_id` | `admob_android_interstitial_id` | `""` | |
| `admob/android_rewarded_id` | `admob_android_rewarded_id` | `""` | |
| `admob/test_device_ids` | `admob_test_device_ids` | `""` | Comma-separated (logcat prints yours). |
| `admob/request_consent` | `admob_request_consent` | `true` | Run UMP before SDK init. |
| `admob/debug_geography_eea` | `admob_debug_eea` | `false` | Test mode only: force EEA consent form. |
| `crossindie/app_id` | `crossindie_app_id` | `""` | Your CrossIndie app id (dashboard). |
| `crossindie/base_url` | `crossindie_base_url` | `https://api.crossindie.com` | |
| `crossindie/category` | `crossindie_category` | `game` | |
| `crossindie/fallback_close_delay_sec` | `fallback_close_delay_sec` | `3` | Interstitial fallback close button delay. |
| `crossindie/fallback_reward_delay_sec` | `fallback_reward_delay_sec` | `5` | Rewarded fallback visible time before reward (≥ 1.5). |
| `crossindie/rewarded_fallback_grants_reward` | `rewarded_fallback_grants_reward` | `false` | See "Fallback behavior". |
| `crossindie/fallback_reward_amount` / `_type` | `fallback_reward_amount` / `fallback_reward_type` | `1` / `"reward"` | Reward reported by the fallback. |
| `crossindie/banner_refresh_sec` | `crossindie_banner_refresh_sec` | `60` | 0 = never refresh. |
| `android/play_services_ads_version` | – | `""` (auto) | Maven version pulled at export. |

## API

```gdscript
func _ready() -> void:
    CrossIndieAds.rewarded_earned.connect(_on_reward)
    CrossIndieAds.ad_failed.connect(func(fmt, provider, err): print(fmt, provider, err))
    CrossIndieAds.initialize({
        "test_mode": OS.is_debug_build(),
        "crossindie_app_id": "YOUR_CROSSINDIE_APP_ID",
        "admob_android_banner_id": "ca-app-pub-xxx/yyy",
        "admob_android_interstitial_id": "ca-app-pub-xxx/yyy",
        "admob_android_rewarded_id": "ca-app-pub-xxx/yyy",
    })
    CrossIndieAds.show_banner("bottom")
    CrossIndieAds.load_interstitial()
    CrossIndieAds.load_rewarded()

func _on_level_end() -> void:
    CrossIndieAds.show_interstitial()      # returns false if nothing is ready

func _on_continue_pressed() -> void:
    CrossIndieAds.show_rewarded()

func _on_reward(amount: int, type: String) -> void:
    coins += amount                        # grant ONLY here, never on *_closed
```

**Methods**

| Method | |
|---|---|
| `initialize(config := {})` | Merge config over Project Settings and start providers. |
| `show_banner(position := "bottom")` / `hide_banner()` / `destroy_banner()` | `"top"` or `"bottom"`. |
| `is_banner_visible()`, `get_banner_height_px()` | Physical pixels, for pushing UI out of the way. |
| `load_interstitial()`, `is_interstitial_ready()`, `show_interstitial() -> bool` | |
| `load_rewarded()`, `is_rewarded_ready()`, `show_rewarded() -> bool` | |
| `is_privacy_options_required()`, `show_privacy_options()` | GDPR "Privacy settings" button. |
| `get_active_providers()`, `is_test_mode()`, `is_initialized()` | |

**Signals** (`provider` = `"admob"`, `"crossindie"`, …)

`initialized`, `consent_finished(can_request_ads)`, `banner_loaded(provider)`,
`interstitial_loaded/opened/closed(provider)`,
`rewarded_loaded/opened/closed(provider)`, `rewarded_earned(amount, reward_type)`,
`ad_clicked(format, provider)`, `ad_failed(format, provider, error)`.

`ad_failed` fires once per provider failure; a final one with `provider == ""`
means the whole chain failed for that request. All native callbacks are run
on the Android UI thread and come back to GDScript on Godot's main thread.

## Fallback behavior

| Format | AdMob unavailable / no fill → CrossIndie |
|---|---|
| Banner | Full-width CrossIndie strip (CanvasLayer 100) at the same edge. Refreshes every `banner_refresh_sec`. Every `banner_retry_sec` AdMob is tried again; on fill it replaces the fallback. |
| Interstitial | Full-screen overlay (CanvasLayer 128, blocks game input, works while the tree is paused) with a CrossIndie ad; the close button appears after `fallback_close_delay_sec`. |
| Rewarded | Same overlay. If `rewarded_fallback_grants_reward` is **on** `rewarded_earned(fallback_reward_amount, fallback_reward_type)` fires after the ad has been visible for `fallback_reward_delay_sec` **with the window focused**, then the close button appears. If **off (default)**, it behaves like an interstitial and never rewards: a rewarded call that closes without `rewarded_earned` means "no reward". |

Impressions/clicks for fallback ads go through the unmodified
`CrossIndieBanner`: `GET /api/v1/ad/fetch` → signed `tracking_token` →
`POST /api/v1/ad/track` after the server's minimum display time (≥1.5 s,
focused only) and on click. Ads are preloaded hidden, so preloading never
counts as an impression.

Note: the CrossIndie network policy is "never reward users for viewing or
tapping a CrossIndie ad" (advertisers pay credits for genuine attention). That
is why the rewarded fallback does **not** grant a reward by default. Only turn
`rewarded_fallback_grants_reward` on for house ads between your own apps.

The CrossIndie overlay does not pause your game. Use `interstitial_opened` /
`interstitial_closed` (and the rewarded pair) to pause/resume if needed. AdMob
full-screen ads pause the Godot activity themselves.

## Platforms

| | Banner | Interstitial | Rewarded |
|---|---|---|---|
| Android | AdMob → CrossIndie | AdMob → CrossIndie | AdMob → CrossIndie |
| iOS | CrossIndie only (AdMob = roadmap) | CrossIndie only | CrossIndie only |
| Desktop / Web / editor run | CrossIndie only | CrossIndie only | CrossIndie only |

## Roadmap

- **iOS AdMob**: native plugin `CrossIndieAdsIOS` with the same method/signal
  surface as the Android bridge, Google Mobile Ads via CocoaPods/SPM. Stub:
  `providers/admob_ios_provider.gd`.
- **AppLovin MAX** (Android + iOS): second bridge `CrossIndieAdsMax`, SDK pulled
  from Maven/CocoaPods, enabled by adding `applovin_max` to `provider_chain`.
  Stub: `providers/applovin_max_provider.gd`.
- Adding a network = extend `providers/ad_provider.gd` and register it in
  `crossindie_ads.gd::_provider_script_path()`.

## Rebuilding the Android bridge

Source: [`../../crossindie_ads_android`](../../crossindie_ads_android). `./gradlew assemble`
rebuilds and copies `bin/debug/crossindie-ads-debug.aar` and
`bin/release/crossindie-ads-release.aar` into this folder.

## Demo

[`../../examples/crossindie_ads_demo`](../../examples/crossindie_ads_demo): button panel
for every call, plus a headless smoke test of the fallback path.
