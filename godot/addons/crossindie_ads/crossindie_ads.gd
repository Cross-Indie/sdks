extends Node

## CrossIndieAds - one ad API for Godot 4.2+ (autoload singleton).
##
## Each format walks a provider chain (default: AdMob -> CrossIndie). When a
## provider has no fill, errors, or does not exist on this platform (editor,
## desktop, iOS for now), the next one is tried, so the CrossIndie network
## fills the slot instead of leaving it empty.
##
##   CrossIndieAds.initialize({"crossindie_app_id": "...", "test_mode": true})
##   CrossIndieAds.show_banner("bottom")
##   CrossIndieAds.load_interstitial(); ... CrossIndieAds.show_interstitial()
##   CrossIndieAds.load_rewarded();     ... CrossIndieAds.show_rewarded()
##
## In every signal `provider` is the network that served the event ("admob",
## "crossindie", ...). `ad_failed` with provider == "" means the whole chain
## failed for that request.

signal initialized
signal consent_finished(can_request_ads: bool)

signal banner_loaded(provider: String)

signal interstitial_loaded(provider: String)
signal interstitial_opened(provider: String)
signal interstitial_closed(provider: String)

signal rewarded_loaded(provider: String)
signal rewarded_opened(provider: String)
signal rewarded_closed(provider: String)
signal rewarded_earned(amount: int, reward_type: String)

signal ad_clicked(format: String, provider: String)
signal ad_failed(format: String, provider: String, error: String)

const BANNER := "banner"
const INTERSTITIAL := "interstitial"
const REWARDED := "rewarded"
const VERSION := "0.1.0"

const Settings := preload("res://addons/crossindie_ads/settings.gd")
const ProviderBase := preload("res://addons/crossindie_ads/providers/ad_provider.gd")

var _config: Dictionary = {}
var _initialized: bool = false
## Available providers, in chain order.
var _providers: Array[ProviderBase] = []

# Banner state: index in _providers currently loading / currently shown.
var _banner_wanted: bool = false
var _banner_top: bool = false
var _banner_attempt: int = -1
var _banner_active: int = -1
var _banner_timer: Timer = null

# Fullscreen state per format: index currently loading (-1 = idle).
var _fs_attempt: Dictionary = {INTERSTITIAL: -1, REWARDED: -1}
var _fs_showing: Dictionary = {INTERSTITIAL: null, REWARDED: null}


# --------------------------------------------------------------------------- #
# Setup
# --------------------------------------------------------------------------- #

## Start the ad stack. `config` overrides Project Settings (crossindie_ads/*);
## keys: see settings.gd DEFINITIONS (e.g. "test_mode", "crossindie_app_id",
## "admob_android_banner_id", "rewarded_fallback_grants_reward", ...).
func initialize(config: Dictionary = {}) -> void:
	if _initialized:
		push_warning("CrossIndieAds.initialize() called twice; ignored.")
		return
	_config = Settings.load_all()
	for k in config:
		_config[k] = config[k]
	_initialized = true

	_banner_timer = Timer.new()
	_banner_timer.one_shot = true
	_banner_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_banner_timer.timeout.connect(_on_banner_timer)
	add_child(_banner_timer)

	var chain: PackedStringArray = String(_config.get("provider_chain", "admob,crossindie")).split(",", false)
	for raw in chain:
		var pname: String = raw.strip_edges()
		var path: String = _provider_script_path(pname)
		if path.is_empty():
			push_warning("CrossIndieAds: unknown provider '%s' in provider_chain" % pname)
			continue
		var script: Script = load(path) as Script
		var p: ProviderBase = script.new() as ProviderBase
		p.name = "Provider_" + pname
		add_child(p)
		p.setup(_config)
		if not p.is_available():
			print_verbose("CrossIndieAds: provider '%s' not available on this platform, skipped" % pname)
			p.queue_free()
			continue
		_providers.append(p)
		p.loaded.connect(_on_loaded.bind(p), CONNECT_DEFERRED)
		p.load_failed.connect(_on_load_failed.bind(p), CONNECT_DEFERRED)
		p.opened.connect(_on_opened.bind(p), CONNECT_DEFERRED)
		p.closed.connect(_on_closed.bind(p), CONNECT_DEFERRED)
		p.show_failed.connect(_on_show_failed.bind(p), CONNECT_DEFERRED)
		p.clicked.connect(_on_clicked.bind(p), CONNECT_DEFERRED)
		p.earned.connect(_on_earned.bind(p), CONNECT_DEFERRED)
		p.consent_finished.connect(_on_consent.bind(p), CONNECT_DEFERRED)

	if _providers.is_empty():
		push_warning("CrossIndieAds: no ad provider available (is addons/cross_indie installed?)")
	initialized.emit.call_deferred()


