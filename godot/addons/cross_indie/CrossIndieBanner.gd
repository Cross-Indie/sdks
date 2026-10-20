@tool
class_name CrossIndieBanner
extends Control

## CrossIndie cross-promotion banner for Godot 4.x.
##
## Fetches an eligible ad from the CrossIndie network, downloads its banner
## image, displays it, and reports a validated impression after the banner has
## been visible (window focused) for the server-mandated minimum display time.
## Clicking the banner opens the promoted game's store page and reports a click.

signal ad_loaded(ad_name: String)
signal ad_failed(reason: String)
signal impression_tracked
signal clicked

## Base URL of your CrossIndie backend, e.g. "https://api.crossindie.com".
@export var api_base: String = "http://localhost:8000"
## The app_id of THIS game (from your CrossIndie dashboard).
@export var app_id: String = ""
## Category pool to request. Games only ever match games.
@export_enum("game", "web_tool", "saas", "mobile_app") var category: String = "game"
## Fetch an ad automatically when the node enters the tree.
@export var auto_load: bool = true
## Banner layout. "image" = texture only; "card" = texture + title/description
## stacked below; "banner" = horizontal texture + text (leaderboard style).
@export_enum("image", "card", "banner") var banner_format: String = "card"

var _texture_rect: TextureRect
var _title_label: Label
var _desc_label: Label
var _fetch_request: HTTPRequest
var _image_request: HTTPRequest

var _tracking_token: String = ""
var _target_url: String = ""
var _min_display_ms: int = 1500
var _impression_sent: bool = false
var _click_sent: bool = false

var _display_timer: SceneTreeTimer = null
var _elapsed_visible_ms: float = 0.0
var _counting: bool = false


func _ready() -> void:
	_build_layout()

	if Engine.is_editor_hint():
		return  # don't hit the network inside the editor

	_fetch_request = HTTPRequest.new()
	add_child(_fetch_request)
	_fetch_request.request_completed.connect(_on_fetch_completed)

	_image_request = HTTPRequest.new()
	add_child(_image_request)
	_image_request.request_completed.connect(_on_image_completed)

	gui_input.connect(_on_gui_input)

	if auto_load:
		load_ad()


## Build the child nodes for the selected banner_format. All children ignore
## mouse input so clicks land on this Control's gui_input handler.
func _build_layout() -> void:
	_texture_rect = TextureRect.new()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if banner_format == "image":
		custom_minimum_size = Vector2(320, 180)
		_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_texture_rect)
		return

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 12)
	_desc_label.modulate = Color(1, 1, 1, 0.7)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_label.clip_text = true

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.add_child(_title_label)
	text_box.add_child(_desc_label)

	var root_box: BoxContainer
	if banner_format == "banner":
		custom_minimum_size = Vector2(468, 90)
		root_box = HBoxContainer.new()
		_texture_rect.custom_minimum_size = Vector2(120, 0)
		_texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:  # "card"
		custom_minimum_size = Vector2(320, 230)
		root_box = VBoxContainer.new()
		_texture_rect.custom_minimum_size = Vector2(0, 160)
		_texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(_texture_rect)
	root_box.add_child(text_box)
	add_child(root_box)


## Request a new ad from the network.
func load_ad() -> void:
	if app_id.is_empty():
		ad_failed.emit("app_id is not set")
		return
	_reset_state()
	var url := "%s/api/v1/ad/fetch?app_id=%s&category=%s" % [
		_base(), app_id.uri_encode(), category.uri_encode()
	]
	var err := _fetch_request.request(url, PackedStringArray(["Accept: application/json"]))
	if err != OK:
		ad_failed.emit("fetch request error %d" % err)


func _reset_state() -> void:
	_tracking_token = ""
	_target_url = ""
	_impression_sent = false
	_click_sent = false
	_counting = false
	_elapsed_visible_ms = 0.0


