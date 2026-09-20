// lib/widgets/blocking_progress_overlay.dart
//
// A non-dismissible progress dialog, for the handful of operations the user
// must not interrupt: switching the active term, deactivating an account.
//
// This is the logout overlay in showLoggingOutOverlay() with its two strings
// lifted out. That one stays where it is -- it is called from several places
// and its copy is specific -- but every later "please wait, this one matters"
// dialog should come from here rather than being pasted again.
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shows a blocking spinner with a title and one line of explanation.
///
/// Returns nothing: the caller owns dismissal, and must do it with
/// `Navigator.of(context, rootNavigator: true).pop()` in a `finally`, or the
/// user is stranded if the operation throws.
void showBlockingProgressOverlay(
  BuildContext context, {
  required String title,
  required String subtitle,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    // Root navigator so a dialog opened from inside a nested navigator (the
    // role tabs each have their own) still covers the whole screen.
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false, // the hardware back button must not strand the operation
      child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Closes an overlay opened by [showBlockingProgressOverlay].
///
/// Tolerates the route already being gone -- the screen underneath may have
/// been replaced (a deactivation ends at the login screen), and popping twice
/// would take a real route with it.
void dismissBlockingProgressOverlay(BuildContext context) {
  final nav = Navigator.of(context, rootNavigator: true);
  if (nav.canPop()) nav.pop();
}
