import 'package:flutter/material.dart';

/// Provides one looping shimmer animation to descendant [AppShimmerBox] widgets.
/// Prefer wrapping a whole skeleton section so many boxes share a single controller.
class AppShimmer extends StatefulWidget {
  const AppShimmer({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  static Animation<double>? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShimmerInherited>()?.animation;
  }

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AppShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!widget.enabled || reduceMotion) {
      _controller.stop();
      _controller.value = 0.35;
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerInherited(
      animation: _controller,
      child: widget.child,
    );
  }
}

class _ShimmerInherited extends InheritedWidget {
  const _ShimmerInherited({
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  @override
  bool updateShouldNotify(covariant _ShimmerInherited oldWidget) {
    return oldWidget.animation != animation;
  }
}

/// Dark-theme skeleton block with a subtle moving highlight.
/// Must be placed under [AppShimmer] for animation (falls back to static gray).
class AppShimmerBox extends StatelessWidget {
  const AppShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 6,
  });

  final double? width;
  final double height;
  final double borderRadius;

  static const Color _base = Color(0xFF2A2A2A);
  static const Color _highlight = Color(0xFF3A3A3A);

  @override
  Widget build(BuildContext context) {
    final animation = AppShimmer.of(context);
    final radius = BorderRadius.circular(borderRadius);

    final child = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _base,
        borderRadius: radius,
      ),
    );

    if (animation == null) {
      return child;
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment(-1.4 + 2.8 * animation.value, 0),
              end: Alignment(-0.2 + 2.8 * animation.value, 0),
              colors: const [
                _base,
                _highlight,
                _base,
              ],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}
