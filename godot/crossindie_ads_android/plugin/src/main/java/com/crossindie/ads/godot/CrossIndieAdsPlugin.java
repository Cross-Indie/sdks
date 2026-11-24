package com.crossindie.ads.godot;

import android.app.Activity;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdListener;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.AdSize;
import com.google.android.gms.ads.AdView;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.RequestConfiguration;
import com.google.android.gms.ads.interstitial.InterstitialAd;
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback;
import com.google.android.gms.ads.rewarded.RewardItem;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;
import com.google.android.ump.ConsentDebugSettings;
import com.google.android.ump.ConsentInformation;
import com.google.android.ump.ConsentRequestParameters;
import com.google.android.ump.UserMessagingPlatform;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * CrossIndie Ads - Godot Android plugin (v2 architecture, Godot 4.2+).
 *
 * Thin bridge over the Google Mobile Ads SDK. The GDScript facade
 * (addons/crossindie_ads/crossindie_ads.gd) owns all policy: provider chain,
 * fallback to the CrossIndie network, retries. This class only:
 *   - runs every SDK call on the Android UI thread,
 *   - reports results back as Godot signals, emitted on Godot's thread.
 *
 * Only APIs that exist unchanged from play-services-ads 22.6 through 25.x are
 * used, so one AAR works with whichever SDK version the export pulls in.
 */
public class CrossIndieAdsPlugin extends GodotPlugin {

    private static final String TAG = "CrossIndieAds";
    static final String PLUGIN_NAME = "CrossIndieAdsAndroid";

    // ---- signals (names mirrored in providers/admob_android_provider.gd) ----
    private static final SignalInfo SIG_INITIALIZED = new SignalInfo("initialized");
    private static final SignalInfo SIG_CONSENT_FINISHED =
            new SignalInfo("consent_finished", Boolean.class, String.class);

    private static final SignalInfo SIG_BANNER_LOADED = new SignalInfo("banner_loaded");
    private static final SignalInfo SIG_BANNER_FAILED =
            new SignalInfo("banner_failed_to_load", Integer.class, String.class);
    private static final SignalInfo SIG_BANNER_CLICKED = new SignalInfo("banner_clicked");

    private static final SignalInfo SIG_INTER_LOADED = new SignalInfo("interstitial_loaded");
    private static final SignalInfo SIG_INTER_FAILED =
            new SignalInfo("interstitial_failed_to_load", Integer.class, String.class);
    private static final SignalInfo SIG_INTER_OPENED = new SignalInfo("interstitial_opened");
    private static final SignalInfo SIG_INTER_CLOSED = new SignalInfo("interstitial_closed");
    private static final SignalInfo SIG_INTER_SHOW_FAILED =
            new SignalInfo("interstitial_failed_to_show", Integer.class, String.class);
    private static final SignalInfo SIG_INTER_CLICKED = new SignalInfo("interstitial_clicked");

    private static final SignalInfo SIG_REW_LOADED = new SignalInfo("rewarded_loaded");
    private static final SignalInfo SIG_REW_FAILED =
            new SignalInfo("rewarded_failed_to_load", Integer.class, String.class);
    private static final SignalInfo SIG_REW_OPENED = new SignalInfo("rewarded_opened");
    private static final SignalInfo SIG_REW_CLOSED = new SignalInfo("rewarded_closed");
    private static final SignalInfo SIG_REW_SHOW_FAILED =
            new SignalInfo("rewarded_failed_to_show", Integer.class, String.class);
    private static final SignalInfo SIG_REW_EARNED =
            new SignalInfo("rewarded_earned", Integer.class, String.class);
    private static final SignalInfo SIG_REW_CLICKED = new SignalInfo("rewarded_clicked");

    // Our own error codes (GMA codes are 0..11).
    private static final int ERR_NO_ACTIVITY = -1;
    private static final int ERR_NOT_READY = -2;
    private static final int ERR_EXCEPTION = -3;

    private FrameLayout overlay;
    private AdView adView;
    private AdSize bannerSize;
    private boolean bannerTop = false;
    private boolean bannerWantedVisible = false;

    private volatile InterstitialAd interstitial;
    private volatile RewardedAd rewarded;
    private volatile boolean sdkInitialized = false;
    private final AtomicBoolean initStarted = new AtomicBoolean(false);

