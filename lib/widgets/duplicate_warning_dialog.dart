import 'package:flutter/material.dart';

import '../core/services/identity_validator.dart';
import '../theme/app_colors.dart';
import 'apple_ui.dart';

/// Popup shown when a name, email or ID already belongs to another account.
///
/// A duplicate is not a passing "oops" the way a missing field is -- it means
/// the person you are trying to add is already in the system, and the answer is
/// usually to go find them rather than to retype anything. A snackbar slides
/// away after a few seconds and is easy to miss behind a keyboard, so these get
/// a modal that has to be dismissed deliberately.
///
/// Format errors ("email is required") stay as snackbars. Only conflicts come
/// here.
Future<void> showDuplicateWarningDialog(
  BuildContext context, {
  required String message,
  IdentityField? field,
}) {
  return showDialog<void>(
    context: context,
    // Deliberately not dismissible by tapping outside: the whole point is that
    // the admin reads it.
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            AppleIconBadge(
              icon: _iconFor(field),
              color: AppColors.warning,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _titleFor(field),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.45,
          ),
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// Shows the modal when [result] is a conflict. Returns true if it was shown,
/// so a caller can write `if (await ...) return;` and stop there.
Future<bool> showConflictIfAny(
  BuildContext context,
  IdentityCheckResult result,
) async {
  if (result.isAvailable) return false;
  await showDuplicateWarningDialog(
    context,
    message: result.error!,
    field: result.field,
  );
  return true;
}

/// True when an edge function reported a duplicate rather than some other
/// failure.
///
/// Every conflict message the server produces is built by `describeConflict` in
/// supabase/functions/_shared/identity_guard.ts, which always prefixes
/// 'Duplicate:'. That prefix is the contract -- if it changes there, change it
/// here. Used so the race case (two admins submitting the same person at once,
/// caught by the unique index rather than the pre-flight check) still gets the
/// modal instead of a snackbar.
bool isDuplicateMessage(String message) => message.startsWith('Duplicate');

String _titleFor(IdentityField? field) {
  switch (field) {
    case IdentityField.universityId:
      return 'ID Already Used';
    case IdentityField.email:
      return 'Email Already Used';
    case IdentityField.name:
      return 'Name Already Used';
    case null:
      return 'Already In The Database';
  }
}

IconData _iconFor(IdentityField? field) {
  switch (field) {
    case IdentityField.universityId:
      return Icons.badge_outlined;
    case IdentityField.email:
      return Icons.alternate_email_rounded;
    case IdentityField.name:
      return Icons.person_search_rounded;
    case null:
      return Icons.warning_amber_rounded;
  }
}
