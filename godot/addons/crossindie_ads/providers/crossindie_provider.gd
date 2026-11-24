extends "res://addons/crossindie_ads/providers/ad_provider.gd"

## CrossIndie cross-promotion network as the always-available fallback.
##
## Reuses the stock CrossIndieBanner node from res://addons/cross_indie/
## (composition, never modified): it already does fetch -> signed
## tracking_token -> impression after >= min_display_ms while focused ->
## click tracking. This provider only places it on screen:
##   banner       : CanvasLayer strip at the top/bottom of the screen,
##   interstitial : full-screen overlay, close button after a short delay,
##   rewarded     : same overlay, reward granted after a minimum visible time.

const BANNER_SCRIPT_PATH := "res://addons/cross_indie/CrossIndieBanner.gd"
const FullscreenAd := preload("res://addons/crossindie_ads/fullscreen_ad.gd")

const BANNER_LAYER := 100
const BANNER_HEIGHT := 90.0

var _banner_script: Script = null

var _banner_layer: CanvasLayer = null
var _banner: Control = null
var _banner_wanted: bool = false
var _banner_has_ad: bool = false
var _refresh_timer: Timer = null

var _fullscreen: Dictionary = {}  # format -> FullscreenAd (loaded or loading)
var _fullscreen_ready: Dictionary = {}  # format -> bool


func provider_name() -> String:
	return "crossindie"


func is_available() -> bool:
	return _banner_script != null


func supports(format: String) -> bool:
	return format == BANNER or format == INTERSTITIAL or format == REWARDED


func setup(cfg: Dictionary) -> void:
	super.setup(cfg)
	if ResourceLoader.exists(BANNER_SCRIPT_PATH):
		_banner_script = load(BANNER_SCRIPT_PATH) as Script
	if _banner_script == null:
		push_warning("CrossIndie Ads: %s not found. Install addons/cross_indie next to addons/crossindie_ads to enable the CrossIndie fallback." % BANNER_SCRIPT_PATH)


## A configured CrossIndieBanner, not yet in the tree (auto_load off: we decide
## when to fetch). Returns null + reason through `error` when misconfigured.
func make_banner(format_name: String) -> Control:
	var b: Control = _banner_script.new() as Control
	b.set("api_base", String(config.get("crossindie_base_url", "https://api.crossindie.com")))
	b.set("app_id", String(config.get("crossindie_app_id", "")))
	b.set("category", String(config.get("crossindie_category", "game")))
	b.set("auto_load", false)
	b.set("banner_format", format_name)
	return b


func _app_id_missing(format: String) -> bool:
	if String(config.get("crossindie_app_id", "")).strip_edges().is_empty():
		load_failed.emit(format, "crossindie app_id not set")
		return true
	return false


# --- banner ---------------------------------------------------------------
func load_banner(top: bool) -> void:
	if _app_id_missing(BANNER):
		return
	destroy_banner()
	_banner_wanted = true
	_banner_has_ad = false

	_banner_layer = CanvasLayer.new()
	_banner_layer.layer = BANNER_LAYER
	_banner_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_banner_layer)

	_banner = make_banner("banner")
	_banner.visible = false
	_banner_layer.add_child(_banner)
	# Full-width strip anchored to the requested edge (after _ready built it).
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.0 if top else 1.0
	_banner.anchor_bottom = 0.0 if top else 1.0
	_banner.offset_left = 0.0
	_banner.offset_right = 0.0
	_banner.offset_top = 0.0 if top else -BANNER_HEIGHT
	_banner.offset_bottom = BANNER_HEIGHT if top else 0.0

	_banner.connect("ad_loaded", _on_banner_loaded)
	_banner.connect("ad_failed", _on_banner_failed)
	_banner.connect("clicked", func() -> void: clicked.emit(BANNER))

	var refresh: float = float(config.get("crossindie_banner_refresh_sec", 60.0))
	if refresh > 0.0:
		_refresh_timer = Timer.new()
		_refresh_timer.wait_time = refresh
		_refresh_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_refresh_timer.timeout.connect(_on_refresh)
		_banner_layer.add_child(_refresh_timer)

	_banner.call("load_ad")


