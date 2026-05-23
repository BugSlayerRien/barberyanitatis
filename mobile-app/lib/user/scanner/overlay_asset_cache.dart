import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'overlay_asset_resolver.dart';
import 'overlay_registry.dart';

/// Preloads overlay PNG bytes so capture/results screens do not hitch on first use.
class OverlayAssetCache {
  OverlayAssetCache._();

  static final Map<String, Uint8List> _bytes = {};
  static Future<void>? _preloadFuture;
  static bool get isReady => _bytes.isNotEmpty;

  static Future<void> preload({bool force = false}) {
    if (!force && _preloadFuture != null) {
      return _preloadFuture!;
    }
    _preloadFuture = _doPreload();
    return _preloadFuture!;
  }

  static Future<void> _doPreload() async {
    final paths = OverlayRegistry.allAssetPaths();
    debugPrint('[OverlayAssetCache] Preloading ${paths.length} overlay assets...');
    var loaded = 0;
    for (final path in paths) {
      var stored = false;
      for (final candidate in OverlayAssetResolver.bundleCandidates(path)) {
        try {
          final data = await rootBundle.load(candidate);
          _bytes[path] = data.buffer.asUint8List();
          loaded++;
          stored = true;
          break;
        } catch (_) {
          continue;
        }
      }
      if (!stored) {
        debugPrint('[OverlayAssetCache] Missing asset $path');
      }
    }
    debugPrint('[OverlayAssetCache] Loaded $loaded/${paths.length} overlays');
  }

  static Uint8List? getBytes(String assetPath) => _bytes[assetPath];

  static Future<Uint8List> loadBytes(String assetPath) async {
    final cached = _bytes[assetPath];
    if (cached != null) return cached;
    Object? lastError;
    for (final candidate in OverlayAssetResolver.bundleCandidates(assetPath)) {
      try {
        final data = await rootBundle.load(candidate);
        final bytes = data.buffer.asUint8List();
        _bytes[assetPath] = bytes;
        return bytes;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Overlay asset not found: $assetPath ($lastError)');
  }
}
