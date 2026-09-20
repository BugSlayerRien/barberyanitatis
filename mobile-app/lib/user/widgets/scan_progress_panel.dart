import 'dart:async';

import 'package:flutter/material.dart';

import '../app_brand.dart';

/// Progress display for the two long waits in the AI flow.
///
/// Two deliberately different modes, because only one of them has real progress
/// to report:
///
/// * [ScanProgressPanel.steps] — the scan phase performs discrete client-driven
///   calls (save, upload, analyze), so "step 2 of 3" is a fact and the bar is
///   determinate.
/// * [ScanProgressPanel.indeterminate] — generation is a single blocking server
///   call that returns all three angles at once (`ai_tryon_generate_three_view_previews`).
///   Nothing reports partial completion, so this shows the pipeline stages and
///   an elapsed timer rather than a percentage that would be invented.
///
/// Do not add a percentage to the indeterminate mode without a real
/// server-side progress source to drive it.
class ScanProgressPanel extends StatefulWidget {
  final List<String> stages;

  /// 0-based index of the stage in flight. Null means no stage is known to be
  /// active yet (indeterminate mode animates through them instead).
  final int? currentStep;

  /// Whether real progress is known. False shows an indeterminate bar.
  final bool determinate;

  /// Shows a running timer, so a long wait reads as working rather than stuck.
  final bool showElapsed;

  final String? title;

  const ScanProgressPanel.steps({
    super.key,
    required this.stages,
    required int this.currentStep,
    this.title,
    this.showElapsed = false,
  }) : determinate = true;

  const ScanProgressPanel.indeterminate({
    super.key,
    required this.stages,
    this.currentStep,
    this.title,
    this.showElapsed = true,
  }) : determinate = false;

  @override
  State<ScanProgressPanel> createState() => _ScanProgressPanelState();
}

class _ScanProgressPanelState extends State<ScanProgressPanel> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.showElapsed) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _elapsedLabel {
    final minutes = _elapsed.inMinutes;
    final seconds = _elapsed.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.stages.length;
    final step = widget.currentStep;
    final progress = widget.determinate && total > 0 && step != null
        ? ((step + 1) / total).clamp(0.0, 1.0)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null) ...[
            Text(
              widget.title!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(AppBrand.accent),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < total; i++) _stageRow(i, step),
          if (widget.showElapsed) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule, size: 13, color: Colors.white38),
                const SizedBox(width: 6),
                Text(
                  '$_elapsedLabel elapsed',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stageRow(int index, int? step) {
    final isDone = step != null && index < step;
    final isActive = step != null && index == step;

    final Widget marker;
    if (isDone) {
      marker = const Icon(Icons.check_circle, size: 15, color: AppBrand.accent);
    } else if (isActive) {
      marker = const SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppBrand.accent),
      );
    } else {
      marker = const Icon(Icons.circle_outlined, size: 14, color: Colors.white24);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 18, child: Center(child: marker)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.stages[index],
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : (isDone ? Colors.white54 : Colors.white38),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
