# CrossIndie Ads demo

Minimal Godot project for `addons/crossindie_ads`. `addons/` holds symlinks to
`../../addons/*` (on Windows, copy the two folders instead).

Set `CROSSINDIE_APP_ID` in `main.gd` (or Project Settings → crossindie_ads) to
see CrossIndie fallback ads on desktop.

## Android (Google test ads)

```bash
godot --headless --path . --install-android-build-template \
      --export-debug "Android" build/crossindie_ads_demo.apk
adb install -r build/crossindie_ads_demo.apk
```

The preset already enables Gradle build, arm64 and INTERNET.

## Headless fallback smoke test

```bash
python3 -I tests/mock_server.py 8765 &           # fake CrossIndie API
godot --headless --path . res://tests/smoke_test.tscn            # fill path
godot --headless --path . res://tests/smoke_test.tscn -- --nofill  # no-fill path
```

Both print `[smoke] PASS` and exit 0 on success.
