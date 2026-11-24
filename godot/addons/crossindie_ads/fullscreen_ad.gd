extends CanvasLayer

## Full-screen CrossIndie ad used as the interstitial / rewarded fallback.
##
## Wraps a stock CrossIndieBanner ("image" layout) that does the network work:
## fetch, signed tracking_token, impression after the server's min display
## time while focused, click tracking + opening the store page.
##
## Interstitial: the close button appears after `close_delay_sec`.
## Rewarded:     the reward is granted (if `grant_reward`) once the ad has been
##               visible for `reward_delay_sec` while the window is focused,
##               then the close button appears. With `grant_reward` off it
##               behaves like an interstitial and never emits `earned`.

signal ad_ready
signal ad_failed(reason: String)
signal opened
signal clicked
signal earned(amount: int, reward_type: String)
signal closed

const LAYER := 128

var rewarded: bool = false
var close_delay_sec: float = 3.0
var reward_delay_sec: float = 5.0
var grant_reward: bool = false
var reward_amount: int = 1
var reward_type: String = "reward"

var _banner: Control = null
var _root: Control = null
var _title: Label = null
var _status: Label = null
var _close: Button = null
var _showing: bool = false
var _visible_sec: float = 0.0
var _rewarded_done: bool = false
var _closable: bool = false


func _ready() -> void:
	layer = LAYER
	visible = false
	# Keep working while the game pauses the tree for the ad.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow game input
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	var header := Label.new()
	header.text = "Sponsored"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.modulate = Color(1, 1, 1, 0.6)
	box.add_child(header)

	# Slot the banner goes into (added in begin_load).
	var slot := Control.new()
	slot.name = "Slot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(slot)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)

	var hint := Label.new()
	hint.text = "Tap the image to check it out"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.55)
	box.add_child(hint)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	_close = Button.new()
	_close.text = "  X  "
	_close.add_theme_font_size_override("font_size", 28)
	_close.visible = false
	_close.pressed.connect(_on_close)
	_root.add_child(_close)
	_close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)


## Takes ownership of a not-yet-added CrossIndieBanner and fetches an ad.
func begin_load(banner: Control) -> void:
	_banner = banner
	_banner.visible = false  # no impression time accrues while preloading
	var slot: Control = _root.find_child("Slot", true, false) as Control
	slot.add_child(_banner)
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit_slot()
	_banner.connect("ad_loaded", _on_loaded)
	_banner.connect("ad_failed", func(reason: String) -> void: ad_failed.emit(reason))
	_banner.connect("clicked", func() -> void: clicked.emit())
	_banner.call("load_ad")


## 16:9 media area sized to ~90% of the shorter fitting dimension.
func _fit_slot() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(vp.x * 0.9, vp.y * 0.55 * 16.0 / 9.0)
	var slot_size := Vector2(w, w * 9.0 / 16.0)
	var slot: Control = _banner.get_parent() as Control
	slot.custom_minimum_size = slot_size
	_banner.custom_minimum_size = slot_size


func _on_loaded(ad_name: String) -> void:
	_title.text = ad_name
	ad_ready.emit()


func present() -> void:
	_fit_slot()
	_showing = true
	_visible_sec = 0.0
	visible = true
	_banner.visible = true
	_update_status()
	opened.emit()


func _process(delta: float) -> void:
	if not _showing:
		return
	# Same rule as the banner's impression timer: only focused time counts.
	if not DisplayServer.window_is_focused():
		return
	_visible_sec += delta
	if rewarded and grant_reward:
		if not _rewarded_done and _visible_sec >= reward_delay_sec:
			_rewarded_done = true
			earned.emit(reward_amount, reward_type)
			_set_closable()
	elif not _closable and _visible_sec >= close_delay_sec:
		_set_closable()
	_update_status()


func _set_closable() -> void:
	_closable = true
	_close.visible = true


func _update_status() -> void:
	if rewarded and grant_reward:
		if _rewarded_done:
			_status.text = "Reward granted"
		else:
			_status.text = "Reward in %d" % int(ceil(reward_delay_sec - _visible_sec))
	elif not _closable:
		_status.text = "Close in %d" % int(ceil(close_delay_sec - _visible_sec))
	else:
		_status.text = ""


func _on_close() -> void:
	if not _closable:
		return
	_showing = false
	visible = false
	closed.emit()
