// lib/core/services/identity_validator.dart
//
// One place that decides whether a name, email or university ID may be used.
//
// Three screens create accounts -- the public registration screen, SAO Admin ->
// Personnel Management, and SAO Admin -> User Management -- plus the two edit
// dialogs that can rename someone into a collision. Before this file they each
// had their own partial rules, so a value rejected on one screen was accepted
// on another. Everything now routes through here.
//
// THE RULES
//   university_id  unique across all active accounts (case-insensitive)
//   email          unique across all active accounts (case-insensitive)
//   first + last   unique TOGETHER
//
// Sharing only one half of a name is fine and always was:
//   Juan Cruz + Juan Santos   -> allowed (same first name)
//   Juan Cruz + Maria Cruz    -> allowed (same last name)
//   Juan Cruz + Juan Cruz     -> blocked
//
// Both allowed cases log in normally. Sign-in resolves an account by university
// ID or email and never by name, so people sharing a first or last name are
// never confused for each other at the login screen.
//
// WHERE THE GUARANTEE ACTUALLY LIVES
// Not here. This file is the fast, friendly check that runs before submitting.
// The real guarantee is the set of unique indexes in
// supabase/migrations/20240130000008_identity_uniqueness.sql, because a
// "SELECT then INSERT" in app code cannot be safe: two submissions milliseconds
// apart both read "available" and both insert. This file exists so the user
// gets a clear message instead of a raw database error, and so the account is
// never half-created. mapDatabaseError below catches the race.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which field a duplicate was found on.
enum IdentityField { universityId, email, name }

/// Outcome of a duplicate check. [error] is ready to show to the user as-is.
class IdentityCheckResult {
  const IdentityCheckResult.ok() : error = null, field = null;
  const IdentityCheckResult.conflict(this.field, this.error);

  final String? error;
  final IdentityField? field;

  bool get isAvailable => error == null;
}

class IdentityValidator {
  IdentityValidator._();

  /// What the ID field is called to the user on the screen doing the asking.
  ///
  /// The database column is always `university_id`, but SAO Personnel
  /// Management calls it a Staff ID, so every message that screen produces has
  /// to say Staff ID too -- a field labelled one thing and an error naming
  /// another is how people conclude the app is broken.
  static const String defaultIdLabel = 'University ID';
  static const String staffIdLabel = 'Staff ID';

  /// Names in this system may contain letters (including ñ and accented
  /// characters), spaces, hyphens, apostrophes and full stops -- enough for
  /// "Maria-Clara", "O'Brien", "Peñaflor", "Cruz Jr.". Digits are rejected.
  static final RegExp _namePattern = RegExp(
    r"^\p{L}[\p{L}\p{M}\s'\-.]*$",
    unicode: true,
  );

  /// University IDs are letters, digits and hyphens. Matches the rule the
  /// registration screen already applied.
  static final RegExp _universityIdPattern = RegExp(r'^[a-zA-Z0-9\-]+$');

