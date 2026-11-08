/// CrossIndie: free cross-promotion banners for indie apps and games.
///
/// ```dart
/// import 'package:crossindie/crossindie.dart';
///
/// CrossIndieBanner(appId: 'YOUR_APP_ID')
/// ```
library;

export 'src/ad.dart' show CrossIndieAd;
export 'src/banner.dart'
    show
        CrossIndieBanner,
        CrossIndieCategory,
        CrossIndieFormat,
        CrossIndieUrlOpener,
        crossIndieVisibleFraction;
export 'src/client.dart'
    show
        CrossIndieClient,
        CrossIndieException,
        crossIndiePlatform,
        kCrossIndieApiBase,
        kCrossIndieVersion;