    public CrossIndieAdsPlugin(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return PLUGIN_NAME;
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(
                SIG_INITIALIZED, SIG_CONSENT_FINISHED,
                SIG_BANNER_LOADED, SIG_BANNER_FAILED, SIG_BANNER_CLICKED,
                SIG_INTER_LOADED, SIG_INTER_FAILED, SIG_INTER_OPENED, SIG_INTER_CLOSED,
                SIG_INTER_SHOW_FAILED, SIG_INTER_CLICKED,
                SIG_REW_LOADED, SIG_REW_FAILED, SIG_REW_OPENED, SIG_REW_CLOSED,
                SIG_REW_SHOW_FAILED, SIG_REW_EARNED, SIG_REW_CLICKED));
    }

    // ------------------------------------------------------------------ //
    // Lifecycle
    // ------------------------------------------------------------------ //

    /** The returned view is stacked above Godot's render view; it hosts the banner. */
    @Nullable
    @Override
    public View onMainCreate(Activity activity) {
        overlay = new FrameLayout(activity);
        // An empty, non-clickable FrameLayout never consumes touches, so the
        // game still receives input everywhere outside the AdView.
        overlay.setClickable(false);
        overlay.setFocusable(false);
        return overlay;
    }

    @Override
    public void onMainPause() {
        if (adView != null) adView.pause();
    }

    @Override
    public void onMainResume() {
        if (adView != null) adView.resume();
    }

    @Override
    public void onMainDestroy() {
        if (adView != null) {
            adView.destroy();
            adView = null;
        }
    }

    // ------------------------------------------------------------------ //
    // Initialization & consent
    // ------------------------------------------------------------------ //

    /**
     * @param testMode       when true, `testDeviceIds` are registered and the GDScript
     *                       side swaps in Google's official test ad unit ids.
     * @param testDeviceIds  comma-separated hashed device ids (logcat prints yours).
     * @param requestConsent run Google UMP (GDPR / US state privacy) before init.
     * @param debugEea       test mode only: pretend the device is in the EEA.
     */
    @UsedByGodot
    public void initialize(boolean testMode, String testDeviceIds, boolean requestConsent, boolean debugEea) {
        final Activity activity = getActivity();
        if (activity == null) {
            Log.w(TAG, "initialize: no activity");
            return;
        }
        final List<String> ids = splitCsv(testDeviceIds);
        if (!ids.isEmpty()) {
            RequestConfiguration cfg = MobileAds.getRequestConfiguration().toBuilder()
                    .setTestDeviceIds(ids)
                    .build();
            MobileAds.setRequestConfiguration(cfg);
        }
        if (!requestConsent) {
            startSdk(activity);
            return;
        }
        activity.runOnUiThread(() -> {
            ConsentRequestParameters.Builder params = new ConsentRequestParameters.Builder();
            if (testMode && (debugEea || !ids.isEmpty())) {
                ConsentDebugSettings.Builder dbg = new ConsentDebugSettings.Builder(activity);
                if (debugEea) {
                    dbg.setDebugGeography(ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_EEA);
                }
                for (String id : ids) dbg.addTestDeviceHashedId(id);
                params.setConsentDebugSettings(dbg.build());
            }
            final ConsentInformation info = UserMessagingPlatform.getConsentInformation(activity);
            try {
                info.requestConsentInfoUpdate(activity, params.build(),
                        () -> UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity, formError -> {
                            String err = formError == null ? "" : formError.getMessage();
                            emit(SIG_CONSENT_FINISHED, info.canRequestAds(), err);
                            startSdk(activity);
                        }),
                        requestError -> {
                            // Typical cause: no privacy message configured in AdMob.
                            // Ads can still be requested (non-personalized where required).
                            emit(SIG_CONSENT_FINISHED, info.canRequestAds(), requestError.getMessage());
                            startSdk(activity);
                        });
            } catch (Throwable t) {
                Log.e(TAG, "consent failed", t);
                emit(SIG_CONSENT_FINISHED, true, String.valueOf(t.getMessage()));
                startSdk(activity);
            }
        });
    }

    private void startSdk(final Activity activity) {
        if (!initStarted.compareAndSet(false, true)) {
            if (sdkInitialized) emit(SIG_INITIALIZED);
            return;
        }
        // Google recommends initializing off the main thread (avoids ANRs).
        new Thread(() -> {
            try {
                MobileAds.initialize(activity, status -> {
                    sdkInitialized = true;
                    emit(SIG_INITIALIZED);
                });
            } catch (Throwable t) {
                Log.e(TAG, "MobileAds.initialize failed", t);
                initStarted.set(false);
            }
        }, "CrossIndieAds-init").start();
    }

    @UsedByGodot
    public boolean isInitialized() {
        return sdkInitialized;
    }

    @UsedByGodot
    public boolean canRequestAds() {
        Activity activity = getActivity();
        if (activity == null) return false;
        return UserMessagingPlatform.getConsentInformation(activity).canRequestAds();
    }

    /** True when the user must be offered a way to change consent (show a "Privacy" button). */
    @UsedByGodot
    public boolean isPrivacyOptionsRequired() {
        Activity activity = getActivity();
        if (activity == null) return false;
        return UserMessagingPlatform.getConsentInformation(activity).getPrivacyOptionsRequirementStatus()
                == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED;
    }

    @UsedByGodot
    public void showPrivacyOptionsForm() {
        final Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> UserMessagingPlatform.showPrivacyOptionsForm(activity, formError -> {
            Activity a = getActivity();
            boolean can = a != null && UserMessagingPlatform.getConsentInformation(a).canRequestAds();
            emit(SIG_CONSENT_FINISHED, can, formError == null ? "" : formError.getMessage());
        }));
    }

    // ------------------------------------------------------------------ //
    // Banner (anchored adaptive)
    // ------------------------------------------------------------------ //

    @UsedByGodot
    public void loadBanner(final String adUnitId, final boolean top) {
        final Activity activity = getActivity();
        if (activity == null) {
            emit(SIG_BANNER_FAILED, ERR_NO_ACTIVITY, "no activity");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                destroyBannerInternal();
                bannerTop = top;
                bannerWantedVisible = true;
                bannerSize = adaptiveSize(activity);

                adView = new AdView(activity);
                adView.setAdUnitId(adUnitId);
                adView.setAdSize(bannerSize);
                adView.setAdListener(new AdListener() {
                    @Override
                    public void onAdLoaded() {
                        if (adView != null) {
                            adView.setVisibility(bannerWantedVisible ? View.VISIBLE : View.GONE);
                        }
                        emit(SIG_BANNER_LOADED);
                    }

                    @Override
                    public void onAdFailedToLoad(@NonNull LoadAdError error) {
                        emit(SIG_BANNER_FAILED, error.getCode(), error.getMessage());
                    }

                    @Override
                    public void onAdClicked() {
                        emit(SIG_BANNER_CLICKED);
                    }
                });
                // Hidden until the first fill so a no-fill never shows a blank strip.
                adView.setVisibility(View.GONE);

                FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                        Gravity.CENTER_HORIZONTAL | (top ? Gravity.TOP : Gravity.BOTTOM));
                overlayOrThrow().addView(adView, lp);
                adView.loadAd(new AdRequest.Builder().build());
            } catch (Throwable t) {
                Log.e(TAG, "loadBanner failed", t);
                emit(SIG_BANNER_FAILED, ERR_EXCEPTION, String.valueOf(t.getMessage()));
            }
        });
    }

    @UsedByGodot
    public void showBanner() {
        runOnUiThread(() -> {
            bannerWantedVisible = true;
            if (adView != null) {
                adView.setVisibility(View.VISIBLE);
                adView.resume();
            }
        });
    }

    @UsedByGodot
    public void hideBanner() {
        runOnUiThread(() -> {
            bannerWantedVisible = false;
            if (adView != null) {
                adView.setVisibility(View.GONE);
                adView.pause();
            }
        });
    }

    @UsedByGodot
    public void destroyBanner() {
        runOnUiThread(this::destroyBannerInternal);
    }

    /** Banner height in physical pixels (0 when no banner), for laying out game UI. */
    @UsedByGodot
    public int getBannerHeightPx() {
        Activity activity = getActivity();
        AdSize size = bannerSize;
        if (activity == null || size == null || adView == null) return 0;
        return size.getHeightInPixels(activity);
    }

    private void destroyBannerInternal() {
        if (adView != null) {
            ViewGroup parent = (ViewGroup) adView.getParent();
            if (parent != null) parent.removeView(adView);
            adView.destroy();
            adView = null;
        }
        bannerSize = null;
    }

    private FrameLayout overlayOrThrow() {
        if (overlay == null) throw new IllegalStateException("plugin overlay not created");
        return overlay;
    }

    @SuppressWarnings("deprecation")
    private AdSize adaptiveSize(Activity activity) {
        DisplayMetrics metrics = new DisplayMetrics();
        activity.getWindowManager().getDefaultDisplay().getMetrics(metrics);
        float widthPx = overlay != null && overlay.getWidth() > 0 ? overlay.getWidth() : metrics.widthPixels;
        int widthDp = (int) (widthPx / metrics.density);
        return AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(activity, widthDp);
    }

    // ------------------------------------------------------------------ //
    // Interstitial
    // ------------------------------------------------------------------ //

    @UsedByGodot
    public void loadInterstitial(final String adUnitId) {
        final Activity activity = getActivity();
        if (activity == null) {
            emit(SIG_INTER_FAILED, ERR_NO_ACTIVITY, "no activity");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                InterstitialAd.load(activity, adUnitId, new AdRequest.Builder().build(),
                        new InterstitialAdLoadCallback() {
                            @Override
                            public void onAdLoaded(@NonNull InterstitialAd ad) {
                                interstitial = ad;
                                emit(SIG_INTER_LOADED);
                            }

                            @Override
                            public void onAdFailedToLoad(@NonNull LoadAdError error) {
                                interstitial = null;
                                emit(SIG_INTER_FAILED, error.getCode(), error.getMessage());
                            }
                        });
            } catch (Throwable t) {
                Log.e(TAG, "loadInterstitial failed", t);
                emit(SIG_INTER_FAILED, ERR_EXCEPTION, String.valueOf(t.getMessage()));
            }
        });
    }

    @UsedByGodot
    public boolean isInterstitialReady() {
        return interstitial != null;
    }

    @UsedByGodot
    public void showInterstitial() {
        final Activity activity = getActivity();
        if (activity == null) {
            emit(SIG_INTER_SHOW_FAILED, ERR_NO_ACTIVITY, "no activity");
            return;
        }
        activity.runOnUiThread(() -> {
            final InterstitialAd ad = interstitial;
            if (ad == null) {
                emit(SIG_INTER_SHOW_FAILED, ERR_NOT_READY, "interstitial not loaded");
                return;
            }
            interstitial = null; // one-shot
            ad.setFullScreenContentCallback(new FullScreenContentCallback() {
                @Override
                public void onAdShowedFullScreenContent() {
                    emit(SIG_INTER_OPENED);
                }

                @Override
                public void onAdDismissedFullScreenContent() {
                    emit(SIG_INTER_CLOSED);
                }

                @Override
                public void onAdFailedToShowFullScreenContent(@NonNull AdError error) {
                    emit(SIG_INTER_SHOW_FAILED, error.getCode(), error.getMessage());
                }

                @Override
                public void onAdClicked() {
                    emit(SIG_INTER_CLICKED);
                }
            });
            ad.show(activity);
        });
    }

    // ------------------------------------------------------------------ //
    // Rewarded
    // ------------------------------------------------------------------ //

    @UsedByGodot
    public void loadRewarded(final String adUnitId) {
        final Activity activity = getActivity();
        if (activity == null) {
            emit(SIG_REW_FAILED, ERR_NO_ACTIVITY, "no activity");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                RewardedAd.load(activity, adUnitId, new AdRequest.Builder().build(),
                        new RewardedAdLoadCallback() {
                            @Override
                            public void onAdLoaded(@NonNull RewardedAd ad) {
                                rewarded = ad;
                                emit(SIG_REW_LOADED);
                            }

                            @Override
                            public void onAdFailedToLoad(@NonNull LoadAdError error) {
                                rewarded = null;
                                emit(SIG_REW_FAILED, error.getCode(), error.getMessage());
                            }
                        });
            } catch (Throwable t) {
                Log.e(TAG, "loadRewarded failed", t);
                emit(SIG_REW_FAILED, ERR_EXCEPTION, String.valueOf(t.getMessage()));
            }
        });
    }

    @UsedByGodot
    public boolean isRewardedReady() {
        return rewarded != null;
    }

    @UsedByGodot
    public void showRewarded() {
        final Activity activity = getActivity();
        if (activity == null) {
            emit(SIG_REW_SHOW_FAILED, ERR_NO_ACTIVITY, "no activity");
            return;
        }
        activity.runOnUiThread(() -> {
            final RewardedAd ad = rewarded;
            if (ad == null) {
                emit(SIG_REW_SHOW_FAILED, ERR_NOT_READY, "rewarded not loaded");
                return;
            }
            rewarded = null; // one-shot
            ad.setFullScreenContentCallback(new FullScreenContentCallback() {
                @Override
                public void onAdShowedFullScreenContent() {
                    emit(SIG_REW_OPENED);
                }

                @Override
                public void onAdDismissedFullScreenContent() {
                    emit(SIG_REW_CLOSED);
                }

                @Override
                public void onAdFailedToShowFullScreenContent(@NonNull AdError error) {
                    emit(SIG_REW_SHOW_FAILED, error.getCode(), error.getMessage());
                }

                @Override
                public void onAdClicked() {
                    emit(SIG_REW_CLICKED);
                }
            });
            ad.show(activity, (RewardItem item) -> emit(SIG_REW_EARNED, item.getAmount(), item.getType()));
        });
    }

    // ------------------------------------------------------------------ //
    // Helpers
    // ------------------------------------------------------------------ //

    /**
     * SDK callbacks arrive on the Android UI thread; GDScript must only run on
     * Godot's own thread, so every signal is marshalled there first.
     */
    private void emit(final SignalInfo signal, final Object... args) {
        runOnRenderThread(() -> emitSignal(signal.getName(), args));
    }

    private static List<String> splitCsv(String csv) {
        List<String> out = new ArrayList<>();
        if (csv == null) return out;
        for (String s : csv.split(",")) {
            String t = s.trim();
            if (!t.isEmpty()) out.add(t);
        }
        return out;
    }
}
