// lib/widgets/forgot_password_dialog.dart
// In-app password reset. Replaces the old "click the link in your email" flow:
// the user never leaves the app, they just type the code they were emailed.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'apple_ui.dart';
import 'safe_button.dart';

/// Three-step password reset modal:
///   1. collect the email and send a one-time code to it
///   2. verify the code the user received
///   3. set the new password, confirmed twice
///
/// Resolves to `true` once the password has actually been changed, otherwise
/// `null` (dismissed). The caller is responsible for telling the user to sign
/// in again — this dialog clears the recovery session before it closes.
Future<bool?> showForgotPasswordDialog(
  BuildContext context, {
  AuthService? authService,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ForgotPasswordDialog(authService: authService),
  );
}

enum _ResetStep { email, code, password }

/// How many digits the emailed code has.
///
/// This MUST match the Supabase project setting:
///   Authentication -> Sign In / Providers -> Email -> Email OTP Length
/// Supabase allows 6-10; the default is 6 but this project is set to 8. Every
/// label, the max length and the auto-submit below are all driven from here, so
/// changing that setting only means changing this one number.
const int _codeLength = 8;

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({this.authService});

  /// Injectable so the flow can be driven in tests without hitting the network.
  final AuthService? authService;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final AuthService _authService = widget.authService ?? AuthService();

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _ResetStep _step = _ResetStep.email;
  bool _busy = false;
  String? _error;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// The address the code was actually sent to — kept so the verify call and
  /// the "resend" action cannot drift from what the user typed in step 1.
  String _sentToEmail = '';

  /// The last code we already sent to the server. Codes are single-use, so
  /// auto-submitting the same digits twice would spend the code on the first
  /// call and then report the second as invalid. Tapping Verify still retries
  /// deliberately (useful when the first attempt died on a flaky network).
  String? _attemptedCode;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ── Password rules — same set the signup screen enforces ──────────────────
  bool get _hasLength => _passwordController.text.length >= 8;
  bool get _hasUpper => _passwordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber => _passwordController.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecial =>
      _passwordController.text.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
  bool get _passwordValid =>
      _hasLength && _hasUpper && _hasNumber && _hasSpecial;

  void _fail(String message) {
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  // ── Step 1: email the code ───────────────────────────────────────────────
  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _fail('Please enter a valid email address.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await _authService.sendPasswordResetCode(email);
    if (!mounted) return;

    if (!result.success) {
      _fail(result.error ?? 'Could not send the code. Please try again.');
      return;
    }

    setState(() {
      _busy = false;
      _sentToEmail = email;
      _step = _ResetStep.code;
      _codeController.clear();
    });
  }

  // ── Step 2: verify the code ──────────────────────────────────────────────
  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length < _codeLength) {
      _fail('Enter the $_codeLength-digit code from your email.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    _attemptedCode = code;
    final result = await _authService.verifyPasswordResetCode(
      email: _sentToEmail,
      code: code,
    );
    if (!mounted) return;

    if (!result.success) {
      _fail(result.error ?? 'Incorrect code. Please try again.');
      return;
    }

    setState(() {
      _busy = false;
      _step = _ResetStep.password;
    });
  }

  /// Sends a fresh code without leaving step 2.
  Future<void> _resendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await _authService.sendPasswordResetCode(_sentToEmail);
    if (!mounted) return;

    if (!result.success) {
      _fail(result.error ?? 'Could not resend the code. Please try again.');
      return;
    }

    setState(() {
      _busy = false;
      _codeController.clear();
      _attemptedCode = null;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New code sent — use the newest email, the older code '
            'no longer works.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  // ── Step 3: set the new password ─────────────────────────────────────────
  Future<void> _updatePassword() async {
    final newPassword = _passwordController.text;
    final confirm = _confirmController.text;

    if (!_passwordValid) {
      _fail(
        'Password must be at least 8 characters and include an uppercase '
        'letter, a number, and a special character.',
      );
      return;
    }
    if (newPassword != confirm) {
      _fail('The two passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await _authService.updatePassword(newPassword);
    if (!mounted) return;

    if (!result.success) {
      _fail(result.error ?? 'Password update failed. Please try again.');
      return;
    }

    // Drop the recovery session so the next sign-in uses the new password.
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // ── Chrome ───────────────────────────────────────────────────────────────
  ({IconData icon, String title, String blurb}) get _chrome {
    switch (_step) {
      case _ResetStep.email:
        return (
          icon: Icons.mark_email_read_outlined,
          title: 'Reset Password',
          blurb:
              'Enter your institutional email. We’ll send a '
              '$_codeLength-digit code to it.',
        );
      case _ResetStep.code:
        return (
          icon: Icons.pin_outlined,
          title: 'Enter Code',
          blurb:
              'We sent a $_codeLength-digit code to $_sentToEmail. Enter it below.',
        );
      case _ResetStep.password:
        return (
          icon: Icons.lock_reset_rounded,
          title: 'Set New Password',
          blurb: 'Code verified. Choose a new password for your account.',
        );
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
    String? counterText,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
      suffixIcon: suffix,
      counterText: counterText,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _stepDots() {
    const total = _ResetStep.values;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final s in total) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: s == _step ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: s.index <= _step.index
                  ? AppColors.primary
                  : AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          if (s != total.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _rule(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 15,
            color: met ? AppColors.success : AppColors.textTertiary,
          ),
          const SizedBox(width: 7),
          // Expanded so a long rule wraps instead of overflowing the dialog on
          // narrow phones.
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: met ? AppColors.success : AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case _ResetStep.email:
        return TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _sendCode(),
          decoration: _fieldDecoration(
            label: 'Email',
            icon: Icons.alternate_email_rounded,
          ),
        );

      case _ResetStep.code:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              enabled: !_busy,
              maxLength: _codeLength,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              // Tracking is scaled down as the code gets longer so a 10-digit
              // code still fits inside the dialog on a small phone.
              style: AppTextStyles.titleLarge.copyWith(
                letterSpacing: _codeLength >= 8 ? 4 : 8,
              ),
              textInputAction: TextInputAction.done,
              onChanged: (v) {
                // Clear a stale error as soon as they start retyping.
                if (_error != null) setState(() => _error = null);
                if (v.length == _codeLength && !_busy && v != _attemptedCode) {
                  _verifyCode();
                }
              },
              decoration: _fieldDecoration(
                label: '$_codeLength-digit code',
                icon: Icons.dialpad_rounded,
                counterText: '',
              ),
            ),
            const SizedBox(height: 4),
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
          ],
        );

      case _ResetStep.password:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              enabled: !_busy,
              onChanged: (_) => setState(() {}), // refresh the rule checklist
              decoration: _fieldDecoration(
                label: 'New Password',
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _busy ? null : _updatePassword(),
              decoration: _fieldDecoration(
                label: 'Confirm Password',
                icon: Icons.lock_person_outlined,
                suffix: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _rule('At least 8 characters', _hasLength),
            _rule('One uppercase letter', _hasUpper),
            _rule('One number', _hasNumber),
            _rule('One special character', _hasSpecial),
            _rule(
              'Both passwords match',
              _confirmController.text.isNotEmpty &&
                  _confirmController.text == _passwordController.text,
            ),
          ],
        );
    }
  }

  List<Widget> _actions() {
    switch (_step) {
      case _ResetStep.email:
        return [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          SafeElevatedButton(
            onPressed: _busy ? null : _sendCode,
            child: const Text('Send Code'),
          ),
        ];

      case _ResetStep.code:
        return [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _step = _ResetStep.email;
                    _attemptedCode = null;
                    _error = null;
                  }),
            child: const Text(
              'Back',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          SafeElevatedButton(
            onPressed: _busy ? null : _verifyCode,
            child: const Text('Verify Code'),
          ),
        ];

      case _ResetStep.password:
        return [
          SafeElevatedButton(
            onPressed: _busy ? null : _updatePassword,
            child: const Text('Update Password'),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = _chrome;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          AppleIconBadge(icon: chrome.icon),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              chrome.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stepDots(),
            const SizedBox(height: 16),
            Text(
              chrome.blurb,
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 18),
            _body(),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 17,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: _actions(),
    );
  }
}
