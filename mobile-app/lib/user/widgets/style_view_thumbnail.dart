import 'package:flutter/material.dart';

import '../api_config.dart';
import '../app_brand.dart';
import '../scanner/overlay_preview_image.dart';

/// Which of a haircut's three reference photographs to show.
enum StyleView { front, side, back }

extension StyleViewLabel on StyleView {
  String get label => switch (this) {
        StyleView.front => 'Front',
        StyleView.side => 'Side',
        StyleView.back => 'Back',
      };

  /// Every spelling these keys arrive under. The API uses snake_case, parts of
  /// the app have already remapped them to camelCase, and the library page adds
  /// a bare `image` for the front.
  List<String> get keys => switch (this) {
        StyleView.front => const ['front_view_url', 'frontViewUrl', 'image'],
        StyleView.side => const ['side_view_url', 'sideViewUrl', 'sideView'],
        StyleView.back => const ['back_view_url', 'backViewUrl', 'backView'],
      };
}

/// The URL or asset path for one view of a style, or '' when there is none.
String styleViewUrl(Map<String, dynamic> style, StyleView view) {
  for (final key in view.keys) {
    final value = style[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }

  return '';
}

/// One reference photograph of a haircut.
///
/// Both the bundled overlays and uploaded photos end up here, and they need
/// different treatment: a bundled overlay is a transparent cut-out that
/// disappears into a dark card without a light backing, while an uploaded
/// photo is an ordinary image. Pulled out of FaceScanResultsPage so the
/// recommendation details, the library and the try-on page all draw a view the
/// same way.
class StyleViewThumbnail extends StatelessWidget {
  final Map<String, dynamic> style;
  final StyleView view;
  final double size;
  final double? width;
  final VoidCallback? onTap;

  const StyleViewThumbnail({
    super.key,
    required this.style,
    this.view = StyleView.front,
    this.size = 58,
    this.width,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final raw = styleViewUrl(style, view);
    final bundled = raw.startsWith('assets/');

    final fallback = Center(
      child: Icon(
        Icons.content_cut,
        color: AppBrand.textMuted,
        size: (size * 0.38).clamp(14, 30),
      ),
    );

    Widget inner;
    if (raw.isEmpty) {
      inner = fallback;
    } else if (bundled) {
      inner = OverlayPreviewImage(
        assetPath: raw,
        fit: BoxFit.contain,
        errorWidget: fallback,
      );
    } else {
      inner = Image.network(
        ApiConfig.resolveImageUrl(raw),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    final tile = Container(
      width: width ?? size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bundled ? Colors.white : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(padding: const EdgeInsets.all(3), child: inner),
    );

    if (onTap == null || raw.isEmpty) return tile;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: tile,
    );
  }
}

/// Front, side and back side by side, with the views that have no image left
/// out rather than drawn as empty boxes.
///
/// The recommendation detail showed only the front, although the side and back
/// URLs were already on every row -- which mattered most for the cuts whose
/// whole point is what happens at the back.
class StyleViewStrip extends StatelessWidget {
  final Map<String, dynamic> style;
  final double height;
  final void Function(StyleView view)? onViewTap;

  const StyleViewStrip({
    super.key,
    required this.style,
    this.height = 92,
    this.onViewTap,
  });

  @override
  Widget build(BuildContext context) {
    final available = StyleView.values
        .where((view) => styleViewUrl(style, view).isNotEmpty)
        .toList();
    if (available.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (final view in available) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StyleViewThumbnail(
                  style: style,
                  view: view,
                  size: height,
                  width: double.infinity,
                  onTap: onViewTap == null ? null : () => onViewTap!(view),
                ),
                const SizedBox(height: 4),
                Text(
                  view.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (view != available.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// Front / Side / Back, as a segmented control.
///
/// Two screens had their own: the try-on page a SegmentedButton, the
/// recommendation page a hand-rolled row of ChoiceChips. They looked different
/// and they disagreed about what to call the third angle.
///
/// [labels] exists because the enum means two things. For a haircut's
/// reference photographs, Front / Side / Back is right. For the customer's own
/// scan it is not: the three captures are front, left profile and right
/// profile, so a tab reading "Back" promises a view of the back of their head
/// that was never photographed. Those screens pass [customerScanLabels].
class StyleViewSelector extends StatelessWidget {
  final StyleView selected;
  final ValueChanged<StyleView> onChanged;

  /// Overrides [StyleViewLabel.label] per view. Unset views keep the enum's.
  final Map<StyleView, String>? labels;

  /// Views to offer. Defaults to all three.
  final List<StyleView> views;

  const StyleViewSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.labels,
    this.views = StyleView.values,
  });

  /// What the customer's own three scan photos actually are.
  static const Map<StyleView, String> customerScanLabels = {
    StyleView.front: 'Front',
    StyleView.side: 'Left',
    StyleView.back: 'Right',
  };

  String labelFor(StyleView view) => labels?[view] ?? view.label;

  @override
  Widget build(BuildContext context) {
    // Colours come from the app's ColorScheme, set in main.dart. Hard-coding
    // them here is what left this control Material-default purple on a
    // blue-and-red brand.
    return SegmentedButton<StyleView>(
      segments: [
        for (final view in views)
          ButtonSegment(value: view, label: Text(labelFor(view))),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (set) {
        if (set.isEmpty) return;
        onChanged(set.first);
      },
    );
  }
}

/// Opens one view full-screen, so a customer can actually look at the haircut
/// rather than squint at a 92-pixel tile.
Future<void> showStyleViewViewer(
  BuildContext context,
  Map<String, dynamic> style,
  StyleView view,
) {
  final raw = styleViewUrl(style, view);
  if (raw.isEmpty) return Future.value();

  final styleName = style['style_name']?.toString() ??
      style['styleName']?.toString() ??
      style['name']?.toString() ??
      'Haircut';
  final bundled = raw.startsWith('assets/');

  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: bundled ? Colors.white : const Color(0xFF121212),
                padding: const EdgeInsets.all(8),
                child: bundled
                    ? OverlayPreviewImage(assetPath: raw, fit: BoxFit.contain)
                    : Image.network(
                        ApiConfig.resolveImageUrl(raw),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(32),
                          child: Icon(Icons.broken_image_outlined,
                              color: Colors.white38, size: 40),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$styleName — ${view.label}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    ),
  );
}
