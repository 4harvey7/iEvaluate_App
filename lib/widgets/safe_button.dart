/// safe_button.dart
///
/// Drop-in replacements for Flutter's built-in buttons that prevent
/// double-taps on async handlers. users love to spam buttons like crazy,
/// this file fix that problem. each widget manage its own _isLoading state:
/// once pressed the button is disabled and show a spinner until future complete
/// (success or error). pray lang the async finish fast.
///
/// Usage -- replace:
///   ElevatedButton(onPressed: () async { ... })
/// with:
///   SafeElevatedButton(onPressed: () async { ... })
/// simple swap, dili ta need rewrite everything.

library safe_button;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Internal mixin -- shared loading-state logic used by all Safe button variants
// this mixin is the secret sauce, importente kaayo, ayaw remove
// ─────────────────────────────────────────────────────────────────────────────

mixin _SafeButtonMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false; // tracks if button currently doing async work, starts as false

  /// Wraps [callback] with a loading guard so button cant be tapped twice.
  /// if already loading or callback is null, it do nothing -- wala choice, dili pwede proceed.
  /// sets _isLoading true before, false after, whether it succeed or crash.
  Future<void> handlePress(Future<void> Function()? callback) async {
    if (_isLoading || callback == null) return; // already busy or nothing to do, skip
    if (mounted) setState(() => _isLoading = true); // lock the button, user cannot spam now
    try {
      await callback(); // do the actual work, bahala na what happen
    } finally {
      if (mounted) setState(() => _isLoading = false); // always unlock after done, even if error
    }
  }

  /// A small circular progress indicator styled to match button text colour.
  /// this is the little spinning thing that replace the button text while loading.
  Widget loadingIndicator({Color color = Colors.white, double size = 20}) {
    return SizedBox(
      height: size,
      width: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: color), // thin spinner, not too chunky
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SafeElevatedButton
// the solid filled button with spam protection. use this instead of ElevatedButton
// when onPressed is async, dili ta use the plain one for async ops
// ─────────────────────────────────────────────────────────────────────────────

class SafeElevatedButton extends StatefulWidget {
  final Future<void> Function()? onPressed; // the async callback, can be null to disable button
  final Widget child;                        // the button label or content
  final ButtonStyle? style;                  // optional custom styling
  final Widget? loadingChild;               // optional custom loading widget, defaults to spinner

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
    return ElevatedButton(
      style: widget.style,
      onPressed: _isLoading ? null : () => handlePress(widget.onPressed), // disable while loading, ayaw allow double tap
      child: _isLoading
          ? (widget.loadingChild ?? loadingIndicator()) // show spinner or custom loading widget
          : widget.child,                               // show normal child when not loading
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
  final Widget child;                        // the button label
  final ButtonStyle? style;                  // optional styling
  final Widget? loadingChild;               // optional custom loading widget

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
    return OutlinedButton(
      style: widget.style,
      onPressed: _isLoading ? null : () => handlePress(widget.onPressed), // locked while loading
      child: _isLoading
          ? (widget.loadingChild ??
              loadingIndicator(color: Theme.of(context).colorScheme.primary)) // use primary color for outlined spinner
          : widget.child,
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
  final Widget child;                        // the label widget
  final ButtonStyle? style;                  // optional styling, can be null

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
class _SafeTextButtonState extends State<SafeTextButton>
    with _SafeButtonMixin {
  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: widget.style,
      onPressed: _isLoading ? null : () => handlePress(widget.onPressed), // no tap while loading
      child: _isLoading
          ? loadingIndicator(
              color: Theme.of(context).colorScheme.primary, size: 16) // smaller spinner for text button
          : widget.child,
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
  final Widget icon;                         // the icon to display
  final String? tooltip;                     // hover tooltip text, optional
  final Color? color;                        // icon color, optional
  final double? iconSize;                    // icon size, defaults to 24

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
class _SafeIconButtonState extends State<SafeIconButton>
    with _SafeButtonMixin {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      color: widget.color,
      iconSize: widget.iconSize ?? 24, // default size 24 if not specified
      onPressed: _isLoading ? null : () => handlePress(widget.onPressed), // disabled while loading
      icon: _isLoading
          ? loadingIndicator(color: widget.color ?? Colors.white, size: 18) // slightly smaller spinner for icon button
          : widget.icon,
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
  final Widget child;                    // the widget to make tappable
  final BorderRadius? borderRadius;     // optional border radius for the ink ripple

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
    return InkWell(
      borderRadius: widget.borderRadius,
      onTap: _isLoading ? null : () => handlePress(widget.onTap), // null onTap means inkwell disabled while loading
      child: widget.child, // always show the child, we dont swap it for spinner here
    );
  }
}
