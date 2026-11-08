import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'ad.dart';
import 'client.dart';

/// Category pool to request. Games are shown only to games; web tools and
/// SaaS share a pool; mobile apps match mobile apps.
enum CrossIndieCategory { game, webTool, saas, mobileApp }

extension on CrossIndieCategory {
  String get wire => switch (this) {
        CrossIndieCategory.game => 'game',
        CrossIndieCategory.webTool => 'web_tool',
        CrossIndieCategory.saas => 'saas',
        CrossIndieCategory.mobileApp => 'mobile_app',
      };
}

/// Standard slot formats, identical to the web widget.
enum CrossIndieFormat {
  /// 320 wide, 16:9 image + title + description.
  card,

  /// 300 x 250 medium rectangle.
  rectangle,

  /// 728 x 90 horizontal.
  leaderboard,

  /// 320 x 50 compact.
  mobile,

  /// No image.
  text,
}

class _Spec {
  const _Spec(this.w,
      {this.h,
      this.horizontal = false,
      this.imgW,
      this.imgH,
      this.img = true,
      this.desc = true,
      this.badge = true});
  final double w;
  final double? h;
  final bool horizontal;
  final double? imgW;
  final double? imgH;
  final bool img;
  final bool desc;
  final bool badge;
}

const _specs = <CrossIndieFormat, _Spec>{
  CrossIndieFormat.card: _Spec(320),
  CrossIndieFormat.rectangle: _Spec(300, h: 250, imgH: 150),
  CrossIndieFormat.leaderboard:
      _Spec(728, h: 90, horizontal: true, imgW: 150),
  CrossIndieFormat.mobile: _Spec(320,
      h: 50, horizontal: true, imgW: 50, desc: false, badge: false),
  CrossIndieFormat.text: _Spec(320, img: false),
};

const _bg = Color(0xFF141210);
const _border = Color(0xFF27272A);
const _fg = Color(0xFFF5F3EF);
const _muted = Color(0xFFA8A29A);
const _mediaBg = Color(0xFF0A0A0C);

/// Fraction (0..1) of [box] that lies inside [clip]. Zero for an empty box.
@visibleForTesting
double crossIndieVisibleFraction(Rect box, Rect clip) {
  if (box.width <= 0 || box.height <= 0) return 0;
  final i = box.intersect(clip);
  if (i.width <= 0 || i.height <= 0) return 0;
  return (i.width * i.height) / (box.width * box.height);
}

typedef CrossIndieUrlOpener = Future<bool> Function(Uri url);

/// A CrossIndie cross-promotion banner.
///
/// ```dart
/// CrossIndieBanner(appId: 'YOUR_APP_ID')
/// ```
///
/// Fetches one ad, renders it, and reports an impression only once the banner
/// has been continuously on screen (non-zero size, at least 50% inside the
/// screen and any scroll viewport, app in the foreground, route on top) for the
/// server's minimum display time. A tap opens the ad in the external browser
/// and reports a click. Every failure is swallowed: the banner then simply
/// renders nothing.
class CrossIndieBanner extends StatefulWidget {
  const CrossIndieBanner({
    super.key,
    required this.appId,
    this.category = CrossIndieCategory.mobileApp,
    this.format = CrossIndieFormat.card,
    this.apiBase = kCrossIndieApiBase,
    this.packageName,
    this.country,
    this.lang,
    this.closeable = true,
    this.refreshInterval,
    this.onAdLoaded,
    this.onNoAd,
    this.onImpression,
    this.onClick,
    this.onError,
    this.client,
    this.urlOpener,
  });

  /// Your app id from the CrossIndie dashboard (public, not a secret).
  final String appId;
  final CrossIndieCategory category;
  final CrossIndieFormat format;

  /// Backend base URL. Defaults to `https://api.crossindie.com`.
  final String apiBase;

  /// Your Android package name / iOS bundle id. Optional: lets the dashboard
  /// confirm the SDK runs inside your store app. (Pure Dart cannot read it
  /// without a plugin, so pass it in, e.g. from package_info_plus.)
  final String? packageName;

  /// Viewer country (e.g. "US") for targeting. Optional.
  final String? country;

  /// Viewer language (2 letters). Defaults to the device locale.
  final String? lang;

  /// Show a small ✕ that dismisses the slot. A dismissed slot earns nothing.
  final bool closeable;

  /// Rotate to a new ad this long after the impression was counted (at least
  /// 30 s). Null (default) = show one ad per mount, like the other SDKs.
  final Duration? refreshInterval;

