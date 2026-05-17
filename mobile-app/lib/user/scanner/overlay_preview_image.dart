import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'overlay_asset_cache.dart';

/// Renders overlay PNGs on mobile and web (Flutter web often fails [Image.asset] for nested assets).
class OverlayPreviewImage extends StatelessWidget {
  final String assetPath;
  final BoxFit fit;
  final Widget? errorWidget;

  const OverlayPreviewImage({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.contain,
    this.errorWidget,
  });

  static final Map<String, Future<Uint8List>> _webCache = {};

  static Future<Uint8List> _loadBytes(String path) async {
    final cached = OverlayAssetCache.getBytes(path);
    if (cached != null) return cached;
    return OverlayAssetCache.loadBytes(path);
  }

  static Future<Uint8List> _loadWebBytes(String path) {
    return _webCache.putIfAbsent(path, () async {
      try {
        return await _loadBytes(path);
      } catch (_) {
        final fetchUrl = '/assets/${path.replaceFirst('assets/', '')}';
        final response = await http.get(Uri.parse(fetchUrl));
        if (response.statusCode != 200) {
          throw Exception('Overlay load failed ($fetchUrl): ${response.statusCode}');
        }
        return response.bodyBytes;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!assetPath.startsWith('assets/')) {
      return errorWidget ?? _defaultError();
    }

    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: _loadWebBytes(assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(color: Colors.white);
          }
          if (!snapshot.hasData) {
            debugPrint('[OverlayPreviewImage] $assetPath: ${snapshot.error}');
            return errorWidget ?? _defaultError();
          }
          return Image.memory(
            snapshot.data!,
            fit: fit,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          );
        },
      );
    }

    final cached = OverlayAssetCache.getBytes(assetPath);
    if (cached != null) {
      return Image.memory(
        cached,
        fit: fit,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      );
    }

    return Image.asset(
      assetPath,
      fit: fit,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('[OverlayPreviewImage] $assetPath: $error');
        return errorWidget ?? _defaultError();
      },
    );
  }

  Widget _defaultError() {
    return const Center(
      child: Icon(Icons.image_not_supported_outlined, color: Colors.black38, size: 34),
    );
  }
}
