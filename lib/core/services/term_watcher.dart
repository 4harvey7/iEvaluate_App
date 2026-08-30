// lib/core/services/term_watcher.dart
//
// One app-wide subscription to the active academic term.
//
// WHY THIS EXISTS
// The term is the primary partition key of this whole data model -- 19 tables
// carry a term_id -- but it was read independently by about seventeen call
// sites, each doing its own one-shot query in initState. When the SAO admin
// switched the term, screens already on-screen kept showing the old term's
// numbers until they happened to be rebuilt, and the SharedPreferences
// dashboard caches would re-hydrate the *old* term's numbers on next mount.
//
// SystemSettingsService.streamSettings() was always the right idea, but only
// three screens subscribed, and the table was not in the supabase_realtime
// publication at all, so the stream never fired (fixed in migration
// 20240130000012). With replication on, one subscription here is enough for
// everyone: screens listen to this notifier instead of opening their own.
//
// Usage from a screen:
//   TermWatcher.instance.addListener(_onTerm);   // in initState
//   TermWatcher.instance.removeListener(_onTerm); // in dispose
// and in _onTerm, reload whatever is term-scoped.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'system_settings_service.dart';

/// SharedPreferences key prefixes whose contents are scoped to one term.
///
/// These hold cached dashboard numbers. Left alone, a term change would be
/// followed by the previous term's figures being restored from disk on the next
/// screen mount -- which looks exactly like the term change failing.
/// Preferences that are genuinely per-user rather than per-term (haptics, push
/// opt-in) are deliberately not listed.
const List<String> _termScopedCachePrefixes = <String>[
  'admin_dashboard_',
  'dept_dashboard_',
  'gatherer_dashboard_',
  'instructor_profile_',
  'subjects_cache_',
];

/// What a newly-observed [SystemSettings] means relative to the last one.
enum TermTransition {
  /// Nothing was known before. Publish it, but do not treat it as a change --
  /// the screen that is mounting will load this term anyway.
  firstSnapshot,

  /// Same term. Either a genuine no-op notification or a change to a field the
  /// data model is not partitioned on, such as auto_sync.
  unchanged,

  /// A different term is now active. Caches are stale and every term-scoped
  /// screen has to reload.
  changed,
}

/// Classifies a settings update. Pure, so the cases can be tested without a
/// Supabase client or a live Realtime socket.
///
/// The semester/year label is compared as well as the id: the SAO screen
/// upserts academic_terms on (semester, academic_year), so renaming the current
/// term keeps the same id while changing what every report is labelled. That
/// has to count as a change or the labels go stale.
TermTransition classifyTermChange(
  SystemSettings? previous,
  SystemSettings next,
) {
  if (previous == null) return TermTransition.firstSnapshot;
  if (previous.termId != next.termId) return TermTransition.changed;
  if (previous.semester != next.semester ||
      previous.academicYear != next.academicYear) {
    return TermTransition.changed;
  }
  return TermTransition.unchanged;
}

class TermWatcher extends ChangeNotifier with WidgetsBindingObserver {
  TermWatcher._();

  static final TermWatcher instance = TermWatcher._();

  /// Swappable for tests.
  @visibleForTesting
  SystemSettingsService settingsService = SystemSettingsService();

  StreamSubscription<SystemSettings>? _sub;
  SystemSettings? _current;
  bool _isChanging = false;
  bool _started = false;

  /// The last known settings, or null before the first snapshot arrives.
  SystemSettings? get current => _current;

  String? get termId => _current?.termId;

  /// `'1st Semester 2025-2026'`, or null before the first snapshot.
  String? get termLabel => _current == null
      ? null
      : '${_current!.semester} ${_current!.academicYear}';

  /// True from the moment a *different* term is observed until listeners have
  /// been notified and caches cleared. Drives the "Updating term…" overlay.
  bool get isChanging => _isChanging;

  /// Begins watching. Safe to call more than once; only the first call binds.
  ///
  /// Deliberately does not throw: a failure here must not stop the app from
  /// starting, it only means the term stops auto-updating.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Seed synchronously so the first screen to ask does not have to wait for
    // the stream's first event.
    try {
      _current = await settingsService.getSettings();
      notifyListeners();
    } catch (e) {
      debugPrint('[TermWatcher] initial fetch failed: $e');
    }

    _bind();

    // Catch a switch that happened while the app was backgrounded, where the
    // Realtime socket was suspended and may not replay what it missed.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Re-bind as well: a socket killed while backgrounded stays dead, and
    // subscribing again is cheap next to silently stopping auto-update.
    _bind();
    refreshNow();
  }

  void _bind() {
    _sub?.cancel();
    _sub = settingsService.streamSettings().listen(
      _onSettings,
      onError: (Object e) {
        // A dropped Realtime socket is not fatal -- screens still read the
        // term on mount. Log it so a permanently broken publication is
        // visible rather than silently degrading to manual refresh.
        debugPrint('[TermWatcher] stream error: $e');
      },
    );
  }

  Future<void> _onSettings(SystemSettings next) async {
    final String? previousTerm = _current?.termId;
    final transition = classifyTermChange(_current, next);

    _current = next;

    if (transition != TermTransition.changed) {
      // First snapshot, or a change to something we do not partition on
      // (auto_sync). Publish it without the overlay.
      notifyListeners();
      return;
    }

    debugPrint('[TermWatcher] term changed: $previousTerm -> ${next.termId}');
    _isChanging = true;
    notifyListeners();

    await clearTermScopedCaches();

    _isChanging = false;
    notifyListeners();
  }

  /// Drops every cached blob whose contents belong to the previous term.
  ///
  /// Public because the SAO admin's own device writes the change rather than
  /// receiving it, so that screen clears caches directly.
  Future<void> clearTermScopedCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final doomed = prefs
          .getKeys()
          .where((k) => _termScopedCachePrefixes.any(k.startsWith))
          .toList();
      for (final key in doomed) {
        await prefs.remove(key);
      }
      if (doomed.isNotEmpty) {
        debugPrint('[TermWatcher] cleared ${doomed.length} stale cache key(s)');
      }
    } catch (e) {
      // A stale cache is a display bug, not a crash. Screens re-query anyway.
      debugPrint('[TermWatcher] cache clear failed: $e');
    }
  }

  /// Forces a re-read now. Used by the admin screen right after it writes a new
  /// term, so its own device does not wait for the round trip.
  Future<void> refreshNow() async {
    try {
      final next = await settingsService.getSettings();
      await _onSettings(next);
    } catch (e) {
      debugPrint('[TermWatcher] refreshNow failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _sub = null;
    _started = false;
    super.dispose();
  }

  /// Test hook: drops the subscription and cached value without disposing the
  /// singleton, so each test starts clean.
  @visibleForTesting
  Future<void> resetForTest() async {
    WidgetsBinding.instance.removeObserver(this);
    await _sub?.cancel();
    _sub = null;
    _current = null;
    _isChanging = false;
    _started = false;
  }
}
