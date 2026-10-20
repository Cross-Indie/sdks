// CrossIndie Banner for Unity (uGUI).
//
// Attach this component to a UI GameObject that has a RawImage. It fetches an
// eligible ad, downloads the banner texture, enforces the server-mandated
// minimum display time (only while the application is focused), and reports a
// click (opening the store URL) when the banner is clicked.
//
// All credit and anti-fraud rules are enforced server-side; this is a thin,
// honest client.
using System;
using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.Networking;
using UnityEngine.UI;

namespace CrossIndie
{
    [RequireComponent(typeof(RawImage))]
    public class CrossIndieBanner : MonoBehaviour, IPointerClickHandler
    {
        [Header("Config")]
        [Tooltip("Base URL of your CrossIndie backend, e.g. https://api.crossindie.com")]
        public string apiBase = "http://localhost:8000";

        [Tooltip("This game's app id from the CrossIndie dashboard.")]
        public string appId = "";

        [Tooltip("Category pool to request.")]
        public string category = "game";

        [Tooltip("Fetch an ad automatically on Start().")]
        public bool autoLoad = true;

        [Header("Events")]
        public StringEvent onAdLoaded;   // ad name
        public StringEvent onAdFailed;   // reason

        [Serializable] public class StringEvent : UnityEngine.Events.UnityEvent<string> {}

        [Serializable]
        private class AdPayload
        {
            public string ad_id;
            public string name;
            public string description;
            public string category;
            public string target_url;
            public string banner_image_url;
            public string tracking_token;
            public int min_display_ms = 1500;
        }

        [Serializable]
        private class TrackBody
        {
            public string tracking_token;
            public string event_type;
        }

        private RawImage _image;
        private AdPayload _ad;
        private bool _impressionSent;
        private bool _clickSent;
        private float _visibleMs;
        private bool _counting;

        private string Base => apiBase.TrimEnd('/');

        private void Awake() => _image = GetComponent<RawImage>();

        private void Start()
        {
            if (autoLoad) LoadAd();
        }

        /// <summary>Request a fresh ad from the network.</summary>
        public void LoadAd()
        {
            if (string.IsNullOrEmpty(appId))
            {
                onAdFailed?.Invoke("appId is not set");
                return;
            }
            _impressionSent = false;
            _clickSent = false;
            _counting = false;
            _visibleMs = 0f;
            StartCoroutine(FetchRoutine());
        }

        private IEnumerator FetchRoutine()
        {
            string url = $"{Base}/api/v1/ad/fetch?app_id={UnityWebRequest.EscapeURL(appId)}" +
                         $"&category={UnityWebRequest.EscapeURL(category)}";
            using (var req = UnityWebRequest.Get(url))
            {
                req.SetRequestHeader("Accept", "application/json");
                yield return req.SendWebRequest();

                if (req.responseCode == 204)
                {
                    onAdFailed?.Invoke("no eligible ads available");
                    yield break;
                }
                if (req.result != UnityWebRequest.Result.Success)
                {
                    onAdFailed?.Invoke($"fetch failed ({req.responseCode})");
                    yield break;
                }

                _ad = JsonUtility.FromJson<AdPayload>(req.downloadHandler.text);
            }

            onAdLoaded?.Invoke(_ad != null ? _ad.name : "");

            if (_ad != null && !string.IsNullOrEmpty(_ad.banner_image_url))
                yield return StartCoroutine(DownloadImageRoutine(_ad.banner_image_url));

            _counting = true; // begin accruing display time
        }

        private IEnumerator DownloadImageRoutine(string imageUrl)
        {
            using (var req = UnityWebRequestTexture.GetTexture(imageUrl))
            {
                yield return req.SendWebRequest();
                if (req.result == UnityWebRequest.Result.Success)
                    _image.texture = DownloadHandlerTexture.GetContent(req);
            }
        }

        private void Update()
        {
            if (!_counting || _impressionSent || _ad == null) return;
            // Only count time while the app is focused and the banner is visible.
            if (!Application.isFocused || !isActiveAndEnabled) return;

            _visibleMs += Time.unscaledDeltaTime * 1000f;
            if (_visibleMs >= _ad.min_display_ms)
            {
                _counting = false;
                Track("impression");
            }
        }

        public void OnPointerClick(PointerEventData eventData)
        {
            if (_ad == null || string.IsNullOrEmpty(_ad.target_url)) return;
            Application.OpenURL(_ad.target_url);
            if (!_clickSent) Track("click");
        }

        private void Track(string eventType)
        {
            if (_ad == null || string.IsNullOrEmpty(_ad.tracking_token)) return;
            if (eventType == "impression") _impressionSent = true;
            if (eventType == "click") _clickSent = true;
            StartCoroutine(TrackRoutine(eventType));
        }

        private IEnumerator TrackRoutine(string eventType)
        {
            var body = JsonUtility.ToJson(new TrackBody
            {
                tracking_token = _ad.tracking_token,
                event_type = eventType,
            });
            using (var req = new UnityWebRequest($"{Base}/api/v1/ad/track", "POST"))
            {
                req.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(body));
                req.downloadHandler = new DownloadHandlerBuffer();
                req.SetRequestHeader("Content-Type", "application/json");
                yield return req.SendWebRequest();
            }
        }
    }
}
