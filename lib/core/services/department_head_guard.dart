// lib/core/services/department_head_guard.dart
//
// One department head per department, client side.
//
// The guarantee is the trigger `department_table_one_head` from migration
// 20240130000016. This file exists so the screens can say so in a sentence --
// before an account is created, before an OTP is emailed, and while the
// dropdown is still open -- rather than surfacing a rejected write.
//
// Three copies of the role rule exist and must agree:
//   * public.is_department_head_role(bigint)  -- migration 20240130000016
//   * isDepartmentHeadRole below
//   * isDepartmentHeadRole -- supabase/functions/_shared/department_head_guard.ts
// The database one is authoritative; it backs the trigger.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Raw role strings that land on the department-head dashboard.
///
/// DEAN is in here on purpose. [roleFromString] in role_nav_config routes DEAN
/// and DEPARTMENT_HEAD to the same [UserRole.deptHead], so two of them over one
/// department is exactly the collision this rule prevents -- the app could not
/// tell which of the two owns the faculty roster.
const Set<String> kDepartmentHeadRoles = <String>{
  'DEPARTMENT_HEAD',
  'DEPARTMENT-HEAD',
  'DEPARTMENT HEAD',
  'DEAN',
};

/// Is this raw role string a department-head role?
bool isDepartmentHeadRole(String? raw) {
  if (raw == null) return false;
  final normalised = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '-');
  return normalised == 'DEPARTMENT-HEAD' || normalised == 'DEAN';
}

/// Pre-flight checks and wording for the one-head-per-department rule.
class DepartmentHeadGuard {
  const DepartmentHeadGuard._();

  /// The sentence every screen shows when the chair is taken.
  ///
  /// [headName] is omitted where the caller has no business naming the sitting
  /// head -- the registration screen, where the applicant is not staff yet.
  static String conflictMessage({String? headName, String? departmentName}) {
    final where = (departmentName != null && departmentName.trim().isNotEmpty)
        ? departmentName.trim()
        : 'that department';
    if (headName != null && headName.trim().isNotEmpty) {
      return '$headName is already the department head of $where. '
          'A department can only have one head — change that person\'s role '
          'first, or choose a different department.';
    }
    return 'A department head is already assigned to $where. '
        'A department can only have one head, so this role is not available '
        'for it. Pick another department, or contact the SAO office.';
  }

  /// Does [departmentId] already have a head?
  ///
  /// Calls the `department_has_head` RPC rather than reading department_table
  /// directly: the registration screen asks this while nobody is signed in,
  /// and the RPC is SECURITY DEFINER and hands back a boolean instead of staff
  /// rows.
  ///
  /// [excludeUserId] is the account being edited, so the sitting head does not
  /// block their own save.
  ///
  /// Returns false if the check itself cannot be reached. It is a pre-flight
  /// courtesy, not the guarantee -- the trigger still rejects the write and
  /// [describeConflictError] turns that into the same message. Blocking every
  /// role change because one RPC timed out would be the worse failure.
  static Future<bool> departmentHasHead({
    required SupabaseClient client,
    required Object departmentId,
    String? excludeUserId,
  }) async {
    try {
      final result = await client.rpc(
        'department_has_head',
        params: {
          'p_department_id': departmentId is int
              ? departmentId
              : int.tryParse(departmentId.toString()),
          'p_exclude_user_id': excludeUserId,
        },
      );
      return result == true;
    } on SocketException {
      debugPrint('[DEPT_HEAD] Vacancy check skipped: no connection.');
      return false;
    } catch (e) {
      // Most likely migration 20240130000016 has not been applied yet, so the
      // function does not exist. Loud in debug, silent for the user.
      debugPrint('[DEPT_HEAD] Vacancy check unavailable: $e');
      return false;
    }
  }

  /// Recognises the head conflict in an error raised by the database or
  /// returned by an edge function, and hands back the message to show.
  ///
  /// Both sources start with the same words: the trigger raises
  /// "Department head already assigned: ..." and the edge functions list that
  /// prefix among the messages they pass through untouched.
  static String? describeConflictError(Object error) {
    final message = error is PostgrestException
        ? error.message
        : error.toString();
    final marker = message.indexOf('Department head already assigned');
    if (marker == -1) return null;
    // Trim the leading marker so the sentence reads as prose in a dialog.
    return message.substring(marker).replaceFirst(
          RegExp(r'^Department head already assigned:\s*'),
          '',
        );
  }
}
