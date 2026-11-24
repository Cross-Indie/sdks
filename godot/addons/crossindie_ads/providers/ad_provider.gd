extends Node

## Base class for one ad network adapter in the CrossIndieAds provider chain.
##
## The facade (crossindie_ads.gd) asks providers in chain order and falls
## through to the next one on any load failure. To add a network (AppLovin MAX,
## iOS AdMob, ...): extend this script, override what the network supports,
## and register it in crossindie_ads.gd `_provider_script_path()`.
##
## Rules for implementations:
## - never block; report outcomes only through the signals below,
## - `format` is one of "banner", "interstitial", "rewarded",
## - signals may be emitted from inside a call; the facade connects deferred.

signal loaded(format: String)
signal load_failed(format: String, error: String)
signal opened(format: String)
signal closed(format: String)
signal show_failed(format: String, error: String)
signal clicked(format: String)
signal earned(amount: int, reward_type: String)
## Consent flow finished (only providers that run one, e.g. AdMob/UMP).
signal consent_finished(can_request_ads: bool, error: String)

const BANNER := "banner"
const INTERSTITIAL := "interstitial"
const REWARDED := "rewarded"

var config: Dictionary = {}


## Short id used in signals, e.g. "admob", "crossindie".
func provider_name() -> String:
	return "base"


## False when the network cannot run here (no native plugin, unsupported OS,
## missing dependency). Unavailable providers are silently skipped.
func is_available() -> bool:
	return false


## Called once, right after the provider is added to the tree.
func setup(cfg: Dictionary) -> void:
	config = cfg


func supports(format: String) -> bool:
	return false


# --- banner ---------------------------------------------------------------
func load_banner(top: bool) -> void:
	load_failed.emit(BANNER, "not supported")

func show_banner() -> void:
	pass

func hide_banner() -> void:
	pass

func destroy_banner() -> void:
	pass

## Height of the visible banner in physical screen pixels (0 if none).
func banner_height_px() -> int:
	return 0


# --- interstitial ---------------------------------------------------------
func load_interstitial() -> void:
	load_failed.emit(INTERSTITIAL, "not supported")

func is_interstitial_ready() -> bool:
	return false

func show_interstitial() -> void:
	show_failed.emit(INTERSTITIAL, "not supported")


# --- rewarded -------------------------------------------------------------
func load_rewarded() -> void:
	load_failed.emit(REWARDED, "not supported")

func is_rewarded_ready() -> bool:
	return false

func show_rewarded() -> void:
	show_failed.emit(REWARDED, "not supported")


# --- privacy (optional) ---------------------------------------------------
func is_privacy_options_required() -> bool:
	return false

func show_privacy_options() -> void:
	pass
