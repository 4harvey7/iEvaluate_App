// lib/core/services/account_activation_service.dart
//
// Decides whether a pending account can be approved with one tap, or has to be
// ACTIVATED first -- and does the activation.
//
// An account needs activation when approving it as-is would hand out a login
// nobody can use: its email is blank or a placeholder. Instructors added during
// batch scanning (the website's "add instructor" step) get
// `placeholder-<uuid>@ievaluate.internal` and no password anyone knows. Same
// idea as the website's /activate page.
//
// The admin supplies ONLY the real email. A missing university_id / address is
// not the admin's to fill: the person is asked for it by the mandatory
// post-login "Complete your information" dialog (profile_completion_gate.dart),
// so an account with a real email but no ID / address approves in one tap.
//
// Activation runs through the admin-activate-account edge function, which needs
// the service role: trg_protect_user_info_fields refuses email changes from the
// app, and another user's Auth email can only be changed with the admin API.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'identity_validator.dart';

/// Outcome of [AccountActivationService.activate].
@immutable
class AccountActivationResult {
  const AccountActivationResult.ok({
    required this.email,
    this.passwordSetupRequired = false,
    this.emailSent = true,
  })  : success = true,
        alreadyActivated = false,
        error = null;

  const AccountActivationResult.failed(this.error, {this.alreadyActivated = false})
      : success = false,
        email = null,
        passwordSetupRequired = false,
        emailSent = false;

  final bool success;
  final String? error;

  /// Somebody activated or changed this account first. The list is stale.
  final bool alreadyActivated;

  /// The login email the account ended up with.
  final String? email;

  /// The person has never had a password and was told how to set one.
  final bool passwordSetupRequired;

  /// The activation email reached the mail provider. False does not mean the
  /// activation failed -- only that the admin should pass the steps on.
  final bool emailSent;
}

class AccountActivationService {
  /// [client] is injectable so tests never touch a live Supabase. Resolved
  /// lazily, so a fake that overrides [invokeActivate] needs no client at all.
  AccountActivationService({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;
  SupabaseClient get _supabase => _injectedClient ?? Supabase.instance.client;

  static const String functionName = 'admin-activate-account';

  /// Domain the website gives placeholder logins.
  static const String placeholderDomain = 'ievaluate.internal';

  /// Prefix the edge function uses for "already activated / changed meanwhile".
  static const String alreadyActivatedPrefix = 'Already activated';

  /// A login nobody can receive mail at. Must agree with isPlaceholderEmail in
  /// supabase/functions/admin-activate-account/index.ts.
  static bool isPlaceholderEmail(String? email) {
    final cleaned = IdentityValidator.cleanEmail(email);
    if (cleaned.isEmpty) return true;
    final at = cleaned.indexOf('@');
    final local = at < 0 ? cleaned : cleaned.substring(0, at);
    final domain = at < 0 ? '' : cleaned.substring(at + 1);
    return local.startsWith('placeholder-') || domain == placeholderDomain;
  }

  /// Whether pressing Approve on [row] must open the activation dialog instead
  /// of approving straight away.
  ///
  /// [row] is a `user_info` row (email, optionally is_placeholder from the
  /// website's migration). Only a blank / placeholder login qualifies; a missing
  /// ID or address is collected from the person after they sign in.
  static bool requiresActivation(Map<String, dynamic> row) =>
      row['is_placeholder'] == true ||
      isPlaceholderEmail(row['email']?.toString());

  /// Email rule for the dialog: the normal format rule, plus "not a placeholder".
  static String? validateEmail(String? value) {
    final formatError = IdentityValidator.validateEmail(value);
    if (formatError != null) return formatError;
    if (isPlaceholderEmail(value)) {
      return "Enter the person's real email address, not the placeholder";
    }
    return null;
  }

  /// Activates [userId] with the person's real [email], then approves it.
  Future<AccountActivationResult> activate({
    required String userId,
    required String email,
  }) async {
    final cleanEmail = IdentityValidator.cleanEmail(email);
    final emailError = validateEmail(cleanEmail);
    if (emailError != null) return AccountActivationResult.failed(emailError);

    try {
      final data = await invokeActivate({
        'targetUserId': userId,
        'email': cleanEmail,
      });
      final map = data is Map ? data : const {};
      return AccountActivationResult.ok(
        email: (map['email'] ?? cleanEmail).toString(),
        passwordSetupRequired: map['passwordSetupRequired'] == true,
        emailSent: map['emailSent'] != false,
      );
    } catch (e) {
      debugPrint('[ACTIVATION] Failed: $e');
      final message = describeError(e);
      return AccountActivationResult.failed(
        message,
        alreadyActivated: message.startsWith(alreadyActivatedPrefix),
      );
    }
  }

  /// Calls the edge function and returns its JSON body. Overridden in tests.
  @visibleForTesting
  Future<dynamic> invokeActivate(Map<String, dynamic> body) async {
    final response = await _supabase.functions.invoke(functionName, body: body);
    return response.data;
  }

  /// Server message -> sentence for the admin.
  ///
  /// The function writes 'Invalid input: ...' and 'Duplicate: ...'; the prefix
  /// is dropped from the first, and the second is reworded for this dialog.
  @visibleForTesting
  static String describeError(Object e) {
    if (e is SocketException) {
      return 'No internet connection. Please check your WiFi or mobile data.';
    }
    if (e is FunctionException && e.status == 404) {
      return 'Account activation is not set up on the server yet. '
          'Deploy the $functionName function and try again.';
    }
    final message = IdentityValidator.describeEdgeFunctionError(
      e,
      fallback: 'Could not activate the account. Please try again.',
    );
    if (message.startsWith('Duplicate:') &&
        message.toLowerCase().contains('email')) {
      return 'This email address already belongs to another account. '
          'Use a different address.';
    }
    if (message.startsWith('Invalid input: ')) {
      final rest = message.substring('Invalid input: '.length);
      return rest.isEmpty ? message : rest[0].toUpperCase() + rest.substring(1);
    }
    return message;
  }
}
