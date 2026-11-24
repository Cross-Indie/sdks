# CrossIndie Ads: Android bridge (Godot plugin v2)

Source of the AAR shipped in `../addons/crossindie_ads/bin/`. One Java class,
`CrossIndieAdsPlugin` (extends `org.godotengine.godot.plugin.GodotPlugin`),
registered as the Godot singleton **`CrossIndieAdsAndroid`** through the
`org.godotengine.plugin.v2.CrossIndieAdsAndroid` manifest meta-data.

Design rules that keep it working across Godot versions:

- **Nothing is bundled.** Godot (`org.godotengine:godot`) and Google Mobile Ads
  (`com.google.android.gms:play-services-ads`, which brings UMP transitively)
  are `compileOnly`. At export the editor plugin
  (`addons/crossindie_ads/export_plugin.gd`) adds the AAR via
  `_get_android_libraries`, the Maven coordinate via
  `_get_android_dependencies`, and the AdMob `APPLICATION_ID` via
  `_get_android_manifest_application_element_contents`.
- **Compiled against the oldest APIs**: Godot 4.2.0 + play-services-ads 22.6.0,
  Java 11 bytecode, plain Java (no Kotlin stdlib clash with any template).
- **Threading**: every SDK call runs on the Android UI thread; every callback
  is re-posted with `runOnRenderThread` before `emitSignal`, so GDScript only
  ever runs on Godot's thread. All signals are declared in `getPluginSignals()`.

## Build

Requires JDK 17 and the Android SDK (`ANDROID_HOME` or `local.properties`
with `sdk.dir=...`).

```bash
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=~/Library/Android/sdk
./gradlew assembleDebug assembleRelease
# -> ../addons/crossindie_ads/bin/{debug,release}/crossindie-ads-{debug,release}.aar
```

Compatibility check against newer SDKs (compile only, does not touch `bin/`):

```bash
./gradlew :plugin:compileReleaseJavaWithJavac -PgodotVersion=4.7.2.stable -PgmaVersion=25.5.0 --rerun-tasks
```

Toolchain: Gradle 8.11.1 (wrapper), AGP 8.6.1, compileSdk 35, minSdk 21.

## Native API (called by `providers/admob_android_provider.gd`)

Methods: `initialize(testMode, testDeviceIdsCsv, requestConsent, debugEea)`,
`isInitialized()`, `canRequestAds()`, `isPrivacyOptionsRequired()`,
`showPrivacyOptionsForm()`, `loadBanner(unitId, top)`, `showBanner()`,
`hideBanner()`, `destroyBanner()`, `getBannerHeightPx()`,
`loadInterstitial(unitId)`, `isInterstitialReady()`, `showInterstitial()`,
`loadRewarded(unitId)`, `isRewardedReady()`, `showRewarded()`.

Signals: `initialized`, `consent_finished(bool, String)`, `banner_loaded`,
`banner_failed_to_load(int, String)`, `banner_clicked`,
`interstitial_loaded|opened|closed|clicked`,
`interstitial_failed_to_load|failed_to_show(int, String)`,
`rewarded_loaded|opened|closed|clicked`,
`rewarded_failed_to_load|failed_to_show(int, String)`,
`rewarded_earned(int amount, String type)`.

Error codes are Google's `AdError` codes; `-1` no activity, `-2` not loaded,
`-3` exception in the bridge.
