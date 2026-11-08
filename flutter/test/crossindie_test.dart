import 'dart:convert';

import 'package:crossindie/crossindie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _ad({int minMs = 1500}) => {
      'ad_id': 'a1',
      'name': 'Hyperbase',
      'description': 'The instant backend for side projects',
      'category': 'saas',
      'target_url': 'https://example.com/?ci_ref=r1',
      'banner_image_url': '',
      'video_url': '',
      'video_ogv_url': '',
      'tracking_token': 'tok-1',
      'min_display_ms': minMs,
    };

class _Recorder {
  final fetches = <Uri>[];
  final tracks = <Map<String, dynamic>>[];
  int fetchStatus = 200;
  int trackStatus = 200;
  Map<String, dynamic> payload = _ad();

  late final client = MockClient((req) async {
    if (req.url.path.endsWith('/ad/fetch')) {
      fetches.add(req.url);
      if (fetchStatus != 200) return http.Response('', fetchStatus);
      return http.Response(jsonEncode(payload), 200,
          headers: {'content-type': 'application/json'});
    }
    if (req.url.path.endsWith('/ad/track')) {
      tracks.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{"status":"ok","event_type":"x"}', trackStatus);
    }
    return http.Response('', 404);
  });

  List<String> get events =>
      tracks.map((t) => t['event_type'] as String).toList();
}

Widget _host(Widget child, {double top = 0}) => MaterialApp(
      home: Scaffold(
        body: Stack(children: [Positioned(top: top, left: 0, right: 0, child: child)]),
      ),
    );

