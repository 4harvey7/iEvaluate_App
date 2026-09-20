// Drop-in replacements for Flutter's built-in buttons that prevent repeated
// submissions while an async action is running.

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'apple_ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Internal mixin -- shared loading-state logic used by all Safe button variants
// this mixin is the secret sauce, importente kaayo, ayaw remove
// ─────────────────────────────────────────────────────────────────────────────

mixin _SafeButtonMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading =
      false; // tracks if button currently doing async work, starts as false

  /// Wraps [callback] with a loading guard so button cant be tapped twice.
  /// if already loading or callback is null, it do nothing -- wala choice, dili pwede proceed.
  /// sets _isLoading true before, false after, whether it succeed or crash.
  Future<void> handlePress(Future<void> Function()? callback) async {
    if (_isLoading || callback == null) {
      return;
    }
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      await callback();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// A small circular progress indicator styled to match button text colour.
  /// this is the little spinning thing that replace the button text while loading.
  Widget loadingIndicator({Color color = Colors.white, double size = 20}) {
    return SizedBox(
      height: size,
      width: size,
      child: CupertinoActivityIndicator(
        radius: size / 2,
        color: color,
      ), // thin spinner, not too chunky
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SafeElevatedButton
// the solid filled button with spam protection. use this instead of ElevatedButton
// when onPressed is async, dili ta use the plain one for async ops
// ─────────────────────────────────────────────────────────────────────────────

class SafeElevatedButton extends StatefulWidget {
  final Future<void> Function()?
  onPressed; // the async callback, can be null to disable button
  final Widget child; // the button label or content
  final ButtonStyle? style; // optional custom styling
  final Widget?
  loadingChild; // optional custom loading widget, defaults to spinner

  const SafeElevatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.loadingChild,
  });

  @override
  State<SafeElevatedButton> createState() => _SafeElevatedButtonState();
}

// the state class for SafeElevatedButton, mixes in _SafeButtonMixin for the loading logic
class _SafeElevatedButtonState extends State<SafeElevatedButton>
    with _SafeButtonMixin {
  @override
  Widget build(BuildContext context) {
    final enabled = !_isLoading && widget.onPressed != null;
    return ApplePressable(
      enabled: enabled,
      pressedScale: 0.985,
      child: ElevatedButton(
        style: widget.style,
        onPressed: enabled ? () => handlePress(widget.onPressed) : null,
        child: _isLoading
            ? (widget.loadingChild ?? loadingIndicator())
            : widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SafeOutlinedButton
// the outlined (border only) button with spam protection.
// use this when you need the outlined style but the handler is async
// ─────────────────────────────────────────────────────────────────────────────

class SafeOutlinedButton extends StatefulWidget {
  final Future<void> Function()? onPressed; // the async callback
  final Widget child; // the button label
  final ButtonStyle? style; // optional styling
  final Widget? loadingChild; // optional custom loading widget

  const SafeOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.loadingChild,
  });

  @override
  State<SafeOutlinedButton> createState() => _SafeOutlinedButtonState();
}

// state for SafeOutlinedButton, same mixin pattern as the elevated version
class _SafeOutlinedButtonState extends State<SafeOutlinedButton>
    with _SafeButtonMixin {
  @override
  Widget build(BuildContext context) {
    final enabled = !_isLoading && widget.onPressed != null;
    return ApplePressable(
      enabled: enabled,
      pressedScale: 0.985,
      child: OutlinedButton(
        style: widget.style,
        onPressed: enabled ? () => handlePress(widget.onPressed) : null,
        child: _isLoading
            ? (widget.loadingChild ??
                  loadingIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ))
            : widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SafeTextButton
// the flat text-only button with spam protection. no border, no fill, just text.
// but still protected from double tap, dili ta underestimate this one
// ─────────────────────────────────────────────────────────────────────────────

class SafeTextButton extends StatefulWidget {
  final Future<void> Function()? onPressed; // the async callback
  final Widget child; // the label widget
  final ButtonStyle? style; // optional styling, can be null

  const SafeTextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });

  @override
  State<SafeTextButton> createState() => _SafeTextButtonState();
}

// state for SafeTextButton
class _SafeTextButtonState extends State<SafeTextButton> with _SafeButtonMixin {
  @override
  Widget build(BuildContext context) {
    final enabled = !_isLoading && widget.onPressed != null;
    return ApplePressable(
      enabled: enabled,
      pressedScale: 0.97,
      child: TextButton(
        style: widget.style,
        onPressed: enabled ? () => handlePress(widget.onPressed) : null,
        child: _isLoading
            ? loadingIndicator(
                color: Theme.of(context).colorScheme.primary,
                size: 16,
              )
            : widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SafeIconButton
// the icon-only button with spam protection.
// basin user think icon button is safe to spam. it is not. we handle it.
// ─────────────────────────────────────────────────────────────────────────────

class SafeIconButton extends StatefulWidget {
  final Future<void> Function()? onPressed; // the async callback
  final Widget icon; // the icon to display
  final String? tooltip; // hover tooltip text, optional
  final Color? color; // icon color, optional
  final double? iconSize; // icon size, defaults to 24

  const SafeIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.color,
    this.iconSize,
  });

  @override
  State<SafeIconButton> createState() => _SafeIconButtonState();
}

// state for SafeIconButton
class _SafeIconButtonState extends State<SafeIconButton> with _SafeButtonMixin {
  @override
  Widget build(BuildContext context) {
    final enabled = !_isLoading && widget.onPressed != null;
    return ApplePressable(
      enabled: enabled,
      pressedScale: 0.90,
      child: IconButton(
        tooltip: widget.tooltip,
        color: widget.color,
        iconSize: widget.iconSize ?? 24,
        onPressed: enabled ? () => handlePress(widget.onPressed) : null,
        icon: _isLoading
            ? loadingIndicator(
                color: widget.color ?? Theme.of(context).colorScheme.primary,
                size: 18,
              )
            : widget.icon,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SafeInkWell  (for GestureDetector / InkWell / ListTile onTap patterns)
// wrap any tappable widget with this to get spam protection for free.
// useful for custom tap areas that are not normal buttons, wala need reinvent logic
// ─────────────────────────────────────────────────────────────────────────────

class SafeInkWell extends StatefulWidget {
  final Future<void> Function()? onTap; // the async tap callback
  final Widget child; // the widget to make tappable
  final BorderRadius? borderRadius; // optional border radius for the ink ripple

  const SafeInkWell({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius,
  });

  @override
  State<SafeInkWell> createState() => _SafeInkWellState();
}

// state for SafeInkWell, same mixin, same pattern
class _SafeInkWellState extends State<SafeInkWell> with _SafeButtonMixin {
  @override
  Widget build(BuildContext context) {
    final enabled = !_isLoading && widget.onTap != null;
    return ApplePressable(
      enabled: enabled,
      pressedScale: 0.985,
      child: InkWell(
        borderRadius: widget.borderRadius,
        onTap: enabled ? () => handlePress(widget.onTap) : null,
        child: widget.child,
      ),
    );
  }
}
