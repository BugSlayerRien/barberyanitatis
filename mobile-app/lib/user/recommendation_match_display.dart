import 'package:flutter/material.dart';

/// UI helpers for PHP `match_percent` + `match_breakdown` from ai_scan.php.
class RecommendationMatchDisplay {
  static int? matchPercent(Map<String, dynamic> item) {
    final raw = item['match_percent'] ?? item['matchPercent'];
    if (raw is int) return raw.clamp(0, 100);
    if (raw is num) return raw.round().clamp(0, 100);
    return null;
  }

  static String? rankLabel(Map<String, dynamic> item) {
    final raw = item['match_rank_label'] ?? item['matchRankLabel'];
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String fitReasonTeaser(Map<String, dynamic> item) {
    final reason = item['fit_reason']?.toString().trim() ?? '';
    if (reason.isEmpty) {
      return 'Tap to see why this style fits you.';
    }
    final dot = reason.indexOf('.');
    if (dot > 0 && dot < 120) {
      return reason.substring(0, dot + 1);
    }
    if (reason.length <= 120) return reason;
    return '${reason.substring(0, 117)}...';
  }

  static List<Map<String, dynamic>> breakdown(Map<String, dynamic> item) {
    final raw = item['match_breakdown'] ?? item['matchBreakdown'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Widget percentBadge(int percent, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2410),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFC9B46A).withValues(alpha: 0.55)),
      ),
      child: Text(
        '$percent% match',
        style: TextStyle(
          color: const Color(0xFFC9B46A),
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static Widget breakdownPanel(
    Map<String, dynamic> item, {
    bool dense = false,
  }) {
    final lines = breakdown(item);
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Why this score',
          style: TextStyle(
            color: Colors.white54,
            fontSize: dense ? 10 : 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: dense ? 4 : 6),
        ...lines.map((line) => _breakdownRow(line, dense: dense)),
      ],
    );
  }

  static Widget _breakdownRow(Map<String, dynamic> line, {required bool dense}) {
    final label = line['label']?.toString() ?? 'Factor';
    final detail = line['detail']?.toString() ?? '';
    final contribution = _contributionValue(line['contribution']);
    final contribText = contribution == null
        ? ''
        : (contribution >= 0 ? '+${contribution.toStringAsFixed(2)}' : contribution.toStringAsFixed(2));

    Color contribColor = Colors.white38;
    if (contribution != null) {
      if (contribution > 0) {
        contribColor = const Color(0xFF8BC34A);
      } else if (contribution < 0) {
        contribColor = const Color(0xFFE57373);
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (contribText.isNotEmpty)
            SizedBox(
              width: 44,
              child: Text(
                contribText,
                style: TextStyle(
                  color: contribColor,
                  fontSize: dense ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: dense ? 11 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: dense ? 10 : 11,
                      height: 1.25,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double? _contributionValue(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw');
  }
}
