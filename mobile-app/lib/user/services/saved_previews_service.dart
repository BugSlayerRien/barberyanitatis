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
  ///
  /// Idempotent: the API 404s ("Saved preview not found") when the row is
  /// already gone, which happens whenever a caller is holding an id from
  /// before another screen deleted it. The customer asked for the look to be
  /// removed and it is removed, so that is a success, not an error to show
  /// them. Every other failure still throws.
  static Future<void> delete(int savedPreviewId) async {
    try {
      await CustomerApi.postDecoded('saved_previews.php', {
        'action': 'delete',
        'savedPreviewID': savedPreviewId,
      });
    } on CustomerApiException catch (error) {
      if (error.statusCode != 404) rethrow;
    }
  }

  /// The saved row's id for a look, or null if it is not saved.
  ///
  /// Lets a caller holding a possibly-stale id re-resolve it before deleting,
  /// rather than firing a delete that can only 404.
  static Future<int?> savedIdFor({
    required int variantId,
    required String scanSessionId,
  }) async {
    final data = await CustomerApi.postDecoded('saved_previews.php', {
      'action': 'status',
      'variantID': variantId,
      'scanSessionId': scanSessionId,
    });
    if (data['isSaved'] != true) return null;
    return int.tryParse('${data['savedPreviewID']}');
  }
}
