/// One ad as returned by `GET /api/v1/ad/fetch`.
class CrossIndieAd {
  const CrossIndieAd({
    required this.adId,
    required this.name,
    required this.description,
    required this.targetUrl,
    required this.bannerImageUrl,
    required this.trackingToken,
    required this.minDisplayMs,
  });

  final String adId;
  final String name;
  final String description;
  final String targetUrl;
  final String bannerImageUrl;
  final String trackingToken;

  /// Server-mandated minimum visible time before an impression may be reported.
  final int minDisplayMs;

  static String _s(Object? v) => v is String ? v : (v == null ? '' : '$v');

  factory CrossIndieAd.fromJson(Map<String, dynamic> json) {
    final min = json['min_display_ms'];
    return CrossIndieAd(
      adId: _s(json['ad_id']),
      name: _s(json['name']),
      description: _s(json['description']),
      targetUrl: _s(json['target_url']),
      bannerImageUrl: _s(json['banner_image_url']),
      trackingToken: _s(json['tracking_token']),
      minDisplayMs: min is num && min > 0 ? min.toInt() : 1500,
    );
  }
}