  final void Function(CrossIndieAd ad)? onAdLoaded;
  final VoidCallback? onNoAd;
  final void Function(CrossIndieAd ad)? onImpression;
  final void Function(CrossIndieAd ad)? onClick;
  final void Function(Object error)? onError;

  /// Inject a client (tests / custom HTTP). Not closed by the widget.
  final CrossIndieClient? client;

  /// Override how the target URL is opened (tests). Defaults to url_launcher
  /// in external-application mode.
  final CrossIndieUrlOpener? urlOpener;

  @override
  State<CrossIndieBanner> createState() => _CrossIndieBannerState();
}

class _CrossIndieBannerState extends State<CrossIndieBanner>
    with WidgetsBindingObserver {
  static const _tick = Duration(milliseconds: 250);
  static const _minRefresh = Duration(seconds: 30);

  late CrossIndieClient _client;
  bool _ownsClient = false;

  CrossIndieAd? _ad;
  bool _dismissed = false;
  int _generation = 0;

  bool _impressionSent = false;
  bool _clickSent = false;
  bool _counting = false;
  int _visibleMs = -1; // -1 = not currently in a visible streak

  bool _refreshDue = false;
  Timer? _poll;
  Timer? _refresh;

  bool _tickerEnabled = true;
  ModalRoute<dynamic>? _route;
  Size? _screen;
  AppLifecycleState? _lifecycle;

  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _setupClient();
    _load();
  }

  void _setupClient() {
    if (widget.client != null) {
      _client = widget.client!;
      _ownsClient = false;
    } else {
      _client = CrossIndieClient(apiBase: widget.apiBase);
      _ownsClient = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.of(context);
    _route = ModalRoute.of(context);
    _screen = MediaQuery.maybeSizeOf(context);
  }

  @override
  void didUpdateWidget(CrossIndieBanner old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client || old.apiBase != widget.apiBase) {
      if (_ownsClient) _client.close();
      _setupClient();
    }
    if (old.appId != widget.appId ||
        old.category != widget.category ||
        old.apiBase != widget.apiBase ||
        old.client != widget.client) {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _refresh?.cancel();
    _generation++;
    if (_ownsClient) _client.close();
    super.dispose();
  }

  void _report(Object e) {
    try {
      if (widget.onError != null) {
        widget.onError!(e);
      } else {
        debugPrint('[CrossIndie] $e');
      }
    } catch (_) {}
  }

  void _safe(void Function() f) {
    try {
      f();
    } catch (e) {
      _report(e);
    }
  }

  Future<void> _load() async {
    if (_dismissed) return;
    if (widget.appId.trim().isEmpty) {
      _report(const CrossIndieException('appId is required'));
      return;
    }
    final gen = ++_generation;
    _refreshDue = false;
    _refresh?.cancel();
    try {
      final lang = widget.lang ??
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      final ad = await _client.fetchAd(
        appId: widget.appId.trim(),
        category: widget.category.wire,
        lang: lang,
        country: widget.country,
        packageName: widget.packageName,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _ad = ad;
        _impressionSent = false;
        _clickSent = false;
        _visibleMs = -1;
        _counting = ad != null;
      });
      if (ad == null) {
        _poll?.cancel();
        _safe(() => widget.onNoAd?.call());
      } else {
        _startPolling();
        _safe(() => widget.onAdLoaded?.call(ad));
      }
    } catch (e) {
      if (mounted && gen == _generation) {
        // Keep showing a previous ad (if any) on a failed rotation.
        _report(e);
      }
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_tick, (_) => _safe(_onTick));
  }

  /// True when the banner is really on screen right now.
  bool _isVisible() {
    if (!mounted || _dismissed || _ad == null) return false;
    final life = _lifecycle;
    if (life != null && life != AppLifecycleState.resumed) return false;
    if (!_tickerEnabled) return false;
    if (_route != null && !_route!.isCurrent) return false;
    final ro = _key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return false;
    final size = ro.size;
    if (size.width <= 0 || size.height <= 0) return false;
    final screen = _screen;
    if (screen == null || screen.isEmpty) return false;
    final box = ro.localToGlobal(Offset.zero) & size;
    var clip = Offset.zero & screen;
    // Also clip by every enclosing scroll viewport.
    var scrollable = Scrollable.maybeOf(_key.currentContext!);
    while (scrollable != null) {
      final sro = scrollable.context.findRenderObject();
      if (sro is RenderBox && sro.attached && sro.hasSize) {
        clip = clip.intersect(sro.localToGlobal(Offset.zero) & sro.size);
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    return crossIndieVisibleFraction(box, clip) >= 0.5;
  }

  void _onTick() {
    final ad = _ad;
    if (ad == null) return;
    final visible = _isVisible();

    if (_refreshDue && visible) {
      _refreshDue = false;
      _load();
      return;
    }
    if (!_counting || _impressionSent) {
      if (!_refreshDue) _poll?.cancel();
      return;
    }
    if (!visible) {
      _visibleMs = -1; // a gap resets the streak, like the web widget
      return;
    }
    if (_visibleMs < 0) {
      _visibleMs = 0; // first visible sample: streak starts now
      return;
    }
    _visibleMs += _tick.inMilliseconds;
    if (_visibleMs >= ad.minDisplayMs) {
      _counting = false;
      _impressionSent = true;
      _sendImpression(ad);
    }
  }

  Future<void> _sendImpression(CrossIndieAd ad) async {
    final ok = await _client.track(ad.trackingToken, 'impression');
    if (!mounted) return;
    if (ok) _safe(() => widget.onImpression?.call(ad));
    final every = widget.refreshInterval;
    if (every != null) {
      _refresh?.cancel();
      _refresh = Timer(every < _minRefresh ? _minRefresh : every, () {
        if (!mounted || _dismissed) return;
        _refreshDue = true;
        _startPolling();
      });
    }
  }

  Future<void> _onTap() async {
    final ad = _ad;
    if (ad == null || ad.targetUrl.isEmpty) return;
    try {
      final uri = Uri.parse(ad.targetUrl);
      if (!_clickSent) {
        _clickSent = true;
        unawaited(_client.track(ad.trackingToken, 'click'));
        _safe(() => widget.onClick?.call(ad));
      }
      final open = widget.urlOpener ??
          (u) => launcher.launchUrl(u,
              mode: launcher.LaunchMode.externalApplication);
      await open(uri);
    } catch (e) {
      _report(e);
    }
  }

  Future<void> _openCrossIndie() async {
    try {
      final open = widget.urlOpener ??
          (u) => launcher.launchUrl(u,
              mode: launcher.LaunchMode.externalApplication);
      await open(Uri.parse('https://crossindie.com'));
    } catch (e) {
      _report(e);
    }
  }

  void _dismiss() {
    setState(() => _dismissed = true);
    _poll?.cancel();
    _refresh?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || _dismissed) return const SizedBox.shrink();
    try {
      return _buildCard(ad);
    } catch (e) {
      _report(e);
      return const SizedBox.shrink();
    }
  }

  Widget _buildCard(CrossIndieAd ad) {
    final f = _specs[widget.format]!;
    final compact = f.h != null && f.h! <= 50;

    Widget? media;
    if (f.img && ad.bannerImageUrl.isNotEmpty) {
      final img = Image.network(
        _client.resolveMedia(ad.bannerImageUrl),
        fit: BoxFit.cover,
        semanticLabel: ad.name,
        errorBuilder: (_, __, ___) => const ColoredBox(color: _mediaBg),
      );
      if (f.horizontal) {
        media = SizedBox(width: f.imgW, child: img);
      } else if (f.imgH != null) {
        media = SizedBox(height: f.imgH, width: double.infinity, child: img);
      } else {
        media = AspectRatio(aspectRatio: 16 / 9, child: img);
      }
    }

    final text = Padding(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
          : const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ad.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: _fg,
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w600),
          ),
          if (f.desc && ad.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                ad.description,
                maxLines: f.horizontal ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          // Leave room so the badge never covers the description.
          if (f.badge && !f.horizontal) const SizedBox(height: 14),
        ],
      ),
    );

    final Widget content = f.horizontal
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (media != null) media,
              Expanded(child: Align(alignment: Alignment.centerLeft, child: text)),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (media != null) media,
              if (f.h != null) Expanded(child: text) else text,
            ],
          );

    final card = Container(
      key: _key,
      height: f.h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bg,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
      ),
      child: Stack(
        children: [
          Semantics(
            link: true,
            label: ad.name,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTap,
              child: content,
            ),
          ),
          if (f.badge)
            Positioned(
              right: 6,
              bottom: 6,
              child: GestureDetector(
                onTap: _openCrossIndie,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xB80A0A0C),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PROMOTED WITH CROSSINDIE',
                    style: TextStyle(
                        color: Color(0xFFD6D3CD),
                        fontSize: 9,
                        letterSpacing: 0.9,
                        height: 1.2),
                  ),
                ),
              ),
            ),
          if (widget.closeable)
            Positioned(
              top: 5,
              right: 5,
              child: Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                  key: const ValueKey('crossindie-close'),
                  onTap: _dismiss,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0x8C0A0A0C),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('×',
                        style: TextStyle(color: _fg, fontSize: 14, height: 1)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Align(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: f.w),
          child: card,
        ),
      ),
    );
  }
}
