extends Node

## Desktop smoke test of the CrossIndie fallback path (no AdMob on desktop).
## Needs tests/mock_server.py on 127.0.0.1:8765. Prints PASS/FAIL and exits
## with code 0/1:
##   godot --headless --path . res://tests/smoke_test.tscn
##   godot --headless --path . res://tests/smoke_test.tscn -- --nofill
## The --nofill run checks that a chain with no fill fails cleanly.

const BASE := "http://127.0.0.1:8765"

var _events: PackedStringArray = []
var _earned: int = 0
var _nofill: bool = OS.get_cmdline_user_args().has("--nofill")


func _ready() -> void:
	CrossIndieAds.initialized.connect(_on_init)
	CrossIndieAds.banner_loaded.connect(func(p: String) -> void: _ev("banner_loaded:" + p))
	CrossIndieAds.interstitial_loaded.connect(func(p: String) -> void: _ev("interstitial_loaded:" + p))
	CrossIndieAds.interstitial_opened.connect(func(p: String) -> void: _ev("interstitial_opened:" + p))
	CrossIndieAds.interstitial_closed.connect(func(p: String) -> void: _ev("interstitial_closed:" + p))
	CrossIndieAds.rewarded_loaded.connect(func(p: String) -> void: _ev("rewarded_loaded:" + p))
	CrossIndieAds.rewarded_opened.connect(func(p: String) -> void: _ev("rewarded_opened:" + p))
	CrossIndieAds.rewarded_closed.connect(func(p: String) -> void: _ev("rewarded_closed:" + p))
	CrossIndieAds.rewarded_earned.connect(func(a: int, t: String) -> void:
		_earned += a
		_ev("rewarded_earned:%d:%s" % [a, t]))
	CrossIndieAds.ad_failed.connect(func(f: String, p: String, e: String) -> void: _ev("ad_failed:%s:%s:%s" % [f, p, e]))
	CrossIndieAds.initialize({
		"test_mode": true,
		"crossindie_app_id": "nofill" if _nofill else "smoke",
		"crossindie_base_url": BASE,
		"fallback_close_delay_sec": 1.0,
		"fallback_reward_delay_sec": 2.0,
		"rewarded_fallback_grants_reward": true,  # exercise the reward path (default is off)
	})
	get_tree().create_timer(30.0).timeout.connect(func() -> void: _finish("timeout"))


func _ev(s: String) -> void:
	print("[smoke] ", s)
	_events.append(s)


func _on_init() -> void:
	_ev("initialized:" + ",".join(CrossIndieAds.get_active_providers()))
	if _nofill:
		CrossIndieAds.show_banner("top")
		CrossIndieAds.load_rewarded()
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			_ev("show_rewarded:%s" % CrossIndieAds.show_rewarded())
			_finish("done"))
		return
	CrossIndieAds.show_banner("bottom")
	CrossIndieAds.interstitial_loaded.connect(_show_inter, CONNECT_ONE_SHOT)
	CrossIndieAds.load_interstitial()


func _show_inter(_p: String) -> void:
	var ok: bool = CrossIndieAds.show_interstitial()
	_ev("show_interstitial:%s" % ok)
	# The close button appears after 1s; press it after 2s.
	get_tree().create_timer(2.0).timeout.connect(_press_close)
	CrossIndieAds.interstitial_closed.connect(func(_x: String) -> void:
		CrossIndieAds.rewarded_loaded.connect(_show_rewarded, CONNECT_ONE_SHOT)
		CrossIndieAds.load_rewarded(), CONNECT_ONE_SHOT)


func _show_rewarded(_p: String) -> void:
	var ok: bool = CrossIndieAds.show_rewarded()
	_ev("show_rewarded:%s" % ok)
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		_press_close()
		get_tree().create_timer(1.0).timeout.connect(func() -> void: _finish("done")))


## Press the visible fallback overlay's close button like a user would.
func _press_close() -> void:
	for b in get_tree().root.find_children("*", "Button", true, false):
		var btn: Button = b as Button
		if btn.is_visible_in_tree() and btn.text.strip_edges() == "X":
			btn.pressed.emit()
			_ev("pressed_close")
			return
	_ev("close_button_not_visible")


func _finish(why: String) -> void:
	var need: PackedStringArray = [
		"initialized:crossindie",
		"banner_loaded:crossindie",
		"interstitial_loaded:crossindie",
		"interstitial_opened:crossindie",
		"interstitial_closed:crossindie",
		"rewarded_loaded:crossindie",
		"rewarded_opened:crossindie",
		"rewarded_earned:1:reward",
		"rewarded_closed:crossindie",
	]
	if _nofill:
		need = [
			"initialized:crossindie",
			"ad_failed:banner:crossindie:no eligible ads available",
			"ad_failed:banner::no fill from any provider",
			"ad_failed:rewarded:crossindie:no eligible ads available",
			"ad_failed:rewarded::no fill from any provider",
			"show_rewarded:false",
		]
	var missing: PackedStringArray = []
	for n in need:
		if not _events.has(n):
			missing.append(n)
	if missing.is_empty() and why == "done":
		print("[smoke] PASS")
		get_tree().quit(0)
	else:
		print("[smoke] FAIL (%s) missing: %s" % [why, ", ".join(missing)])
		get_tree().quit(1)