## Script for a provider id. Add new networks here.
func _provider_script_path(provider_id: String) -> String:
	match provider_id:
		"admob":
			if OS.get_name() == "iOS":
				return "res://addons/crossindie_ads/providers/admob_ios_provider.gd"
			return "res://addons/crossindie_ads/providers/admob_android_provider.gd"
		"crossindie":
			return "res://addons/crossindie_ads/providers/crossindie_provider.gd"
		"applovin_max":
			return "res://addons/crossindie_ads/providers/applovin_max_provider.gd"
	return ""


func is_initialized() -> bool:
	return _initialized


## Provider ids that are live on this platform, in chain order.
func get_active_providers() -> PackedStringArray:
	var out := PackedStringArray()
	for p in _providers:
		out.append(p.provider_name())
	return out


func is_test_mode() -> bool:
	return bool(_config.get("test_mode", true))


## True if the user must be offered a privacy/consent settings entry point.
func is_privacy_options_required() -> bool:
	for p in _providers:
		if p.is_privacy_options_required():
			return true
	return false


## Re-open the consent form (GDPR "Privacy settings" button).
func show_privacy_options() -> void:
	for p in _providers:
		if p.is_privacy_options_required():
			p.show_privacy_options()
			return


func _require_init(format: String) -> bool:
	if _initialized:
		return true
	push_error("CrossIndieAds: call initialize() before using %s ads" % format)
	ad_failed.emit(format, "", "not initialized")
	return false


func _next_supporting(format: String, from: int, before: int = -1) -> int:
	var end: int = _providers.size() if before < 0 else mini(before, _providers.size())
	for i in range(from, end):
		if _providers[i].supports(format):
			return i
	return -1


# --------------------------------------------------------------------------- #
# Banner
# --------------------------------------------------------------------------- #

## Show a banner anchored to "top" or "bottom". Loads if needed; falls back
## down the chain on no-fill and periodically retries better providers.
func show_banner(position: String = "bottom") -> void:
	if not _require_init(BANNER):
		return
	var top: bool = position.to_lower() == "top"
	_banner_wanted = true
	if _banner_active >= 0 and top == _banner_top:
		_providers[_banner_active].show_banner()
		return
	if _banner_active >= 0 or _banner_attempt >= 0:
		_destroy_all_banners()
	_banner_top = top
	_try_banner(_next_supporting(BANNER, 0))


func hide_banner() -> void:
	_banner_wanted = false
	if _banner_active >= 0:
		_providers[_banner_active].hide_banner()


## Hide and free the banner on every provider.
func destroy_banner() -> void:
	_banner_wanted = false
	_destroy_all_banners()


func is_banner_visible() -> bool:
	return _banner_wanted and _banner_active >= 0


## Banner height in physical screen pixels (0 when hidden), e.g. to push UI up.
func get_banner_height_px() -> int:
	if not is_banner_visible():
		return 0
	return _providers[_banner_active].banner_height_px()


func _destroy_all_banners() -> void:
	for p in _providers:
		p.destroy_banner()
	_banner_active = -1
	_banner_attempt = -1
	if _banner_timer != null:
		_banner_timer.stop()


func _try_banner(index: int) -> void:
	_banner_attempt = index
	if index < 0:
		return
	_providers[index].load_banner(_banner_top)


func _banner_loaded(index: int) -> void:
	if index != _banner_attempt:
		return  # stale or refresh of the active one
	_banner_attempt = -1
	if _banner_active >= 0 and _banner_active != index:
		_providers[_banner_active].destroy_banner()
	_banner_active = index
	var p: ProviderBase = _providers[index]
	if _banner_wanted:
		p.show_banner()
	else:
		p.hide_banner()
	banner_loaded.emit(p.provider_name())
	if index > 0:
		_schedule_banner_retry()  # try to upgrade to a better provider later


func _banner_failed(index: int, error: String) -> void:
	ad_failed.emit(BANNER, _providers[index].provider_name(), error)
	if index != _banner_attempt:
		return  # failure of the active provider's refresh: keep showing it
	# Only providers ranked above the one on screen are worth trying.
	var next: int = _next_supporting(BANNER, index + 1, _banner_active)
	if next >= 0:
		_try_banner(next)
		return
	_banner_attempt = -1
	if _banner_active < 0:
		ad_failed.emit(BANNER, "", "no fill from any provider")
	_schedule_banner_retry()


func _schedule_banner_retry() -> void:
	if _banner_timer == null:
		return
	_banner_timer.start(float(_config.get("banner_retry_sec", 60.0)))


func _on_banner_timer() -> void:
	if not _banner_wanted or _banner_attempt >= 0:
		return
	if _banner_active == 0:
		return  # already on the best provider
	var first: int = _next_supporting(BANNER, 0, _banner_active)
	if first >= 0:
		_try_banner(first)


# --------------------------------------------------------------------------- #
# Interstitial / rewarded
# --------------------------------------------------------------------------- #

func load_interstitial() -> void:
	_load_fullscreen(INTERSTITIAL)

func is_interstitial_ready() -> bool:
	return _ready_provider(INTERSTITIAL) != null

