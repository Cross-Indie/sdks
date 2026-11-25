extends Node

## crossindie_share / prefer routing with a fake always-fill network ahead of
## CrossIndie. Needs tests/mock_server.py on 127.0.0.1:8765:
##   godot --headless --path . res://tests/share_test.tscn

const BASE := "http://127.0.0.1:8765"

var _fails: PackedStringArray = []


func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(func() -> void: _done(["timeout"]))
	CrossIndieAds.initialize({
		"provider_chain": "res://tests/fake_network_provider.gd,crossindie",
		"crossindie_app_id": "smoke",
		"crossindie_base_url": BASE,
		"auto_reload": false,
		"fallback_close_delay_sec": 0.5,
		"crossindie_share": 0,
	})
	await CrossIndieAds.initialized
	_check("chain", ",".join(CrossIndieAds.get_active_providers()), "fake,crossindie")

	# share 0: the fake network serves everything.
	CrossIndieAds.load_interstitial()
	_check("share0 interstitial", await CrossIndieAds.interstitial_loaded, "fake")
	CrossIndieAds.show_interstitial()
	_check("share0 closed", await CrossIndieAds.interstitial_closed, "fake")

	# prefer "crossindie" goes first even with share 0.
	CrossIndieAds.load_interstitial("crossindie")
	_check("prefer interstitial", await CrossIndieAds.interstitial_loaded, "crossindie")
	CrossIndieAds.show_interstitial()
	_check("prefer opened", await CrossIndieAds.interstitial_opened, "crossindie")
	await get_tree().create_timer(1.5).timeout
	_press_close()
	_check("prefer closed", await CrossIndieAds.interstitial_closed, "crossindie")

	# share 100 -> CrossIndie; prefer "fake" opts this placement out.
	CrossIndieAds._config["crossindie_share"] = 100
	CrossIndieAds.load_interstitial("fake")
	_check("opt-out interstitial", await CrossIndieAds.interstitial_loaded, "fake")
	CrossIndieAds.show_interstitial()
	await CrossIndieAds.interstitial_closed
	CrossIndieAds.load_interstitial()
	_check("share100 interstitial", await CrossIndieAds.interstitial_loaded, "crossindie")

	CrossIndieAds.show_banner("bottom")
	_check("share100 banner", await CrossIndieAds.banner_loaded, "crossindie")
	CrossIndieAds.destroy_banner()
	CrossIndieAds._config["crossindie_share"] = 0
	CrossIndieAds.show_banner("top")
	_check("share0 banner", await CrossIndieAds.banner_loaded, "fake")
	CrossIndieAds.destroy_banner()

	# Share turn with no CrossIndie fill falls back to the fake network.
	CrossIndieAds._config["crossindie_app_id"] = "nofill"
	CrossIndieAds.show_banner("bottom", "crossindie")
	_check("nofill banner", await CrossIndieAds.banner_loaded, "fake")
	_done(_fails)


func _check(what: String, got: Variant, want: Variant) -> void:
	print("[share] %s: %s" % [what, got])
	if got != want:
		_fails.append("%s: got %s want %s" % [what, got, want])


func _press_close() -> void:
	for b in get_tree().root.find_children("*", "Button", true, false):
		var btn: Button = b as Button
		if btn.is_visible_in_tree() and btn.text.strip_edges() == "X":
			btn.pressed.emit()
			return


func _done(fails: PackedStringArray) -> void:
	if fails.is_empty():
		print("[share] PASS")
		get_tree().quit(0)
	else:
		print("[share] FAIL: ", "; ".join(fails))
		get_tree().quit(1)
