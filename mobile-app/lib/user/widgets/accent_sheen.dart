import 'package:flutter/material.dart';

import '../app_brand.dart';

/// A slow accent gradient that drifts across a card.
///
/// Flat dark panels all read the same at a glance, so nothing on the home
/// screen pulled the eye. This gives each card a tinted wash in its own accent
/// colour and moves it just enough to feel alive without competing with the
/// text sitting on top -- the motion is in the background, never under the
/// words being read.
///
/// Honours the platform "reduce motion" setting: when animations are disabled
/// the gradient still tints the card, it simply stops moving.
class AccentSheen extends StatefulWidget {
  final Color accent;
  final BorderRadius borderRadius;
  final Widget child;

  /// Seconds for one full pass. Longer reads as ambient, shorter as busy;
  /// under about 10 the drift starts to pull the eye off the text.
  final int periodSeconds;

  /// How strongly the accent tints the surface. 1 is the default wash; higher
  /// values suit a static card, which can carry more colour than a moving one
  /// without becoming distracting.
  final double intensity;

  const AccentSheen({
    super.key,
    required this.accent,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.periodSeconds = 7,
    this.intensity = 1,
  });

  @override
  State<AccentSheen> createState() => _AccentSheenState();
}

class _AccentSheenState extends State<AccentSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.periodSeconds),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Deliberately faint. At 0.16 the wash read as a coloured card rather than
    // a sheen, and the "Recent haircut" card's white accent turned the whole
    // panel grey. The tint should be felt, not seen.
    final tint = widget.accent.withValues(alpha: 0.07 * widget.intensity);
    final edge = widget.accent.withValues(alpha: 0.02 * widget.intensity);

    if (reduceMotion) {
      _controller.stop();
      return _surface(const Alignment(-0.6, -1), const Alignment(0.6, 1), tint, edge);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Sweeping the gradient's anchor points rather than its colours keeps
        // the card's contrast constant, so text never dips below legibility
        // mid-animation.
        final t = Curves.easeInOut.transform(_controller.value);
        // A short travel over a long period: the wash shifts rather than
        // sweeps, so it reads as the card breathing, not as something sliding
        // past behind the text.
        final begin = Alignment(-1.0 + (t * 0.5), -1);
        final end = Alignment(0.4 + (t * 0.5), 1);

        return _surface(begin, end, tint, edge, child);
      },
      child: widget.child,
    );
  }

  Widget _surface(
    Alignment begin,
    Alignment end,
    Color tint,
    Color edge, [
    Widget? child,
  ]) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        border: Border.all(color: widget.accent.withValues(alpha: 0.16)),
        gradient: LinearGradient(
          begin: begin,
          end: end,
          colors: [AppBrand.surface, tint, AppBrand.surface, edge],
          stops: const [0, 0.35, 0.72, 1],
        ),
      ),
      child: child ?? widget.child,
    );
  }
}