## Shows the best ready interstitial. Returns false (and emits ad_failed) if
## none is ready; with auto_reload a new load is started in that case.
func show_interstitial() -> bool:
	return _show_fullscreen(INTERSTITIAL)

func load_rewarded() -> void:
	_load_fullscreen(REWARDED)

func is_rewarded_ready() -> bool:
	return _ready_provider(REWARDED) != null

## Shows the best ready rewarded ad. Grant the reward on `rewarded_earned`,
## never on `rewarded_closed`.
func show_rewarded() -> bool:
	return _show_fullscreen(REWARDED)


func _load_fullscreen(format: String) -> void:
	if not _require_init(format):
		return
	if int(_fs_attempt[format]) >= 0:
		return  # already loading
	if _ready_provider(format) != null:
		_emit_loaded(format, _ready_provider(format))
		return
	var first: int = _next_supporting(format, 0)
	if first < 0:
		ad_failed.emit(format, "", "no provider supports %s" % format)
		return
	_fs_attempt[format] = first
	_call_load(format, _providers[first])


func _call_load(format: String, p: ProviderBase) -> void:
	if format == INTERSTITIAL:
		p.load_interstitial()
	else:
		p.load_rewarded()


func _is_ready(format: String, p: ProviderBase) -> bool:
	if format == INTERSTITIAL:
		return p.is_interstitial_ready()
	return p.is_rewarded_ready()


func _ready_provider(format: String) -> ProviderBase:
	for p in _providers:
		if p.supports(format) and _is_ready(format, p):
			return p
	return null


func _show_fullscreen(format: String) -> bool:
	if not _require_init(format):
		return false
	var p: ProviderBase = _ready_provider(format)
	if p == null:
		ad_failed.emit(format, "", "no %s ready" % format)
		if bool(_config.get("auto_reload", true)):
			_load_fullscreen(format)
		return false
	_fs_showing[format] = p
	if format == INTERSTITIAL:
		p.show_interstitial()
	else:
		p.show_rewarded()
	return true


func _fullscreen_loaded(format: String, index: int) -> void:
	if index == int(_fs_attempt[format]):
		_fs_attempt[format] = -1
	_emit_loaded(format, _providers[index])


func _emit_loaded(format: String, p: ProviderBase) -> void:
	if format == INTERSTITIAL:
		interstitial_loaded.emit(p.provider_name())
	else:
		rewarded_loaded.emit(p.provider_name())


func _fullscreen_failed(format: String, index: int, error: String) -> void:
	ad_failed.emit(format, _providers[index].provider_name(), error)
	if index != int(_fs_attempt[format]):
		return
	var next: int = _next_supporting(format, index + 1)
	if next >= 0:
		_fs_attempt[format] = next
		_call_load(format, _providers[next])
	else:
		_fs_attempt[format] = -1
		ad_failed.emit(format, "", "no fill from any provider")


# --------------------------------------------------------------------------- #
# Provider signal routing
# --------------------------------------------------------------------------- #

func _on_loaded(format: String, p: ProviderBase) -> void:
	var i: int = _providers.find(p)
	if i < 0:
		return
	if format == BANNER:
		_banner_loaded(i)
	else:
		_fullscreen_loaded(format, i)


func _on_load_failed(format: String, error: String, p: ProviderBase) -> void:
	var i: int = _providers.find(p)
	if i < 0:
		return
	if format == BANNER:
		_banner_failed(i, error)
	else:
		_fullscreen_failed(format, i, error)


func _on_opened(format: String, p: ProviderBase) -> void:
	if format == INTERSTITIAL:
		interstitial_opened.emit(p.provider_name())
	elif format == REWARDED:
		rewarded_opened.emit(p.provider_name())


func _on_closed(format: String, p: ProviderBase) -> void:
	if format == BANNER:
		return
	_fs_showing[format] = null
	if format == INTERSTITIAL:
		interstitial_closed.emit(p.provider_name())
	else:
		rewarded_closed.emit(p.provider_name())
	if bool(_config.get("auto_reload", true)):
		_load_fullscreen(format)


func _on_show_failed(format: String, error: String, p: ProviderBase) -> void:
	ad_failed.emit(format, p.provider_name(), error)
	_fs_showing[format] = null
	# Another provider may have one ready (e.g. CrossIndie preloaded earlier).
	var other: ProviderBase = _ready_provider(format)
	if other != null and other != p:
		_show_fullscreen(format)
	elif bool(_config.get("auto_reload", true)):
		_load_fullscreen(format)


func _on_clicked(format: String, p: ProviderBase) -> void:
	ad_clicked.emit(format, p.provider_name())


func _on_earned(amount: int, reward_type: String, _p: ProviderBase) -> void:
	rewarded_earned.emit(amount, reward_type)


func _on_consent(can_request_ads: bool, error: String, _p: ProviderBase) -> void:
	if not error.is_empty():
		print_verbose("CrossIndieAds consent: " + error)
	consent_finished.emit(can_request_ads)
