extends "res://addons/crossindie_ads/providers/ad_provider.gd"

## Google AdMob on Android, via the CrossIndieAdsAndroid native plugin (AAR in
## addons/crossindie_ads/bin, source in crossindie_ads_android/). Every native
## call is dispatched to the Android UI thread by the plugin and every native
## signal arrives back on Godot's main thread.

const Settings := preload("res://addons/crossindie_ads/settings.gd")
const SINGLETON := "CrossIndieAdsAndroid"

var _native: Object = null
var _sdk_ready: bool = false
## Load calls made before MobileAds finished initializing (replayed after).
var _queued: Array[Callable] = []


func provider_name() -> String:
	return "admob"


func is_available() -> bool:
	return OS.get_name() == "Android" and Engine.has_singleton(SINGLETON)


func supports(format: String) -> bool:
	return format == BANNER or format == INTERSTITIAL or format == REWARDED


func setup(cfg: Dictionary) -> void:
	super.setup(cfg)
	if not is_available():
		return
	_native = Engine.get_singleton(SINGLETON)
	_native.connect("initialized", _on_initialized)
	_native.connect("consent_finished", func(can: bool, err: String) -> void: consent_finished.emit(can, err))

	_native.connect("banner_loaded", func() -> void: loaded.emit(BANNER))
	_native.connect("banner_failed_to_load", func(code: int, msg: String) -> void: load_failed.emit(BANNER, _err(code, msg)))
	_native.connect("banner_clicked", func() -> void: clicked.emit(BANNER))

	_native.connect("interstitial_loaded", func() -> void: loaded.emit(INTERSTITIAL))
	_native.connect("interstitial_failed_to_load", func(code: int, msg: String) -> void: load_failed.emit(INTERSTITIAL, _err(code, msg)))
	_native.connect("interstitial_opened", func() -> void: opened.emit(INTERSTITIAL))
	_native.connect("interstitial_closed", func() -> void: closed.emit(INTERSTITIAL))
	_native.connect("interstitial_failed_to_show", func(code: int, msg: String) -> void: show_failed.emit(INTERSTITIAL, _err(code, msg)))
	_native.connect("interstitial_clicked", func() -> void: clicked.emit(INTERSTITIAL))

	_native.connect("rewarded_loaded", func() -> void: loaded.emit(REWARDED))
	_native.connect("rewarded_failed_to_load", func(code: int, msg: String) -> void: load_failed.emit(REWARDED, _err(code, msg)))
	_native.connect("rewarded_opened", func() -> void: opened.emit(REWARDED))
	_native.connect("rewarded_closed", func() -> void: closed.emit(REWARDED))
	_native.connect("rewarded_failed_to_show", func(code: int, msg: String) -> void: show_failed.emit(REWARDED, _err(code, msg)))
	_native.connect("rewarded_clicked", func() -> void: clicked.emit(REWARDED))
	_native.connect("rewarded_earned", func(amount: int, type: String) -> void: earned.emit(amount, type))

	var test_mode: bool = bool(cfg.get("test_mode", true))
	_native.call("initialize",
		test_mode,
		String(cfg.get("admob_test_device_ids", "")),
		bool(cfg.get("admob_request_consent", true)),
		bool(cfg.get("admob_debug_eea", false)))


func _on_initialized() -> void:
	_sdk_ready = true
	var calls: Array[Callable] = _queued.duplicate()
	_queued.clear()
	for c in calls:
		c.call()


## Run now if MobileAds is initialized, else after. Loads before init would
## race the SDK's adapter setup.
func _when_ready(c: Callable) -> void:
	if _sdk_ready:
		c.call()
	else:
		_queued.append(c)


## Unit id for a format: Google's official test ids in test mode, otherwise the
## configured id ("" -> load fails -> the chain falls back to CrossIndie).
func _unit(format: String) -> String:
	if bool(config.get("test_mode", true)):
		match format:
			BANNER: return Settings.TEST_ANDROID_BANNER
			INTERSTITIAL: return Settings.TEST_ANDROID_INTERSTITIAL
			REWARDED: return Settings.TEST_ANDROID_REWARDED
	return String(config.get("admob_android_%s_id" % format, "")).strip_edges()


func _err(code: int, msg: String) -> String:
	return "%d: %s" % [code, msg]


# --- banner ---------------------------------------------------------------
func load_banner(top: bool) -> void:
	var unit: String = _unit(BANNER)
	if unit.is_empty():
		load_failed.emit(BANNER, "no AdMob banner unit id configured")
		return
	_when_ready(func() -> void: _native.call("loadBanner", unit, top))

func show_banner() -> void:
	_native.call("showBanner")

func hide_banner() -> void:
	_native.call("hideBanner")

func destroy_banner() -> void:
	_native.call("destroyBanner")

func banner_height_px() -> int:
	return int(_native.call("getBannerHeightPx"))


# --- interstitial ---------------------------------------------------------
func load_interstitial() -> void:
	var unit: String = _unit(INTERSTITIAL)
	if unit.is_empty():
		load_failed.emit(INTERSTITIAL, "no AdMob interstitial unit id configured")
		return
	_when_ready(func() -> void: _native.call("loadInterstitial", unit))

func is_interstitial_ready() -> bool:
	return bool(_native.call("isInterstitialReady"))

func show_interstitial() -> void:
	_native.call("showInterstitial")


# --- rewarded -------------------------------------------------------------
func load_rewarded() -> void:
	var unit: String = _unit(REWARDED)
	if unit.is_empty():
		load_failed.emit(REWARDED, "no AdMob rewarded unit id configured")
		return
	_when_ready(func() -> void: _native.call("loadRewarded", unit))

func is_rewarded_ready() -> bool:
	return bool(_native.call("isRewardedReady"))

func show_rewarded() -> void:
	_native.call("showRewarded")


# --- privacy --------------------------------------------------------------
func is_privacy_options_required() -> bool:
	return bool(_native.call("isPrivacyOptionsRequired"))

func show_privacy_options() -> void:
	_native.call("showPrivacyOptionsForm")
