import 'package:flutter/material.dart';

/// Apple-fluid entrance (apple-design-motion): content arrives with a
/// critically damped fade + small rise (16px), staggered by [index].
/// No overshoot — bounce is reserved for momentum-driven gestures.
///
/// Honors reduced motion (MediaQuery.disableAnimations): content appears
/// immediately with no translation.
class Entrance extends StatefulWidget {
  final Widget child;

  /// Position in the stagger sequence; each step adds [stepDelay].
  final int index;
  final Duration stepDelay;
  final Duration duration;

  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.stepDelay = const Duration(milliseconds: 55),
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _rise;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fade = curved;
    _rise = Tween<Offset>(begin: const Offset(0, 0.045), end: Offset.zero)
        .animate(curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _controller.value = 1.0;
    } else {
      Future.delayed(widget.stepDelay * widget.index, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _rise, child: widget.child),
    );
  }
}
