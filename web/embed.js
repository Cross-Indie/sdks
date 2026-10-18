/*!
 * CrossIndie Web SDK — zero-dependency cross-promotion banner (~2KB gzipped).
 *
 * Two ways to use it:
 *
 * 1) Auto-init via a script tag (no code):
 *      <div id="crossindie-banner"></div>
 *      <script src="https://your-host/embed.js"
 *              data-app-id="YOUR_APP_ID"
 *              data-category="web_tool"
 *              data-api-base="https://api.your-host"
 *              async></script>
 *
 * 2) Programmatic API:
 *      <script src="https://your-host/embed.js" async
 *              onload="CrossIndie.createBanner({
 *                el: '#banner', appId: 'YOUR_APP_ID',
 *                category: 'web_tool', apiBase: 'https://api.your-host'
 *              })"></script>
 *
 * Impressions are only reported after the banner is continuously visible for
 * the server-mandated minimum display time (>=1.5s). All credit/fraud rules are
 * enforced server-side; this script is a thin, honest client.
 */
(function (global) {
  "use strict";

  var VERSION = "1.0.0";

  function resolveEl(el) {
    if (!el) return null;
    if (typeof el === "string") {
      return el[0] === "#"
        ? document.getElementById(el.slice(1))
        : document.getElementById(el) || document.querySelector(el);
    }
    return el; // assume HTMLElement
  }

  function post(apiBase, body) {
    return fetch(apiBase + "/api/v1/ad/track", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      keepalive: true,
    });
  }

  // Standard banner formats (IAB-inspired). The host picks one per slot; the
  // same ad content is laid out to fit.
  var FORMATS = {
    card: { w: 320, horizontal: false, imgRatio: "16/9", desc: true, badge: true },
    rectangle: { w: 300, h: 250, horizontal: false, imgH: 150, desc: true, badge: true },
    leaderboard: { w: 728, h: 90, horizontal: true, imgW: 150, desc: true, badge: true },
    mobile: { w: 320, h: 50, horizontal: true, imgW: 50, desc: false, badge: false },
    text: { w: 320, horizontal: false, img: false, desc: true, badge: true },
  };

  function el(tag, css, text) {
    var n = document.createElement(tag);
    if (css) n.style.cssText = css;
    if (text != null) n.textContent = text;
    return n;
  }

  function render(container, apiBase, ad, format) {
    var f = FORMATS[format] || FORMATS.card;
    var minMs = ad.min_display_ms || 1500;
    var tracked = false;
    var clicked = false;

    var wrap = el(
      "a",
      "display:flex;" +
        (f.horizontal ? "flex-direction:row;align-items:stretch;" : "flex-direction:column;") +
        "box-sizing:border-box;width:100%;max-width:" + f.w + "px;" +
        (f.h ? "height:" + f.h + "px;" : "") +
        "border:1px solid #27272a;border-radius:" + (f.h && f.h <= 50 ? 8 : 12) + "px;" +
        "overflow:hidden;background:#141210;color:#f5f3ef;text-decoration:none;" +
        "font-family:system-ui,sans-serif"
    );
    wrap.href = ad.target_url;
    wrap.target = "_blank";
    wrap.rel = "noopener noreferrer sponsored";

    var showImg = f.img !== false && ad.banner_image_url;
    if (showImg) {
      var img = el("img");
      img.src = ad.banner_image_url;
      img.alt = ad.name;
      img.loading = "lazy";
      if (f.horizontal) {
        img.style.cssText =
          "flex:0 0 " + f.imgW + "px;width:" + f.imgW + "px;height:100%;object-fit:cover;display:block";
      } else {
        img.style.cssText =
          "display:block;width:100%;" +
          (f.imgH ? "height:" + f.imgH + "px;" : "aspect-ratio:" + f.imgRatio + ";") +
          "object-fit:cover";
      }
      wrap.appendChild(img);
    }

    var pad = f.h && f.h <= 50 ? "6px 10px" : "10px 12px";
    var body = el(
      "div",
      "min-width:0;flex:1;display:flex;flex-direction:column;justify-content:center;padding:" + pad
    );
    var titleSize = f.h && f.h <= 50 ? 13 : 14;
    body.appendChild(
      el(
        "div",
        "font-weight:600;font-size:" + titleSize + "px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis",
        ad.name
      )
    );
    if (f.desc && ad.description) {
      body.appendChild(
        el(
          "div",
          "font-size:12px;color:#a8a29a;margin-top:2px;overflow:hidden;" +
            (f.horizontal ? "white-space:nowrap;text-overflow:ellipsis" : "max-height:34px"),
          ad.description
        )
      );
    }
    if (f.badge) {
      body.appendChild(
        el(
          "div",
          "font-size:10px;letter-spacing:.14em;text-transform:uppercase;color:#78716c;margin-top:" +
            (f.horizontal ? "2px" : "8px"),
          "Promoted with CrossIndie"
        )
      );
    }
    wrap.appendChild(body);

    container.innerHTML = "";
    container.appendChild(wrap);

    wrap.addEventListener("click", function () {
      if (clicked) return;
      clicked = true;
      post(apiBase, { tracking_token: ad.tracking_token, event_type: "click" });
    });

    var dwellTimer = null;
    function reportImpression() {
      if (tracked) return;
      tracked = true;
      post(apiBase, {
        tracking_token: ad.tracking_token,
        event_type: "impression",
      });
      if (observer) observer.disconnect();
    }

    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting && entry.intersectionRatio >= 0.5) {
            if (!dwellTimer && !tracked) {
              dwellTimer = setTimeout(reportImpression, minMs);
            }
          } else if (dwellTimer) {
            clearTimeout(dwellTimer);
            dwellTimer = null;
          }
        });
      },
      { threshold: [0, 0.5, 1] }
    );
    observer.observe(wrap);
  }

  /**
   * Fetch one eligible ad and render it into `el`. Each call is an independent
   * ad slot: place as many as you like, and every valid impression earns
   * credits, so more slots means more earnings.
   * @param {{el:(string|HTMLElement), appId:string, category?:string,
   *          format?:string, apiBase:string, onError?:(err:Error)=>void}} opts
   * @returns {Promise<boolean>} true if an ad was rendered, false if none.
   */
  function createBanner(opts) {
    opts = opts || {};
    var apiBase = (opts.apiBase || "").replace(/\/$/, "");
    var container = resolveEl(opts.el || "crossindie-banner");
    var category = opts.category || "game";
    var format = opts.format || "card";

    function fail(err) {
      if (typeof opts.onError === "function") opts.onError(err);
      else console.warn("[CrossIndie]", err.message);
      return false;
    }

    if (!opts.appId || !apiBase) {
      return Promise.resolve(fail(new Error("appId and apiBase are required")));
    }
    if (!container) {
      return Promise.resolve(fail(new Error("target element not found")));
    }

    var url =
      apiBase +
      "/api/v1/ad/fetch?app_id=" +
      encodeURIComponent(opts.appId) +
      "&category=" +
      encodeURIComponent(category);

    return fetch(url, { headers: { Accept: "application/json" } })
      .then(function (res) {
        if (res.status === 204) return null;
        if (!res.ok) throw new Error("fetch failed: " + res.status);
        return res.json();
      })
      .then(function (ad) {
        if (!ad) return false;
        render(container, apiBase, ad, format);
        return true;
      })
      .catch(fail);
  }

  /** Initialise every slot element on the page: any element carrying a
   *  data-ci-app-id attribute becomes an independent, earning ad slot. Lets a
   *  host drop several placements (each with its own format) from one include;
   *  more slots means more impressions and more credits. */
  function initSlots(defaultApiBase) {
    var nodes = document.querySelectorAll("[data-ci-app-id]");
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      if (n.getAttribute("data-ci-ready")) continue;
      n.setAttribute("data-ci-ready", "1");
      createBanner({
        el: n,
        appId: n.getAttribute("data-ci-app-id"),
        category: n.getAttribute("data-ci-category") || "game",
        format: n.getAttribute("data-ci-format") || "card",
        apiBase: n.getAttribute("data-ci-api-base") || defaultApiBase,
      });
    }
  }

  var CrossIndie = {
    createBanner: createBanner,
    initSlots: initSlots,
    formats: Object.keys(FORMATS),
    version: VERSION,
  };
  global.CrossIndie = CrossIndie;

  // Auto-init from the script tag (single slot) and/or any [data-ci-app-id]
  // slot elements on the page.
  var script = document.currentScript;
  var apiBase = script ? script.getAttribute("data-api-base") || "" : "";
  var singleAppId = script && script.getAttribute("data-app-id");

  var boot = function () {
    if (singleAppId) {
      createBanner({
        el: script.getAttribute("data-target") || "crossindie-banner",
        appId: singleAppId,
        category: script.getAttribute("data-category") || "game",
        format: script.getAttribute("data-format") || "card",
        apiBase: apiBase,
      });
    }
    initSlots(apiBase);
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})(typeof window !== "undefined" ? window : this);
