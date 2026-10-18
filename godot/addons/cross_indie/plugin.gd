@tool
extends EditorPlugin

## Registers the CrossIndieBanner custom node so it appears in the
## "Add Node" dialog once the plugin is enabled.

const BANNER_SCRIPT := preload("res://addons/cross_indie/CrossIndieBanner.gd")


func _enter_tree() -> void:
	add_custom_type(
		"CrossIndieBanner",
		"Control",
		BANNER_SCRIPT,
		preload("res://addons/cross_indie/icon.svg")
	)


func _exit_tree() -> void:
	remove_custom_type("CrossIndieBanner")
