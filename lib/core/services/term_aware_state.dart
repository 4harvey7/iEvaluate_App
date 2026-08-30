// lib/core/services/term_aware_state.dart
//
// Makes a screen reload itself when the active academic term changes.
//
// Before this, roughly seventeen call sites each read the term once in
// initState and never looked again, so a screen already on-screen kept showing
// the previous term's numbers until it happened to be rebuilt. Adding a
// listener by hand in each one meant four lines of identical
// addListener/removeListener/mounted-check boilerplate per screen, with four
// chances each to forget the removeListener and leak.
//
// Usage:
//   class _FooScreenState extends State<FooScreen>
//       with TermAwareState<FooScreen> {
//     @override
//     void onTermChanged() => _loadData();
//   }
//
// The host's initState must call super.initState() and its dispose must call
// super.dispose() -- both are Flutter convention and every screen here already
// does. Mixin linearisation puts this between State and the screen, so the
// screen's own overrides run first and chain into these.
import 'package:flutter/widgets.dart';

import 'term_watcher.dart';

mixin TermAwareState<T extends StatefulWidget> on State<T> {
  /// Reload whatever on this screen is scoped to the active term.
  ///
  /// Called after the term has actually moved and the stale caches have been
  /// cleared -- never on first mount, so it does not duplicate the load the
  /// screen already does in initState.
  void onTermChanged();

  String? _seenTermId;

  @override
  void initState() {
    super.initState();
    _seenTermId = TermWatcher.instance.termId;
    TermWatcher.instance.addListener(_handleTermNotification);
  }

  @override
  void dispose() {
    TermWatcher.instance.removeListener(_handleTermNotification);
    super.dispose();
  }

  void _handleTermNotification() {
    if (!mounted) return;

    final watcher = TermWatcher.instance;

    // Wait for the switch to finish. The watcher notifies twice -- once when it
    // spots the new term, once after clearing the term-scoped caches. Reloading
    // on the first would race the cache clear and could re-save old numbers.
    if (watcher.isChanging) return;

    final next = watcher.termId;
    if (next == _seenTermId) return; // auto_sync or a no-op notification

    _seenTermId = next;
    onTermChanged();
  }
}
