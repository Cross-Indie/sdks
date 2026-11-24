extends "res://addons/crossindie_ads/providers/ad_provider.gd"

## ROADMAP (phase 2): Google AdMob on iOS.
##
## Planned shape: a GDExtension/iOS plugin exposing an Engine singleton named
## "CrossIndieAdsIOS" with the SAME methods and signals as the Android plugin
## (initialize, loadBanner/showBanner/hideBanner/destroyBanner,
## loadInterstitial/isInterstitialReady/showInterstitial,
## loadRewarded/isRewardedReady/showRewarded, consent), Google Mobile Ads pulled
## via CocoaPods/SPM at export time instead of bundling frameworks.
## Once it exists this file becomes admob_android_provider.gd with a different
## singleton name and the iOS test ids from settings.gd.
##
## Until then it reports unavailable, so on iOS the chain degrades to the
## CrossIndie fallback without errors.

const SINGLETON := "CrossIndieAdsIOS"


func provider_name() -> String:
	return "admob"


func is_available() -> bool:
	return false  # not implemented yet; see header


func supports(format: String) -> bool:
	return false
