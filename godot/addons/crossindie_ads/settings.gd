@tool
extends RefCounted

## Project Settings keys + defaults shared by the editor plugin (registration,
## export) and the runtime singleton. Everything here can also be overridden at
## runtime through CrossIndieAds.initialize({...}).

const PREFIX := "crossindie_ads/"

## Google's official sample ids (https://developers.google.com/admob/android/test-ads).
const TEST_ANDROID_APP_ID := "ca-app-pub-3940256099942544~3347511713"
const TEST_ANDROID_BANNER := "ca-app-pub-3940256099942544/9214589741"  # adaptive banner
const TEST_ANDROID_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const TEST_ANDROID_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_IOS_APP_ID := "ca-app-pub-3940256099942544~1458002511"
const TEST_IOS_BANNER := "ca-app-pub-3940256099942544/2435281174"
const TEST_IOS_INTERSTITIAL := "ca-app-pub-3940256099942544/4411468910"
const TEST_IOS_REWARDED := "ca-app-pub-3940256099942544/1712485313"

## [config key, project setting path, default, type, hint, hint_string]
const DEFINITIONS: Array = [
	["test_mode", "general/test_mode", true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	["provider_chain", "general/provider_chain", "admob,crossindie", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["auto_reload", "general/auto_reload_fullscreen", true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	["banner_retry_sec", "general/banner_retry_sec", 60.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "10,600,1"],

	["admob_android_app_id", "admob/android_app_id", "", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["admob_android_banner_id", "admob/android_banner_id", "", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["admob_android_interstitial_id", "admob/android_interstitial_id", "", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["admob_android_rewarded_id", "admob/android_rewarded_id", "", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["admob_test_device_ids", "admob/test_device_ids", "", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["admob_request_consent", "admob/request_consent", true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	["admob_debug_eea", "admob/debug_geography_eea", false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],

	["crossindie_app_id", "crossindie/app_id", "", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["crossindie_base_url", "crossindie/base_url", "https://api.crossindie.com", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	## % of banners/interstitials that go to CrossIndie first (AdMob is not asked).
	## Each one earns you network credits. Rewarded ads are never shared.
	["crossindie_share", "crossindie/share_percent", 0, TYPE_INT, PROPERTY_HINT_RANGE, "0,100,1"],
	["crossindie_category", "crossindie/category", "game", TYPE_STRING, PROPERTY_HINT_ENUM, "game,web_tool,saas,mobile_app"],
	["fallback_close_delay_sec", "crossindie/fallback_close_delay_sec", 3.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,30,0.5"],
	["fallback_reward_delay_sec", "crossindie/fallback_reward_delay_sec", 5.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "1.5,60,0.5"],
	["rewarded_fallback_grants_reward", "crossindie/rewarded_fallback_grants_reward", false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	["fallback_reward_amount", "crossindie/fallback_reward_amount", 1, TYPE_INT, PROPERTY_HINT_NONE, ""],
	["fallback_reward_type", "crossindie/fallback_reward_type", "reward", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["crossindie_banner_refresh_sec", "crossindie/banner_refresh_sec", 60.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,600,1"],

	## "" = auto: the export plugin picks a play-services-ads version known to
	## build with the running Godot version's Gradle template.
	["android_play_services_ads_version", "android/play_services_ads_version", "", TYPE_STRING, PROPERTY_HINT_NONE, ""],
]


static func path_of(def: Array) -> String:
	return PREFIX + String(def[1])


## Register every setting (editor only) so they show up in Project Settings.
static func register_all() -> void:
	for def in DEFINITIONS:
		var path: String = path_of(def)
		if not ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, def[2])
		ProjectSettings.set_initial_value(path, def[2])
		ProjectSettings.set_as_basic(path, true)
		ProjectSettings.add_property_info({
			"name": path,
			"type": def[3],
			"hint": def[4],
			"hint_string": def[5],
		})


## Current values from Project Settings as a {config key: value} Dictionary.
static func load_all() -> Dictionary:
	var out: Dictionary = {}
	for def in DEFINITIONS:
		out[def[0]] = ProjectSettings.get_setting(path_of(def), def[2])
	return out


static func get_value(key: String) -> Variant:
	for def in DEFINITIONS:
		if def[0] == key:
			return ProjectSettings.get_setting(path_of(def), def[2])
	return null
