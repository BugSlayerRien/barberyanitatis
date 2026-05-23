/// Resolves overlay asset paths for the main app and for kiosk (package dependency).
class OverlayAssetResolver {
  OverlayAssetResolver._();

  static const String packageName = 'tatis_barbershop';
  static const String packagePrefix = 'packages/$packageName/';

  /// Paths to try with [rootBundle.load] (kiosk needs the package-prefixed path).
  static List<String> bundleCandidates(String assetPath) {
    if (!assetPath.startsWith('assets/')) {
      return [assetPath];
    }
    if (assetPath.startsWith(packagePrefix)) {
      return [assetPath];
    }
    return [
      assetPath,
      '$packagePrefix$assetPath',
    ];
  }

  /// URLs to try when loading overlays on Flutter web.
  static List<String> webUrls(String assetPath) {
    final urls = <String>[];
    for (final candidate in bundleCandidates(assetPath)) {
      final resolved = Uri.base.resolve('assets/$candidate').toString();
      if (!urls.contains(resolved)) {
        urls.add(resolved);
      }
    }
    return urls;
  }
}