void main() {
  group('CrossIndieClient', () {
    test('builds the fetch URL with platform, package and targeting', () {
      final c = CrossIndieClient(apiBase: 'https://api.example.com/');
      final uri = c.fetchUri(
        appId: 'app-1',
        category: 'mobile_app',
        lang: 'de',
        country: 'DE',
        packageName: 'com.example.app',
        platform: 'flutter-android',
      );
      expect(uri.origin, 'https://api.example.com');
      expect(uri.path, '/api/v1/ad/fetch');
      expect(uri.queryParameters, {
        'app_id': 'app-1',
        'category': 'mobile_app',
        'platform': 'flutter-android',
        'lang': 'de',
        'country': 'DE',
        'package': 'com.example.app',
      });
    });

    test('defaults to api.crossindie.com and a flutter-* platform', () {
      final uri = CrossIndieClient().fetchUri(appId: 'x', category: 'game');
      expect(uri.host, 'api.crossindie.com');
      expect(uri.queryParameters['platform'], startsWith('flutter-'));
      expect(uri.queryParameters.containsKey('package'), isFalse);
    });

    test('204 means no ad; other errors throw', () async {
      final r = _Recorder()..fetchStatus = 204;
      final c = CrossIndieClient(httpClient: r.client);
      expect(await c.fetchAd(appId: 'x', category: 'game'), isNull);
      r.fetchStatus = 403;
      expect(c.fetchAd(appId: 'x', category: 'game'),
          throwsA(isA<CrossIndieException>()));
    });

    test('track retries once on 425 and never throws', () async {
      var calls = 0;
      final c = CrossIndieClient(
        httpClient: MockClient((req) async {
          calls++;
          return http.Response('', calls == 1 ? 425 : 200);
        }),
      );
      expect(await c.track('t', 'impression', retryDelay: Duration.zero), isTrue);
      expect(calls, 2);

      final broken = CrossIndieClient(
          httpClient: MockClient((_) async => throw Exception('offline')));
      expect(await broken.track('t', 'click'), isFalse);
    });

    test('resolves relative media against the API base', () {
      final c = CrossIndieClient(apiBase: 'https://api.example.com');
      expect(c.resolveMedia('/media/a.png'), 'https://api.example.com/media/a.png');
      expect(c.resolveMedia('https://cdn/x.png'), 'https://cdn/x.png');
    });
  });

  test('visible fraction', () {
    const screen = Rect.fromLTWH(0, 0, 400, 800);
    expect(crossIndieVisibleFraction(const Rect.fromLTWH(0, 0, 100, 100), screen), 1);
    expect(crossIndieVisibleFraction(const Rect.fromLTWH(0, 750, 100, 100), screen), 0.5);
    expect(crossIndieVisibleFraction(const Rect.fromLTWH(0, 900, 100, 100), screen), 0);
    expect(crossIndieVisibleFraction(Rect.zero, screen), 0);
  });

  group('CrossIndieBanner', () {
    testWidgets('renders the ad and reports one impression after min display time',
        (tester) async {
      final r = _Recorder();
      var impressions = 0;
      await tester.pumpWidget(_host(CrossIndieBanner(
        appId: 'app-1',
        packageName: 'com.example.app',
        client: CrossIndieClient(httpClient: r.client),
        urlOpener: (_) async => true,
        onImpression: (_) => impressions++,
      )));
      await tester.pump();
      expect(find.text('Hyperbase'), findsOneWidget);
      expect(r.fetches.single.queryParameters['package'], 'com.example.app');
      expect(r.fetches.single.queryParameters['category'], 'mobile_app');

      await tester.pump(const Duration(milliseconds: 1000));
      expect(r.events, isEmpty, reason: 'too early');

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(r.events, ['impression']);
      expect(r.tracks.single['tracking_token'], 'tok-1');
      expect(impressions, 1);

      await tester.pump(const Duration(seconds: 5));
      expect(r.events, ['impression'], reason: 'only once');
    });

    testWidgets('no impression while the banner is off screen', (tester) async {
      final r = _Recorder();
      await tester.pumpWidget(_host(
        CrossIndieBanner(
          appId: 'app-1',
          client: CrossIndieClient(httpClient: r.client),
          urlOpener: (_) async => true,
        ),
        top: 5000,
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(r.events, isEmpty);
    });

    testWidgets('no impression while the app is in the background', (tester) async {
      final r = _Recorder();
      await tester.pumpWidget(_host(CrossIndieBanner(
        appId: 'app-1',
        client: CrossIndieClient(httpClient: r.client),
        urlOpener: (_) async => true,
      )));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(r.events, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 3));
      expect(r.events, ['impression']);
    });

    testWidgets('tap opens the target URL and reports one click', (tester) async {
      final r = _Recorder();
      final opened = <Uri>[];
      await tester.pumpWidget(_host(CrossIndieBanner(
        appId: 'app-1',
        client: CrossIndieClient(httpClient: r.client),
        urlOpener: (u) async {
          opened.add(u);
          return true;
        },
      )));
      await tester.pump();
      await tester.tap(find.text('Hyperbase'));
      await tester.pump();
      await tester.tap(find.text('Hyperbase'));
      await tester.pump();
      expect(opened.length, 2);
      expect(opened.first.toString(), 'https://example.com/?ci_ref=r1');
      expect(r.events.where((e) => e == 'click').length, 1);
    });

    testWidgets('close button dismisses without an impression', (tester) async {
      final r = _Recorder();
      await tester.pumpWidget(_host(CrossIndieBanner(
        appId: 'app-1',
        client: CrossIndieClient(httpClient: r.client),
        urlOpener: (_) async => true,
      )));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('crossindie-close')));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Hyperbase'), findsNothing);
      expect(r.events, isEmpty);
    });

    testWidgets('no ad (204) and server errors render nothing and do not throw',
        (tester) async {
      for (final status in [204, 403, 500]) {
        final r = _Recorder()..fetchStatus = status;
        Object? error;
        var noAd = false;
        await tester.pumpWidget(_host(CrossIndieBanner(
          key: ValueKey(status),
          appId: 'app-1',
          client: CrossIndieClient(httpClient: r.client),
          onNoAd: () => noAd = true,
          onError: (e) => error = e,
        )));
        await tester.pump();
        expect(find.text('Hyperbase'), findsNothing);
        expect(tester.takeException(), isNull);
        if (status == 204) {
          expect(noAd, isTrue);
        } else {
          expect(error, isA<CrossIndieException>());
        }
      }
    });

    testWidgets('rotates after refreshInterval once the impression counted',
        (tester) async {
      final r = _Recorder();
      await tester.pumpWidget(_host(CrossIndieBanner(
        appId: 'app-1',
        refreshInterval: const Duration(seconds: 30),
        client: CrossIndieClient(httpClient: r.client),
        urlOpener: (_) async => true,
      )));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(r.fetches.length, 1);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(milliseconds: 300));
      expect(r.fetches.length, 2);
      // Unmount cleanly: no pending timers left behind.
      await tester.pumpWidget(const SizedBox());
    });

    for (final format in CrossIndieFormat.values) {
      testWidgets('format ${format.name} lays out without overflow', (tester) async {
        final r = _Recorder();
        await tester.pumpWidget(_host(CrossIndieBanner(
          appId: 'app-1',
          format: format,
          client: CrossIndieClient(httpClient: r.client),
        )));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Hyperbase'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
