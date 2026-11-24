# Godot instantiates the plugin reflectively from the manifest meta-data and
# calls @UsedByGodot methods by name over JNI.
-keep class com.crossindie.ads.godot.** { *; }
