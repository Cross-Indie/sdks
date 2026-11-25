#!/usr/bin/env bash
# Assemble the standalone github.com/Cross-Indie/godot-admob repo from this
# monorepo (source of truth stays here). Usage: tools/build_standalone.sh <dir>
# The target becomes a Godot project (the demo) with addons/ at the root, the
# Android bridge source in android/, and .gitattributes so Asset Library /
# "Download ZIP" users only get addons/.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:?target dir}"
mkdir -p "$out"
find "$out" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +

ex=(--exclude .godot --exclude build --exclude .gradle --exclude local.properties
    --exclude .idea --exclude '*.iml' --exclude .DS_Store --exclude .build_version)
mkdir -p "$out/addons"
rsync -a "${ex[@]}" "$here/addons/crossindie_ads/" "$out/addons/crossindie_ads/"
rsync -a "${ex[@]}" "$here/addons/cross_indie/" "$out/addons/cross_indie/"
rsync -a "${ex[@]}" "$here/crossindie_ads_android/" "$out/android/"
rsync -a "${ex[@]}" --exclude addons --exclude README.md --exclude .gitignore \
  "$here/examples/crossindie_ads_demo/" "$out/"
cp "$here/../LICENSE" "$out/LICENSE"

# Paths in the standalone layout.
sed -e 's#\[`../../crossindie_ads_android`\](../../crossindie_ads_android)#[`android/`](android/)#' \
    -e 's#\[`../../examples/crossindie_ads_demo`\](../../examples/crossindie_ads_demo)#this repo is the demo project (`main.tscn`, `tests/`)#' \
    "$here/addons/crossindie_ads/README.md" > "$out/README.md"
sed -i '' -e 's#; Demo for the CrossIndie Ads addon. addons/ are symlinks into ../../addons.#; Demo project for the CrossIndie Ads addon (addons/crossindie_ads).#' "$out/project.godot"
sed -i '' -e 's#`../addons/crossindie_ads/bin/`#`../addons/crossindie_ads/bin/`#' "$out/android/README.md"

cat > "$out/.gitignore" <<'G'
.godot/
build/
android/build/
android/plugin/build/
android/.gradle/
android/local.properties
*.apk
*.aab
.DS_Store
G
cat > "$out/.gitattributes" <<'G'
# Asset Library / Download ZIP: ship addons/ only.
/android         export-ignore
/tests           export-ignore
/main.gd         export-ignore
/main.gd.uid     export-ignore
/main.tscn       export-ignore
/project.godot   export-ignore
/export_presets.cfg export-ignore
/.gitignore      export-ignore
/.gitattributes  export-ignore
G
echo "built $out"