func _base() -> String:
	return api_base.rstrip("/")


# --------------------------------------------------------------------------- #
# Fetch
# --------------------------------------------------------------------------- #
func _on_fetch_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code == 204:
		ad_failed.emit("no eligible ads available")
		return
	if code != 200:
		ad_failed.emit("fetch failed (HTTP %d)" % code)
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if typeof(json) != TYPE_DICTIONARY:
		ad_failed.emit("invalid ad payload")
		return

	_tracking_token = json.get("tracking_token", "")
	_target_url = json.get("target_url", "")
	_min_display_ms = int(json.get("min_display_ms", 1500))

	if _title_label:
		_title_label.text = json.get("name", "")
	if _desc_label:
		_desc_label.text = json.get("description", "")

	ad_loaded.emit(json.get("name", ""))

	var banner_url: String = json.get("banner_image_url", "")
	if banner_url.is_empty():
		# No image: start the display timer immediately on the placeholder.
		_start_display_counting()
	else:
		var err := _image_request.request(banner_url)
		if err != OK:
			_start_display_counting()


# --------------------------------------------------------------------------- #
# Image download
# --------------------------------------------------------------------------- #
func _on_image_completed(_result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		_start_display_counting()
		return

	var image := Image.new()
	var err := ERR_UNAVAILABLE
	var content_type := _content_type(headers)
	if content_type.contains("png"):
		err = image.load_png_from_buffer(body)
	elif content_type.contains("webp"):
		err = image.load_webp_from_buffer(body)
	elif content_type.contains("jpeg") or content_type.contains("jpg"):
		err = image.load_jpg_from_buffer(body)
	else:
		# Fall back: try png then webp then jpg.
		err = image.load_png_from_buffer(body)
		if err != OK:
			err = image.load_webp_from_buffer(body)
		if err != OK:
			err = image.load_jpg_from_buffer(body)

	if err == OK:
		_texture_rect.texture = ImageTexture.create_from_image(image)

	_start_display_counting()


func _content_type(headers: PackedStringArray) -> String:
	for h in headers:
		if h.to_lower().begins_with("content-type:"):
			return h.to_lower()
	return ""


# --------------------------------------------------------------------------- #
# Minimum display time enforcement
# --------------------------------------------------------------------------- #
func _start_display_counting() -> void:
	_counting = true
	_elapsed_visible_ms = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _counting or _impression_sent:
		return
	# Only accrue display time while the game window is actually focused and the
	# banner is on-screen — mirrors the web widget's visibility requirement.
	if not DisplayServer.window_is_focused() or not is_visible_in_tree():
		return

	_elapsed_visible_ms += delta * 1000.0
	if _elapsed_visible_ms >= float(_min_display_ms):
		_counting = false
		_send_track("impression")


# --------------------------------------------------------------------------- #
# Click handling
# --------------------------------------------------------------------------- #
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _target_url.is_empty():
			return
		OS.shell_open(_target_url)
		clicked.emit()
		if not _click_sent:
			_send_track("click")


# --------------------------------------------------------------------------- #
# Tracking
# --------------------------------------------------------------------------- #
func _send_track(event_type: String) -> void:
	if _tracking_token.is_empty():
		return
	if event_type == "impression":
		_impression_sent = true
	elif event_type == "click":
		_click_sent = true

	var payload := JSON.stringify({
		"tracking_token": _tracking_token,
		"event_type": event_type,
	})
	var headers := PackedStringArray(["Content-Type: application/json"])

	# Use a dedicated, self-freeing request node so an impression and a
	# subsequent click never collide on the same HTTPRequest.
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(
		func(_r, _c, _h, _b): req.queue_free()
	)
	var err := req.request(
		"%s/api/v1/ad/track" % _base(), headers, HTTPClient.METHOD_POST, payload
	)
	if err != OK:
		req.queue_free()
	elif event_type == "impression":
		impression_tracked.emit()
