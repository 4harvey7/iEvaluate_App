// lib/widgets/term_change_gate.dart
//
// Covers the app with "Updating term…" for as long as a term switch is in
// flight, wherever the user happens to be.
//
// The SAO admin's own device gets a blocking dialog from the settings screen,
// because there the switch is a deliberate action being waited on. Everyone
// else finds out through Realtime with no warning -- mid-scroll, mid-scan --
// and every term-scoped number on screen is stale for the second or two it
// takes the listening screens to re-query. Without this, that reads as the app
// glitching. With it, it reads as the app telling you what happened.
//
// Deliberately not a route: pushing one would fight whatever navigation the
// user is doing and could strand them on it. This is an overlay in the app's
// builder, above every route and below nothing.
import 'package:flutter/material.dart';

import '../core/services/term_watcher.dart';
import '../theme/app_colors.dart';

class TermChangeGate extends StatefulWidget {
  const TermChangeGate({super.key, required this.child});

  final Widget child;

  @override
  State<TermChangeGate> createState() => _TermChangeGateState();
}

class _TermChangeGateState extends State<TermChangeGate> {
  final TermWatcher _watcher = TermWatcher.instance;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _watcher.addListener(_onWatcher);
    _visible = _watcher.isChanging;
  }

  @override
  void dispose() {
    _watcher.removeListener(_onWatcher);
    super.dispose();
  }

  void _onWatcher() {
    if (!mounted) return;
    if (_visible != _watcher.isChanging) {
      setState(() => _visible = _watcher.isChanging);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // IgnorePointer when hidden so the invisible layer never eats taps.
        IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: _visible ? const _UpdatingTermScrim() : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _UpdatingTermScrim extends StatelessWidget {
  const _UpdatingTermScrim();

  @override
  Widget build(BuildContext context) {
    final label = TermWatcher.instance.termLabel;
    return Semantics(
      liveRegion: true,
      label: 'Updating term',
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding:
                const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 3,
                ),
                const SizedBox(height: 22),
                const Text(
                  'Updating term…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label == null
                      ? 'The SAO office changed the active term. Reloading your data.'
                      : 'The active term is now $label. Reloading your data.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.85),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
