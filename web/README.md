# @crossindie/web

Zero-dependency cross-promotion banner for websites, web tools and micro-SaaS.
Lightweight (~2KB gzipped), no build step, no tracking bloat. Supports multiple
slots and standard formats (card, rectangle, leaderboard, mobile, text).

## Install

Via the hosted script (served by your CrossIndie backend at `/embed.js`), or
from a CDN / npm:

```bash
npm install @crossindie/web
```

## Usage

### 1. Auto-init (no code)

```html
<div id="crossindie-banner"></div>
<script
  src="https://api.your-host/embed.js"
  data-app-id="YOUR_APP_ID"
  data-category="web_tool"
  data-api-base="https://api.your-host"
  async
></script>
```

### 2. Programmatic

```html
<div id="banner"></div>
<script src="https://api.your-host/embed.js" async></script>
<script>
  window.addEventListener("load", () => {
    CrossIndie.createBanner({
      el: "#banner",
      appId: "YOUR_APP_ID",
      category: "web_tool",
      apiBase: "https://api.your-host",
    });
  });
</script>
```

## Security

- All credit and anti-fraud rules are enforced **server-side** (signed
  single-use tokens, minimum display time, rate limits, datacenter blocking).
  The client is intentionally thin and untrusted.
- Lock your app to specific domains in the dashboard (**Allowed web domains**).
  The widget then only works when embedded on those hosts, so a stolen `app_id`
  cannot be used to farm impressions from another site.
- An impression is only reported after the banner is continuously visible in
  the viewport for the server-mandated minimum (>=1.5s).