func _on_banner_loaded(_ad_name: String) -> void:
	var first: bool = not _banner_has_ad
	_banner_has_ad = true
	if _banner != null:
		_banner.visible = _banner_wanted
	if _refresh_timer != null and _refresh_timer.is_stopped():
		_refresh_timer.start()
	if first:
		loaded.emit(BANNER)


func _on_banner_failed(reason: String) -> void:
	# A failed refresh keeps the previous creative on screen; only the first
	# load counts as a provider failure.
	if not _banner_has_ad:
		load_failed.emit(BANNER, reason)


func _on_refresh() -> void:
	if _banner != null and _banner_wanted and _banner.is_visible_in_tree():
		_banner.call("load_ad")


func show_banner() -> void:
	_banner_wanted = true
	if _banner != null:
		_banner.visible = _banner_has_ad


func hide_banner() -> void:
	_banner_wanted = false
	if _banner != null:
		_banner.visible = false


func destroy_banner() -> void:
	_banner_wanted = false
	_banner_has_ad = false
	if _banner_layer != null:
		_banner_layer.queue_free()
	_banner_layer = null
	_banner = null
	_refresh_timer = null


func banner_height_px() -> int:
	if _banner == null or not _banner.is_visible_in_tree():
		return 0
	var scale: float = _banner.get_viewport().get_final_transform().get_scale().y
	return int(round(_banner.size.y * scale))


# --- interstitial / rewarded ---------------------------------------------
func load_interstitial() -> void:
	_load_fullscreen(INTERSTITIAL)

func is_interstitial_ready() -> bool:
	return bool(_fullscreen_ready.get(INTERSTITIAL, false))

func show_interstitial() -> void:
	_show_fullscreen(INTERSTITIAL)

func load_rewarded() -> void:
	_load_fullscreen(REWARDED)

func is_rewarded_ready() -> bool:
	return bool(_fullscreen_ready.get(REWARDED, false))

func show_rewarded() -> void:
	_show_fullscreen(REWARDED)


func _load_fullscreen(format: String) -> void:
	if _app_id_missing(format):
		return
	_free_fullscreen(format)
	var ad: CanvasLayer = FullscreenAd.new()
	ad.set("rewarded", format == REWARDED)
	ad.set("close_delay_sec", float(config.get("fallback_close_delay_sec", 3.0)))
	ad.set("reward_delay_sec", float(config.get("fallback_reward_delay_sec", 5.0)))
	ad.set("grant_reward", bool(config.get("rewarded_fallback_grants_reward", false)))
	ad.set("reward_amount", int(config.get("fallback_reward_amount", 1)))
	ad.set("reward_type", String(config.get("fallback_reward_type", "reward")))
	_fullscreen[format] = ad
	_fullscreen_ready[format] = false
	add_child(ad)

	ad.connect("ad_ready", func() -> void:
		_fullscreen_ready[format] = true
		loaded.emit(format))
	ad.connect("ad_failed", func(reason: String) -> void:
		_free_fullscreen(format)
		load_failed.emit(format, reason))
	ad.connect("opened", func() -> void: opened.emit(format))
	ad.connect("clicked", func() -> void: clicked.emit(format))
	ad.connect("earned", func(amount: int, type: String) -> void: earned.emit(amount, type))
	ad.connect("closed", func() -> void:
		_free_fullscreen(format)
		closed.emit(format))

	ad.call("begin_load", make_banner("image"))


func _show_fullscreen(format: String) -> void:
	if not bool(_fullscreen_ready.get(format, false)):
		show_failed.emit(format, "crossindie %s not loaded" % format)
		return
	_fullscreen_ready[format] = false
	var ad: CanvasLayer = _fullscreen[format]
	ad.call("present")


func _free_fullscreen(format: String) -> void:
	if _fullscreen.has(format):
		var ad: Node = _fullscreen[format]
		if is_instance_valid(ad):
			ad.queue_free()
		_fullscreen.erase(format)
	_fullscreen_ready[format] = false
