# CrossIndie Unreal Engine SDK

A cross-promotion banner plugin for Unreal Engine 5. Ships an ActorComponent
that handles fetching, dwell-time enforcement and impression/click tracking, and
exposes Blueprint events so you render the banner in UMG however you like.

## Install

1. Copy `clients/unreal/CrossIndie` into your project's `Plugins/` folder.
2. Regenerate project files and build (the plugin depends on the `HTTP`,
   `Json` and `JsonUtilities` modules).
3. Enable **CrossIndie** in Edit → Plugins.

## Usage

1. Add a **CrossIndieBannerComponent** to any Actor (or your HUD / widget actor).
2. Set `ApiBase`, `AppId`, `Category`, `bAutoLoad`.
3. In your UMG widget, bind to the component events:
   - `OnAdLoaded(Name, Description, BannerImageUrl, TargetUrl)` — download the
     image (e.g. via an async texture downloader) and populate your widget.
   - `OnAdFailed(Reason)` — hide the slot.
4. On the banner's clicked event, call `HandleClick()` — it opens the store URL
   and reports the click.

The component accrues display time only while the application is focused
(`FApp::HasFocus()`) and reports the impression once the server-mandated minimum
(>=1.5s) has elapsed. Each component instance is an independent earning slot, so
more placements means more credits.

## How it stays honest

All credit and anti-fraud validation happens server-side (signed single-use
tokens, minimum display time, rate limits, datacenter blocking). The plugin is a
thin, untrusted client.

> Note: shipped as an idiomatic UE5 starter. API names (`FHttpModule`,
> `FApp::HasFocus`, `FPlatformProcess::LaunchURL`) are stable across UE5; verify
> against your engine version and wire the image download to your UMG pipeline.
