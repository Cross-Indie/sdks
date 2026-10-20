# CrossIndie SDKs

Official, open-source client SDKs for [CrossIndie](https://crossindie.com) — the
zero-bloat cross-promotion network for indie games, apps, web tools and
micro-SaaS. Drop in one banner, earn credits by hosting other indies, spend
them to get discovered.

These clients are intentionally thin and **contain no secrets** — they only call
public endpoints with your public `app_id`. All credit and anti-fraud logic is
enforced server-side. MIT licensed, so you can read exactly what runs in your
product and embed it freely.

## SDKs

| Platform | Path | Distribution |
|----------|------|--------------|
| **Web** | [`web/`](web) | npm `@crossindie/web`, or `<script src=".../embed.js">` |
| **Godot 4.x** | [`godot/`](godot) | copy the addon into `res://addons/` |
| **Unity** | [`unity/`](unity) | UPM: add from git URL (see below) |
| **Unreal Engine 5** | [`unreal/`](unreal) | copy the plugin into `Plugins/` |

Each folder has its own README with setup steps.

## Quick install

**Web**
```html
<script src="https://api.your-host/embed.js" data-api-base="https://api.your-host" async></script>
<div data-ci-app-id="YOUR_APP_ID" data-ci-category="game" data-ci-format="leaderboard"></div>
```

**Unity (UPM)** — Package Manager → Add package from git URL:
```
https://github.com/Cross-Indie/sdks.git?path=unity/com.crossindie.banner
```

**Godot** — copy `godot/addons/cross_indie` into `res://addons/` and enable the plugin.

**Unreal** — copy `unreal/CrossIndie` into your project's `Plugins/` and rebuild.

## How the network works

- Each banner you place is an independent **slot**. More slots means more
  earnings.
- Hosting an impression earns **+0.85 credits** (held briefly, then vests).
- Getting your own banner shown costs **−1.00 credit**.
- Games are shown to games; web tools and SaaS share a pool.

> The Unity and Unreal SDKs ship as idiomatic starters — verify against your
> engine version. Web and Godot are production-tested.

## License

MIT — see [LICENSE](LICENSE).
