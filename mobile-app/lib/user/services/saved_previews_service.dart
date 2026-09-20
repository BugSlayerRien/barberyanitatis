import '../customer_api.dart';

/// Opt-in gallery of AI try-on previews the customer chose to keep.
///
/// Separate from the generation cache in `face_scan_previews`: that one is
/// scoped to a single scan session and goes stale when captures are retaken,
/// so a look the customer liked becomes unreachable after their next scan.
/// Saving copies the reference into a durable, user-owned list instead.
class SavedPreviewsService {
  static Future<List<Map<String, dynamic>>> list() async {
    final data = await CustomerApi.postDecoded('saved_previews.php', {
      'action': 'listByUser',
    });
    final raw = data['savedPreviews'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<bool> isSaved({
    required int variantId,
    required String scanSessionId,
  }) async {
    final data = await CustomerApi.postDecoded('saved_previews.php', {
      'action': 'status',
      'variantID': variantId,
      'scanSessionId': scanSessionId,
    });
    return data['isSaved'] == true;
  }

  /// Returns the saved row's id, needed to delete it again without a re-list.
  static Future<int?> save({
    required int variantId,
    required String scanSessionId,
    required String frontViewUrl,
    String? sideViewUrl,
    String? backViewUrl,
    String? styleName,
    String? faceShape,
    String? hairTexture,
  }) async {
    final data = await CustomerApi.postDecoded('saved_previews.php', {
      'action': 'save',
      'variantID': variantId,
      'scanSessionId': scanSessionId,
      'frontViewUrl': frontViewUrl,
      if (sideViewUrl != null) 'sideViewUrl': sideViewUrl,
      if (backViewUrl != null) 'backViewUrl': backViewUrl,
      if (styleName != null) 'styleName': styleName,
      if (faceShape != null) 'faceShape': faceShape,
      if (hairTexture != null) 'hairTexture': hairTexture,
    });
    return (data['savedPreviewID'] as num?)?.toInt();
  }

  /// Removes the saved entry only. The underlying image is left alone --
  /// it may still be serving that scan session's cache or an attached booking.
  static Future<void> delete(int savedPreviewId) async {
    await CustomerApi.postDecoded('saved_previews.php', {
      'action': 'delete',
      'savedPreviewID': savedPreviewId,
    });
  }
}
