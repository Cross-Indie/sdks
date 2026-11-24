extends "res://addons/crossindie_ads/providers/ad_provider.gd"

## ROADMAP (phase 2): AppLovin MAX (Android + iOS).
##
## Planned shape: a second native plugin (singleton "CrossIndieAdsMax") built
## exactly like CrossIndieAdsAndroid: compileOnly against
## com.applovin:applovin-sdk, the export plugin adds the Maven coordinate and
## the SDK key meta-data. Enable it by putting "applovin_max" in
## crossindie_ads/general/provider_chain, e.g. "applovin_max,admob,crossindie".
##
## Until then it reports unavailable and is skipped by the chain.

const SINGLETON := "CrossIndieAdsMax"


func provider_name() -> String:
	return "applovin_max"


func is_available() -> bool:
	return false  # not implemented yet; see header


func supports(format: String) -> bool:
	return false
