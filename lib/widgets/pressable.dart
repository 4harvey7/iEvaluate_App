import 'package:flutter/material.dart';

/// Apple-fluid press feedback (apple-design-motion):
/// responds on pointer-DOWN — never on release — by scaling to
/// [pressedScale] in ~90ms, then settling back critically damped.
///
/// Uses a [Listener] (not a GestureDetector) so it NEVER competes with the
/// child's own tap/long-press handlers — buttons keep working untouched.
/// Purely visual; zero functional impact.
class Pressable extends StatefulWidget {
  final Widget child;
  final double pressedScale;

  const Pressable({
    super.key,
    required this.child,
    this.pressedScale = 0.97,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        // Instant on press, critically-damped settle on release.
        duration: reduceMotion
            ? Duration.zero
            : (_down
                ? const Duration(milliseconds: 90)
                : const Duration(milliseconds: 280)),
        curve: _down ? Curves.easeOut : Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
