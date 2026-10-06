import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The loyalty badge on the customer profile.
///
/// It used to be a flat outlined pill: the same shape for a first-timer as for
/// someone on their twentieth cut, with only the colour changing. A rank you
/// cannot feel is not much of a reward, so the badge now earns motion as it
/// climbs -- nothing at Rookie, a slow breath at Bronze, a sweep of light from
/// Silver, and a halo plus sparkle at Platinum.
///
/// Every effect is drawn from the tier's own colour, so a gold badge glows gold
/// and a bronze one glows bronze; nothing is hardcoded to the brand accent.
/// Honours "reduce motion", where it falls back to the static badge.
class TierBadge extends StatefulWidget {
  final String tier;
  final Color color;
  final VoidCallback? onTap;

  const TierBadge({
    super.key,
    required this.tier,
    required this.color,
    this.onTap,
  });

  /// How lively a rank is, 0 (Rookie) to 4 (Platinum).
  static int levelOf(String tier) {
    switch (tier) {
      case 'Platinum':
        return 4;
      case 'Gold':
        return 3;
      case 'Silver':
        return 2;
      case 'Bronze':
        return 1;
      default:
        return 0;
    }
  }

  @override
  State<TierBadge> createState() => _TierBadgeState();
}

class _TierBadgeState extends State<TierBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (TierBadge.levelOf(widget.tier) > 0) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(TierBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A badge that levels up mid-session should start moving straight away.
    if (widget.tier != oldWidget.tier) {
      if (TierBadge.levelOf(widget.tier) > 0) {
        if (!_controller.isAnimating) _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = TierBadge.levelOf(widget.tier);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final animate = level > 0 && !reduceMotion;

    if (!animate) {
      return _tappable(_pill(glow: 0, sweep: null, sparkle: 0));
    }

    return _tappable(
      AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;

          // Bronze onwards: a slow breath, so the badge is alive but calm.
          final pulse = (math.sin(t * math.pi * 2) + 1) / 2;
          final glow = level >= 1 ? 0.25 + (pulse * 0.1 * level) : 0.0;

          // Silver onwards: a band of light crosses the badge. The pause
          // between passes is what stops it reading as a loading shimmer.
          double? sweep;
          if (level >= 2) {
            final cycle = (t * 1.6) % 1.6;
            if (cycle <= 1) sweep = -1 + (cycle * 2.6);
          }

          // Platinum only: a single point of light that tracks the edge.
          final sparkle = level >= 4 ? t : 0.0;

          return _pill(glow: glow, sweep: sweep, sparkle: sparkle);
        },
      ),
    );
  }

  Widget _tappable(Widget child) {
    if (widget.onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }

  Widget _pill({required double glow, double? sweep, required double sparkle}) {
    final color = widget.color;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: glow > 0
            ? [
                BoxShadow(
                  color: color.withValues(alpha: glow * 0.6),
                  blurRadius: 10 + (glow * 14),
                  spreadRadius: glow * 1.5,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, color: color, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    widget.tier,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (sweep != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(sweep - 0.6, -1),
                        end: Alignment(sweep + 0.6, 1),
                        colors: [
                          Colors.transparent,
                          color.withValues(alpha: 0.38),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.5, 1],
                      ),
                    ),
                  ),
                ),
              ),
            if (sparkle > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SparklePainter(progress: sparkle, color: color),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single highlight running the badge's outline — the Platinum flourish.
class _SparklePainter extends CustomPainter {
  final double progress;
  final Color color;

  _SparklePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final perimeter = (size.width + size.height) * 2;
    final distance = (progress * perimeter) % perimeter;

    Offset point;
    if (distance < size.width) {
      point = Offset(distance, 0);
    } else if (distance < size.width + size.height) {
      point = Offset(size.width, distance - size.width);
    } else if (distance < (size.width * 2) + size.height) {
      point = Offset(size.width - (distance - size.width - size.height), size.height);
    } else {
      point = Offset(0, perimeter - distance);
    }

    canvas.drawCircle(
      point,
      3.0,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
