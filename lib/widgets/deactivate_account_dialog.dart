// lib/widgets/deactivate_account_dialog.dart
//
// Self-service account deactivation, gated behind an emailed code.
//
// WHY A CODE
// Deactivating locks the person out until an SAO admin reactivates them. It was
// previously one tap of a red button behind one confirm dialog, which is not
// much of a barrier for an unlocked phone left on a desk, and nothing about it
// proved the person doing it could read the account's own email. The code makes
// the account owner prove they are the account owner.
//
// The check that matters happens in the delete-user edge function, not here.
// This dialog is the part the honest user sees.
//
// WHY ONE WIDGET
// Four settings screens -- instructor, dept head, gatherer, SAO admin -- each
// had a byte-identical copy of the old confirm dialog. Adding a code step to
// four copies means four places to fix the next time the wording changes, so
// they now all call this.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/auth_service.dart';
import '../theme/app_colors.dart';
import 'blocking_progress_overlay.dart';
import 'safe_button.dart';

/// Two-step deactivation modal:
///   1. explain what deactivating means, and email a code
///   2. verify the code, then deactivate
///
/// Resolves to `true` once the account has actually been deactivated and the
/// session cleared -- the caller should then send the user to the login screen.
/// Resolves to `null` if dismissed.
Future<bool?> showDeactivateAccountDialog(
  BuildContext context, {
  AuthService? authService,
}) {
  return showDialog<bool>(
    context: context,
    // Not dismissible by tapping outside: the second step holds a live code,
    // and losing it to a stray tap means waiting out the 60-second rate limit.
    barrierDismissible: false,
    builder: (_) => _DeactivateAccountDialog(authService: authService),
  );
}

enum _Step { warning, code }

/// Digits in the emailed code.
///
/// Fixed by send-admin-code, which generates `otpBuffer[0] % 900000 + 100000`
/// -- always six digits. This is NOT the same as the password-reset code, which
/// comes from Supabase Auth and is eight digits on this project. Reusing that
/// constant here would silently break auto-submit.
const int _codeLength = 6;

class _DeactivateAccountDialog extends StatefulWidget {
  const _DeactivateAccountDialog({this.authService});

  /// Injectable so the flow can be driven in tests without hitting the network.
  final AuthService? authService;

  @override
  State<_DeactivateAccountDialog> createState() =>
      _DeactivateAccountDialogState();
}

class _DeactivateAccountDialogState extends State<_DeactivateAccountDialog> {
  late final AuthService _authService = widget.authService ?? AuthService();

  final _codeController = TextEditingController();

  _Step _step = _Step.warning;
  bool _busy = false;
  String? _error;

  /// The code we last submitted. Guards the auto-submit on the sixth digit from
  /// firing twice for the same value while the first attempt is still in
  /// flight.
  String? _attemptedCode;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _busy = false;
    });
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await _authService.sendDeactivationCode();
    if (!mounted) return;

    if (!result.success) {
      // Keeps the server's wording -- the rate-limit message names how many
      // seconds are left, which the user needs.
      _fail(result.error ?? 'Could not send the code. Please try again.');
      return;
    }

    setState(() {
      _step = _Step.code;
      _busy = false;
      _attemptedCode = null;
      _codeController.clear();
    });
  }

  Future<void> _resendCode() async {
    _codeController.clear();
    _attemptedCode = null;
    await _sendCode();
  }

  Future<void> _confirm() async {
    final code = _codeController.text.trim();
    if (code.length != _codeLength) {
      _fail('Enter the $_codeLength-digit code from your email.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _attemptedCode = code;
    });

    // Blocking overlay over the dialog: deactivation bans the account in Auth
    // and signs the session out, and a tap that dismissed the dialog midway
    // would leave the user staring at a screen they no longer have access to.
    showBlockingProgressOverlay(
      context,
      title: 'Deactivating account…',
      subtitle: 'Signing you out and locking the account.',
    );

    final result = await _authService.deleteAccount(verificationCode: code);

    if (mounted) dismissBlockingProgressOverlay(context);
    if (!mounted) return;

    if (!result.success) {
      // Wrong / expired / out of attempts each need different action from the
      // user, so the server's own sentence is shown rather than one generic
      // failure.
      _fail(result.error ?? 'Deactivation failed. Please try again.');
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Deactivate Account?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step == _Step.warning) ..._warningBody() else ..._codeBody(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: _actions(),
    );
  }

  List<Widget> _warningBody() {
    return [
      const Text(
        'Your account will be deactivated and you will no longer be able to '
        'access it unless you ask the SAO Admin to reactivate it.',
        style: TextStyle(fontSize: 14, height: 1.4),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.mark_email_read_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'We will email a $_codeLength-digit code to confirm it is you.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _codeBody() {
    return [
      Text(
        'Enter the $_codeLength-digit code we emailed you.',
        style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        enabled: !_busy,
        autofocus: true,
        maxLength: _codeLength,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          fontSize: 24,
          letterSpacing: 8,
          fontWeight: FontWeight.bold,
        ),
        decoration: const InputDecoration(
          hintText: '000000',
          counterText: '',
          prefixIcon: Icon(Icons.dialpad_rounded, color: AppColors.primary),
        ),
        onChanged: (v) {
          // Clear a stale error the moment they start retyping.
          if (_error != null) setState(() => _error = null);
          // Submit on the last digit so there is no second tap to find, but
          // never resubmit a value already in flight.
          if (v.length == _codeLength && !_busy && v != _attemptedCode) {
            _confirm();
          }
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : _resendCode,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Resend code'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
          ),
        ),
      ),
    ];
  }

  List<Widget> _actions() {
    return [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text(
          'Cancel',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
      SafeElevatedButton(
        onPressed: _busy
            ? null
            : (_step == _Step.warning ? _sendCode : _confirm),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          _step == _Step.warning ? 'Send Code' : 'Deactivate My Account',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ];
  }
}
