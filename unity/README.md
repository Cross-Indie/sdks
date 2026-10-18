# CrossIndie Unity SDK

Cross-promotion banner for Unity (uGUI). No third-party dependencies.

## Install

Unity Package Manager → **Add package from disk** → select
`clients/unity/com.crossindie.banner/package.json`, or copy the folder into your
project's `Packages/`. (You can also point UPM at a git URL once published.)

## Usage

1. Create a UI `RawImage` where the banner should appear.
2. Add the **CrossIndieBanner** component to it.
3. Configure in the Inspector:
   - `apiBase` — your backend URL
   - `appId` — your app id from the dashboard
   - `category` — `game` / `web_tool` / `saas` / `mobile_app`
   - `autoLoad` — fetch on Start

```csharp
var banner = rawImage.gameObject.AddComponent<CrossIndie.CrossIndieBanner>();
banner.apiBase = "https://api.crossindie.dev";
banner.appId   = "YOUR_APP_ID";
banner.category = "game";
banner.LoadAd();
```

Each banner you place is an independent slot that earns credits on every valid
impression, so more placements means more earnings.

## How it stays honest

- An impression is reported only after the banner is visible for the
  server-mandated minimum time (>=1.5s) **while the application is focused**
  (`Application.isFocused`).
- Clicking opens the promoted game's URL via `Application.OpenURL` and reports a
  click.
- All credit/fraud validation is server-side.

> Note: shipped as an idiomatic starter. Verify in your target Unity version;
> uGUI + `UnityWebRequest` APIs used here are stable from 2021.3 LTS onward.
