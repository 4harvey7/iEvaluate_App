// lib/core/services/profile_completion_service.dart
//
// Finds out whether the signed-in user's profile is missing the two fields
// every role is expected to have -- `user_info.university_id` and
// `user_info.address` -- and fills them in.
//
// Why they can be missing at all: self-registration always writes both, but
// accounts created by an SAO admin (admin-create-academic) never write an
// address, and older rows predate the ID being required. The post-login
// "Complete your information" dialog (profile_completion_gate.dart) uses this
// to ask for exactly what is absent and nothing else.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'identity_validator.dart';

/// Which of the two profile fields are still empty.
@immutable
class ProfileCompletionStatus {
  const ProfileCompletionStatus({
    required this.needsId,
    required this.needsAddress,
  });

  final bool needsId;
  final bool needsAddress;

  bool get isComplete => !needsId && !needsAddress;

  ProfileCompletionStatus copyWith({bool? needsId, bool? needsAddress}) =>
      ProfileCompletionStatus(
        needsId: needsId ?? this.needsId,
        needsAddress: needsAddress ?? this.needsAddress,
      );

  /// Reads a `user_info` row. Null, empty and whitespace-only all count as
  /// missing, since "  " is no more an address than null is.
  factory ProfileCompletionStatus.fromRow(Map<String, dynamic> row) {
    return ProfileCompletionStatus(
      needsId: isBlank(row['university_id']),
      needsAddress: isBlank(row['address']),
    );
  }

  static bool isBlank(Object? value) =>
      value == null || IdentityValidator.clean(value.toString()).isEmpty;
}

/// Outcome of [ProfileCompletionService.save].
///
/// [addressSaved] can be true on a failed save: when the ID is refused but the
/// address went through, the dialog drops the address field and asks only for
/// what is still missing, instead of making the user type it again.
@immutable
class ProfileCompletionResult {
  const ProfileCompletionResult.ok()
      : success = true,
        error = null,
        addressSaved = true;

  const ProfileCompletionResult.failed(this.error, {this.addressSaved = false})
      : success = false;

  final bool success;
  final String? error;
  final bool addressSaved;
}

class ProfileCompletionService {
  /// [client] is injectable so tests never touch a live Supabase. Resolved
  /// lazily, so a test fake that overrides every method needs no client at all.
  ProfileCompletionService({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;
  SupabaseClient get _supabase => _injectedClient ?? Supabase.instance.client;

  /// Maximum stored address length. Generous for a Philippine address
  /// (house / street / purok, barangay, municipality, province).
  static const int maxAddressLength = 200;

  /// Format rule for the address. Same requirement as registration -- both the
  /// street half and the barangay half must be present -- plus a length cap.
  static String? validateAddress(String street, String location) {
    if (IdentityValidator.clean(street).isEmpty) {
      return 'House number / street is required';
    }
    if (IdentityValidator.clean(location).isEmpty) {
      return 'Barangay is required';
    }
    return null;
  }

  /// What is missing for [userId], or null when it could not be determined.
  ///
  /// Null (not "complete") on failure so the caller can simply skip the
  /// prompt: a network hiccup must never block someone who just logged in.
  Future<ProfileCompletionStatus?> fetchStatus(String userId) async {
    try {
      final row = await _supabase
          .from('user_info')
          .select('university_id, address')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      return ProfileCompletionStatus.fromRow(row);
    } catch (e) {
      debugPrint('[PROFILE] Could not check profile completeness: $e');
      return null;
    }
  }

  /// Writes the missing fields. Pass only the ones the user was asked for.
  ///
  /// [universityId] goes through the same format rule and duplicate check as
  /// registration, so a value refused there cannot get in through here.
  Future<ProfileCompletionResult> save({
    required String userId,
    String? universityId,
    String? address,
    String idLabel = IdentityValidator.defaultIdLabel,
  }) async {
    final String? cleanId =
        universityId == null ? null : IdentityValidator.clean(universityId);
    final String? cleanAddress =
        address == null ? null : IdentityValidator.clean(address);

    if (cleanId == null && cleanAddress == null) {
      return const ProfileCompletionResult.ok();
    }

    if (cleanId != null) {
      final formatError =
          IdentityValidator.validateUniversityId(cleanId, label: idLabel);
      if (formatError != null) {
        return ProfileCompletionResult.failed(formatError);
      }
    }
    if (cleanAddress != null) {
      if (cleanAddress.isEmpty) {
        return const ProfileCompletionResult.failed('Address is required');
      }
      if (cleanAddress.length > maxAddressLength) {
        return const ProfileCompletionResult.failed(
          'Address is too long (max $maxAddressLength characters)',
        );
      }
    }

    try {
      if (cleanId != null) {
        // excludeUserId: this account, so it never collides with itself.
        final availability = await IdentityValidator.checkAvailability(
          client: _supabase,
          universityId: cleanId,
          excludeUserId: userId,
          idLabel: idLabel,
        );
        if (!availability.isAvailable) {
          return ProfileCompletionResult.failed(availability.error);
        }
      }

      await _update(userId, {
        'university_id': ?cleanId,
        'address': ?cleanAddress,
      });
      return const ProfileCompletionResult.ok();
    } catch (e) {
      debugPrint('[PROFILE] Save failed: $e');

      // trg_protect_user_info_fields refuses any university_id change from a
      // non-admin unless migration 20240130000027 (fill-once exception) is
      // applied. Save the address on its own so the user is not asked for it
      // again, and say plainly what is left.
      if (_isIdLocked(e)) {
        bool addressSaved = false;
        if (cleanAddress != null) {
          try {
            await _update(userId, {'address': cleanAddress});
            addressSaved = true;
          } catch (inner) {
            debugPrint('[PROFILE] Address-only save failed too: $inner');
          }
        }
        return ProfileCompletionResult.failed(
          '${addressSaved ? 'Your address was saved, but your' : 'Your'} '
          '$idLabel cannot be set from the app. Please ask the SAO office to '
          'add it for you.',
          addressSaved: addressSaved,
        );
      }

      final duplicate = IdentityValidator.mapDatabaseError(e, idLabel: idLabel);
      if (duplicate != null) return ProfileCompletionResult.failed(duplicate);

      if (e is SocketException || _isNetworkError(e.toString())) {
        return const ProfileCompletionResult.failed(
          'No internet connection. Please check your WiFi or mobile data.',
        );
      }
      return ProfileCompletionResult.failed(
        e is _NothingUpdated
            ? 'Your profile could not be updated. Please contact the SAO office.'
            : 'Could not save your information. Please try again.',
      );
    }
  }

  /// Updates the caller's own row and confirms a row was actually written.
  ///
  /// RLS turns a refused UPDATE into a silent zero-row success, so without the
  /// `.select()` a blocked save would close the dialog as if it had worked and
  /// the prompt would be back at the next login.
  Future<void> _update(String userId, Map<String, dynamic> values) async {
    final List<dynamic> rows = await _supabase
        .from('user_info')
        .update(values)
        .eq('id', userId)
        .select('id');
    if (rows.isEmpty) throw const _NothingUpdated();
  }

  static bool _isIdLocked(Object e) =>
      e.toString().contains('cannot modify your university ID');

  static bool _isNetworkError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('clientexception') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection timed out');
  }
}

class _NothingUpdated implements Exception {
  const _NothingUpdated();
  @override
  String toString() => 'user_info update matched no rows';
}
