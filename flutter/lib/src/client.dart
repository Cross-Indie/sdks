import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ad.dart';

/// Default CrossIndie backend.
const String kCrossIndieApiBase = 'https://api.crossindie.com';

/// SDK version (informational only; never sent to the server).
const String kCrossIndieVersion = '1.0.0';

/// The `platform` value sent with every fetch, e.g. `flutter-android`,
/// `flutter-ios`, `flutter-web`. It only lets the network show the app owner
/// that the SDK is connected.
String crossIndiePlatform() {
  if (kIsWeb) return 'flutter-web';
  return 'flutter-${defaultTargetPlatform.name.toLowerCase()}';
}

/// Thin HTTP client for the public ad endpoints. Holds no secrets: only the
/// public app id is sent; all credit / anti-fraud rules run server-side.
class CrossIndieClient {
  CrossIndieClient({
    String apiBase = kCrossIndieApiBase,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  })  : apiBase = apiBase.replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final String apiBase;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsClient;

  /// Builds the fetch URL (exposed for tests).
  Uri fetchUri({
    required String appId,
    required String category,
    String? lang,
    String? country,
    String? packageName,
    String? platform,
  }) {
    final q = <String, String>{
      'app_id': appId,
      'category': category,
      'platform': platform ?? crossIndiePlatform(),
    };
    if (lang != null && lang.isNotEmpty) q['lang'] = lang;
    if (country != null && country.isNotEmpty) q['country'] = country;
    if (packageName != null && packageName.isNotEmpty) {
      q['package'] = packageName;
    }
    return Uri.parse('$apiBase/api/v1/ad/fetch').replace(queryParameters: q);
  }

  /// Fetches one eligible ad. Returns `null` when the network has none (204).
  /// Throws [CrossIndieException] on any other failure.
  Future<CrossIndieAd?> fetchAd({
    required String appId,
    required String category,
    String? lang,
    String? country,
    String? packageName,
  }) async {
    final uri = fetchUri(
      appId: appId,
      category: category,
      lang: lang,
      country: country,
      packageName: packageName,
    );
    final http.Response res;
    try {
      res = await _http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
    } catch (e) {
      throw CrossIndieException('fetch failed: $e');
    }
    if (res.statusCode == 204) return null;
    if (res.statusCode != 200) {
      throw CrossIndieException('fetch failed (HTTP ${res.statusCode})',
          statusCode: res.statusCode);
    }
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map<String, dynamic>) {
        throw const FormatException('not an object');
      }
      final ad = CrossIndieAd.fromJson(json);
      if (ad.trackingToken.isEmpty) {
        throw const FormatException('missing tracking_token');
      }
      return ad;
    } catch (e) {
      throw CrossIndieException('invalid ad payload: $e');
    }
  }

  /// Reports an `impression` or `click` for an ad's single-use token via
  /// `POST /api/v1/ad/track`. Returns true when the server accepted it.
  ///
  /// A 425 ("too early", the server's minimum display time) does not burn the
  /// token, so it is retried once after [retryDelay]. Never throws.
  Future<bool> track(
    String trackingToken,
    String eventType, {
    Duration retryDelay = const Duration(seconds: 1),
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _http
            .post(
              Uri.parse('$apiBase/api/v1/ad/track'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'tracking_token': trackingToken,
                'event_type': eventType,
              }),
            )
            .timeout(timeout);
        if (res.statusCode == 425 && attempt == 0) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        return res.statusCode >= 200 && res.statusCode < 300;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Resolves a media URL that may come back relative (`/media/...`) against
  /// the API origin.
  String resolveMedia(String url) =>
      url.startsWith('/') ? '$apiBase$url' : url;

  void close() {
    if (_ownsClient) _http.close();
  }
}

class CrossIndieException implements Exception {
  const CrossIndieException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'CrossIndieException: $message';
}
