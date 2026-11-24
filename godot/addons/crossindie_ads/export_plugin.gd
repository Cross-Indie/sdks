@tool
extends EditorExportPlugin

## Android export glue (Godot Android plugin v2, Godot 4.2+).
##
## * ships our tiny bridge AAR (bin/<debug|release>/crossindie-ads-*.aar),
## * pulls Google Mobile Ads from Maven instead of bundling jars: the Gradle
##   build resolves it together with its transitive deps (UMP, androidx...),
## * injects the AdMob APPLICATION_ID meta-data (the SDK crashes at startup
##   without it).
## Requires "Use Gradle Build" in the Android export preset.

const Settings := preload("res://addons/crossindie_ads/settings.gd")
const PLUGIN_NAME := "CrossIndieAds"

## play-services-ads per Godot Gradle template. Each pick satisfies that
## template's compileSdk / minSdk / Kotlin version:
##   4.2      : AGP 7.2, compileSdk 33, minSdk 21 -> 22.6.0
##   4.3-4.4  : AGP 8.2, compileSdk 34, minSdk 21 -> 23.6.0
##   4.5+     : AGP 8.6, compileSdk 35, minSdk 24 -> 25.5.0
## Override with Project Settings > crossindie_ads/android/play_services_ads_version.
const GMA_FOR_4_2 := "22.6.0"
const GMA_FOR_4_3 := "23.6.0"
const GMA_FOR_4_5 := "25.5.0"


func _get_name() -> String:
	return PLUGIN_NAME


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	# Paths are relative to res://addons/.
	if debug:
		return PackedStringArray(["crossindie_ads/bin/debug/crossindie-ads-debug.aar"])
	return PackedStringArray(["crossindie_ads/bin/release/crossindie-ads-release.aar"])


func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	return PackedStringArray(["com.google.android.gms:play-services-ads:" + play_services_ads_version()])


func _get_android_manifest_application_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
	var app_id: String = admob_app_id()
	# OPTIMIZE_* move SDK init / ad loading work off the main thread (fewer ANRs).
	return (
		"\n<meta-data android:name=\"com.google.android.gms.ads.APPLICATION_ID\" android:value=\"%s\"/>" % app_id
		+ "\n<meta-data android:name=\"com.google.android.gms.ads.flag.OPTIMIZE_INITIALIZATION\" android:value=\"true\"/>"
		+ "\n<meta-data android:name=\"com.google.android.gms.ads.flag.OPTIMIZE_AD_LOADING\" android:value=\"true\"/>\n"
	)


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	if not features.has("android"):
		return
	if String(Settings.get_value("admob_android_app_id")).strip_edges().is_empty():
		push_warning("CrossIndie Ads: crossindie_ads/admob/android_app_id is empty, exporting with Google's TEST app id. Set your real AdMob app id before release.")
	var aar: String = "res://addons/" + _get_android_libraries(null, is_debug)[0]
	if not FileAccess.file_exists(aar):
		push_error("CrossIndie Ads: missing %s (rebuild with crossindie_ads_android/gradlew assemble)." % aar)


static func admob_app_id() -> String:
	var app_id: String = String(Settings.get_value("admob_android_app_id")).strip_edges()
	if app_id.is_empty():
		app_id = Settings.TEST_ANDROID_APP_ID
	return app_id.xml_escape()


static func play_services_ads_version() -> String:
	var forced: String = String(Settings.get_value("android_play_services_ads_version")).strip_edges()
	if not forced.is_empty():
		return forced
	var v: Dictionary = Engine.get_version_info()
	var major: int = int(v.get("major", 4))
	var minor: int = int(v.get("minor", 0))
	if major > 4 or (major == 4 and minor >= 5):
		return GMA_FOR_4_5
	if major == 4 and minor >= 3:
		return GMA_FOR_4_3
	return GMA_FOR_4_2
