extends Control

## Minimal button panel exercising every CrossIndieAds call.
## Set your CrossIndie app id below (or in Project Settings > crossindie_ads)
## to see the fallback fill on desktop / when AdMob has no fill.

const CROSSINDIE_APP_ID := ""

var _log: Label


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 40
	box.offset_right = -40
	box.offset_top = 160
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	_add_button(box, "Banner top", func() -> void: CrossIndieAds.show_banner("top"))
	_add_button(box, "Banner bottom", func() -> void: CrossIndieAds.show_banner("bottom"))
	_add_button(box, "Banner bottom (CrossIndie first)", func() -> void:
		CrossIndieAds.destroy_banner()
		CrossIndieAds.show_banner("bottom", "crossindie"))
	_add_button(box, "Hide banner", func() -> void: CrossIndieAds.hide_banner())
	_add_button(box, "Load interstitial", func() -> void: CrossIndieAds.load_interstitial())
	_add_button(box, "Show interstitial", func() -> void: CrossIndieAds.show_interstitial())
	_add_button(box, "Load rewarded", func() -> void: CrossIndieAds.load_rewarded())
	_add_button(box, "Show rewarded", func() -> void: CrossIndieAds.show_rewarded())

	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_log)

	CrossIndieAds.initialized.connect(func() -> void: _say("initialized, providers: %s" % ", ".join(CrossIndieAds.get_active_providers())))
	CrossIndieAds.consent_finished.connect(func(can: bool) -> void: _say("consent finished, can request ads: %s" % can))
	CrossIndieAds.banner_loaded.connect(func(p: String) -> void: _say("banner loaded via " + p))
	CrossIndieAds.interstitial_loaded.connect(func(p: String) -> void: _say("interstitial ready via " + p))
	CrossIndieAds.interstitial_closed.connect(func(p: String) -> void: _say("interstitial closed (" + p + ")"))
	CrossIndieAds.rewarded_loaded.connect(func(p: String) -> void: _say("rewarded ready via " + p))
	CrossIndieAds.rewarded_earned.connect(func(amount: int, type: String) -> void: _say("REWARD %d %s" % [amount, type]))
	CrossIndieAds.rewarded_closed.connect(func(p: String) -> void: _say("rewarded closed (" + p + ")"))
	CrossIndieAds.ad_failed.connect(func(f: String, p: String, e: String) -> void: _say("failed %s/%s: %s" % [f, p if not p.is_empty() else "chain", e]))

	var cfg: Dictionary = {"test_mode": true}
	if not CROSSINDIE_APP_ID.is_empty():
		cfg["crossindie_app_id"] = CROSSINDIE_APP_ID
	CrossIndieAds.initialize(cfg)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.pressed.connect(action)
	parent.add_child(b)


func _say(line: String) -> void:
	print("[demo] ", line)
	_log.text = line + "\n" + _log.text