  static final RegExp _emailPattern = RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,}$');

  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Canonical form used for every comparison.
  ///
  /// Must stay in step with `public.norm_identity(text)` in the migration --
  /// lower-cased, ends trimmed, runs of inner whitespace collapsed to one
  /// space. Without the collapse, "Juan  Cruz" and "Juan Cruz" would be stored
  /// as two different people.
  static String normalise(String? value) {
    if (value == null) return '';
    return value.toLowerCase().replaceAll(_whitespaceRun, ' ').trim();
  }

  /// Cleans a value for STORAGE. Keeps the original capitalisation -- people's
  /// names are theirs -- but removes the stray whitespace that would otherwise
  /// slip a near-duplicate past a comparison.
  static String clean(String? value) {
    if (value == null) return '';
    return value.replaceAll(_whitespaceRun, ' ').trim();
  }

  /// Emails are additionally lower-cased for storage. Mail servers treat the
  /// domain as case-insensitive and every real provider does the same with the
  /// mailbox, so storing one canonical form keeps the login lookup honest.
  static String cleanEmail(String? value) => clean(value).toLowerCase();

  // ── Format rules ──────────────────────────────────────────────────────────

  /// [label] is used in the message, e.g. 'First name'.
  static String? validateName(String? value, String label) {
    final cleaned = clean(value);
    if (cleaned.isEmpty) return '$label is required';
    // Two characters is the practical floor: a one-letter staff name is almost
    // always a typo or an initial left in the wrong field. Relax here if a
    // genuine single-letter name turns up.
    if (cleaned.length < 2) return '$label must be at least 2 characters';
    if (cleaned.length > 60) return '$label is too long (max 60 characters)';
    if (!_namePattern.hasMatch(cleaned)) {
      return '$label may only contain letters, spaces, hyphens and apostrophes';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    final cleaned = cleanEmail(value);
    if (cleaned.isEmpty) return 'Email is required';
    if (cleaned.contains(' ')) return 'Email cannot contain spaces';
    if (cleaned.length > 254) return 'Email is too long';
    if (!_emailPattern.hasMatch(cleaned)) return 'Enter a valid email address';
    return null;
  }

  static String? validateUniversityId(
    String? value, {
    String label = defaultIdLabel,
  }) {
    final cleaned = clean(value);
    if (cleaned.isEmpty) return '$label is required';
    if (cleaned.length < 4) return '$label must be at least 4 characters';
    if (cleaned.length > 30) return '$label is too long (max 30 characters)';
    if (!_universityIdPattern.hasMatch(cleaned)) {
      return '$label must be letters, numbers, or hyphens only';
    }
    return null;
  }

  /// Runs every format rule and returns the first problem, or null if the whole
  /// set is well-formed. Pass only the fields a given screen collects.
  static String? validateFormat({
    String? firstName,
    String? lastName,
    String? email,
    String? universityId,
    String idLabel = defaultIdLabel,
  }) {
    if (firstName != null) {
      final e = validateName(firstName, 'First name');
      if (e != null) return e;
    }
    if (lastName != null) {
      final e = validateName(lastName, 'Last name');
      if (e != null) return e;
    }
    if (email != null) {
      final e = validateEmail(email);
      if (e != null) return e;
    }
    if (universityId != null) {
      final e = validateUniversityId(universityId, label: idLabel);
      if (e != null) return e;
    }
    return null;
  }

  // ── Duplicate check ───────────────────────────────────────────────────────

  /// Asks the database whether these values are free.
  ///
  /// Calls the `check_identity_conflict` RPC rather than selecting from
  /// user_info directly. A direct SELECT would in fact work today -- the table
  /// carries a policy `"Allow anonymous email lookup" SELECT TO anon USING
  /// (true)`, which login-by-university-ID depends on -- but relying on that is
  /// two problems. It couples this check to a policy that exists for an
  /// unrelated reason and should eventually be narrowed, and it means every
  /// caller receives whole rows when all it needs is one field name. The RPC is
  /// SECURITY DEFINER, so it keeps working if that policy is tightened, and it
  /// returns a field name and nothing else.
  ///
  /// [excludeUserId] is the account being edited, so a rename does not collide
  /// with itself.
  ///
  /// If the RPC itself cannot be reached this returns available. It is a
  /// pre-flight courtesy, not the guarantee -- the unique indexes still reject
  /// a duplicate insert, and [mapDatabaseError] turns that into the same
  /// message. Blocking every account creation because one check timed out
  /// would be the worse failure.
  static Future<IdentityCheckResult> checkAvailability({
    required SupabaseClient client,
    String? firstName,
    String? lastName,
    String? email,
    String? universityId,
    String? excludeUserId,
    String idLabel = defaultIdLabel,
  }) async {
    try {
      final conflict = await client.rpc(
        'check_identity_conflict',
        params: {
          'p_first_name': firstName == null ? null : clean(firstName),
          'p_last_name': lastName == null ? null : clean(lastName),
          'p_email': email == null ? null : cleanEmail(email),
          'p_university_id': universityId == null ? null : clean(universityId),
          'p_exclude_id': excludeUserId,
        },
      );

      final code = conflict?.toString();
      if (code == null || code.isEmpty || code == 'null') {
        return const IdentityCheckResult.ok();
      }
      return _conflictFor(
        code,
        firstName: firstName,
        lastName: lastName,
        idLabel: idLabel,
      );
    } on SocketException {
      debugPrint('[IDENTITY] Availability check skipped: no connection.');
      return const IdentityCheckResult.ok();
    } catch (e) {
      // Most likely the migration has not been applied yet, so the function
      // does not exist. Loud in debug, silent for the user, and the unique
      // indexes (once applied) remain the real gate.
      debugPrint('[IDENTITY] Availability check unavailable: $e');
      return const IdentityCheckResult.ok();
    }
  }

  /// Turns a unique-index violation into the same message the pre-flight check
  /// would have produced.
  ///
  /// This is the path taken when two people submit at nearly the same instant:
  /// both pre-flight checks said "available", then the database rejected the
  /// second insert. Returns null for anything that is not a duplicate error, so
  /// callers can fall through to their normal error handling.
  static String? mapDatabaseError(
    Object error, {
    String? firstName,
    String? lastName,
    String idLabel = defaultIdLabel,
  }) {
    final raw = error is PostgrestException
        ? '${error.code} ${error.message} ${error.details ?? ''}'
        : error.toString();

    final isUniqueViolation =
        raw.contains('23505') || raw.contains('duplicate key value');
    if (!isUniqueViolation) return null;

    String? code;
    if (raw.contains('user_info_university_id_unique_idx')) {
      code = 'university_id';
    } else if (raw.contains('user_info_email_unique_idx')) {
      code = 'email';
    } else if (raw.contains('user_info_full_name_unique_idx')) {
      code = 'name';
    }
    if (code == null) return null;

    return _conflictFor(
      code,
      firstName: firstName,
      lastName: lastName,
      idLabel: idLabel,
    ).error;
  }

  /// Pulls the readable message out of an edge-function failure.
  ///
  /// `functions.invoke` throws a [FunctionException] on any non-2xx response,
  /// and printing that object gives the admin
  /// `FunctionException(status: 400, details: {error: Duplicate: ...})`. The
  /// message the server actually wrote is in `details['error']`. Falls back to
  /// [fallback] when there is nothing usable, so a raw exception is never shown.
  static String describeEdgeFunctionError(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        return details['error'] as String;
      }
      if (details is String && details.trim().isNotEmpty) return details;
      return fallback;
    }
    // Some call sites `throw` the server's message string directly.
    if (error is String && error.trim().isNotEmpty) return error;
    if (error is SocketException) {
      return 'No internet connection. Please check your WiFi or mobile data.';
    }
    final duplicate = mapDatabaseError(error);
    if (duplicate != null) return duplicate;
    debugPrint('[IDENTITY] Unmapped edge function error: $error');
    return fallback;
  }

  static IdentityCheckResult _conflictFor(
    String code, {
    String? firstName,
    String? lastName,
    String idLabel = defaultIdLabel,
  }) {
    switch (code) {
      case 'university_id':
        return IdentityCheckResult.conflict(
          IdentityField.universityId,
          'This $idLabel is already registered to another account. '
              'Please check the number, or contact the SAO office.',
        );
      case 'email':
        return const IdentityCheckResult.conflict(
          IdentityField.email,
          'This email address is already registered to another account.',
        );
      case 'name':
        final full = '${clean(firstName)} ${clean(lastName)}'.trim();
        return IdentityCheckResult.conflict(
          IdentityField.name,
          full.isEmpty
              // Deliberately explicit that only the full name is blocked --
              // sharing a first or a last name is fine, and an admin seeing
              // this message needs to know which of the two it is.
              ? 'An account with that exact first and last name already exists.'
              : 'An account for "$full" already exists. A first name or a last '
                  'name may be shared, but not both. Add a middle initial or '
                  'suffix to tell the two people apart.',
        );
      default:
        return const IdentityCheckResult.ok();
    }
  }
}
