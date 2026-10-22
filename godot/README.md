# CrossIndie Godot SDK

A drop-in cross-promotion banner for Godot 4.x. Shows other indie games and
earns credits that promote yours. No third-party dependencies.

## Install

1. Copy `addons/cross_indie/` into your project's `res://addons/`.
2. Enable it: **Project > Project Settings > Plugins > CrossIndie**.
3. Add a **CrossIndieBanner** node to a scene (it appears in the Add Node dialog).

## Configure

In the Inspector or from code:

```gdscript
@onready var banner := $CrossIndieBanner

func _ready() -> void:
    banner.api_base = "https://api.crossindie.com"  # your backend
    banner.app_id   = "YOUR_APP_ID"                 # from the dashboard
    banner.category = "game"                         # game | web_tool | saas | mobile_app
    banner.auto_load = true                          # fetch on ready
```

## Public API

**Properties**
| Property     | Type   | Description                                   |
|--------------|--------|-----------------------------------------------|
| `api_base`   | String | Backend base URL.                             |
| `app_id`     | String | This game's app id.                           |
| `category`   | String | Category pool to request.                     |
| `auto_load`  | bool   | Fetch an ad automatically on `_ready`.        |
| `enable_video` | bool | Request & play a native video banner (.ogv) when the network has one. |

**Methods**
- `load_ad()` — request a fresh ad (call manually when `auto_load` is off).

**Signals**
- `ad_loaded(ad_name: String)`
- `ad_failed(reason: String)`
- `impression_tracked`
- `clicked`

## How it stays honest

- An impression is reported only after the banner has been visible for the
  server-mandated minimum time (>=1.5s) **while the game window is focused**
  (`DisplayServer.window_is_focused()`).
- Clicking opens the promoted game's store page via `OS.shell_open()` and
  reports a click.
- All credit and fraud validation happens server-side; the addon only fetches,
  displays, and reports.

## Native video banners

With `enable_video` on (default), the addon asks the network for a
native-playable **Ogg Theora** (`.ogv`) banner — Godot decodes Theora in-engine,
so no plugin or platform binary is needed. The backend transcodes uploaded
MP4/WebM clips to `.ogv` automatically; when a clip is available it plays muted
and looping in the banner's media area, otherwise the slot shows the static
image. Older backends that don't serve `.ogv` simply fall back to the image.
