extends "res://addons/crossindie_ads/providers/ad_provider.gd"

## Always-fill stand-in for AdMob in share_test (desktop has no AdMob).

var _ready: Dictionary = {}


func provider_name() -> String:
	return "fake"

func is_available() -> bool:
	return true

func supports(format: String) -> bool:
	return format == BANNER or format == INTERSTITIAL

func load_banner(_top: bool) -> void:
	loaded.emit(BANNER)

func load_interstitial() -> void:
	_ready[INTERSTITIAL] = true
	loaded.emit(INTERSTITIAL)

func is_interstitial_ready() -> bool:
	return bool(_ready.get(INTERSTITIAL, false))

func show_interstitial() -> void:
	_ready[INTERSTITIAL] = false
	opened.emit(INTERSTITIAL)
	closed.emit(INTERSTITIAL)
