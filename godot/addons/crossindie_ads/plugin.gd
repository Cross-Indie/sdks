@tool
extends EditorPlugin

## CrossIndie Ads editor plugin:
## - registers Project Settings under crossindie_ads/*,
## - adds the `CrossIndieAds` autoload,
## - installs the Android export plugin (AAR + Maven deps + manifest).

const AUTOLOAD_NAME := "CrossIndieAds"
const AUTOLOAD_PATH := "res://addons/crossindie_ads/crossindie_ads.gd"
const Settings := preload("res://addons/crossindie_ads/settings.gd")
const ExportPluginScript := preload("res://addons/crossindie_ads/export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	Settings.register_all()
	_export_plugin = ExportPluginScript.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


func _enable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	Settings.register_all()
	ProjectSettings.save()


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
