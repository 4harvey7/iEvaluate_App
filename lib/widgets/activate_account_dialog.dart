// lib/widgets/activate_account_dialog.dart
//
// "Activate account" -- opened by the SAO admin's Approve button instead of a
// one-tap approval when the account has no real login email yet (a placeholder
// from batch scanning; AccountActivationService.requiresActivation).
//
// The admin types ONLY the person's real email and confirms. The account is
// given that email, approved, and emailed how to set a password. Same account
// id throughout, so batches and results stay theirs. A missing ID / address is
// asked of the person by the post-login "Complete your information" dialog.
import 'package:flutter/material.dart';

import '../core/services/account_activation_service.dart';
import '../theme/app_colors.dart';
import 'apple_ui.dart';
import 'controller_disposer.dart';

/// Shows the dialog. Resolves to true when the account was activated, or when
/// it turned out to be activated already (either way the caller's list is
/// stale and should be refreshed); false when the admin cancelled.
Future<bool> showActivateAccountDialog(
  BuildContext context, {
  required String userId,
  required String fullName,
  String? subtitle,
  AccountActivationService? service,
}) async {
  // Owned by ControllerDisposer: showDialog completes before the exit
  // animation, while the TextField is still mounted.
  final emailController = TextEditingController();

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ControllerDisposer(
      controllers: [emailController],
      child: ActivateAccountDialog(
        userId: userId,
        fullName: fullName,
        subtitle: subtitle,
        service: service ?? AccountActivationService(),
        emailController: emailController,
      ),
    ),
  );
  return result ?? false;
}

class ActivateAccountDialog extends StatefulWidget {
  const ActivateAccountDialog({
    super.key,
    required this.userId,
    required this.fullName,
    required this.service,
    required this.emailController,
    this.subtitle,
  });

  final String userId;
  final String fullName;
  final String? subtitle;
  final AccountActivationService service;
  final TextEditingController emailController;

  @override
  State<ActivateAccountDialog> createState() => _ActivateAccountDialogState();
}

class _ActivateAccountDialogState extends State<ActivateAccountDialog> {
  bool _saving = false;
  bool _submitted = false; // "required" errors only after a press
  String? _errorMessage;
  AccountActivationResult? _done; // non-null = success view
  bool _alreadyActivated = false;

  String? get _emailError {
    final text = widget.emailController.text;
    if (!_submitted && text.trim().isEmpty) return null;
    return AccountActivationService.validateEmail(text);
  }

  Future<void> _activate() async {
    if (_saving || _alreadyActivated) return; // double tap / locked
    setState(() {
      _submitted = true;
      _errorMessage = null;
    });

    final String? formatError = _emailError;
    if (formatError != null) {
      setState(() => _errorMessage = formatError);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final result = await widget.service.activate(
      userId: widget.userId,
      email: widget.emailController.text,
    );
    if (!mounted) return;

    setState(() {
      _saving = false;
      if (result.success) {
        _done = result;
      } else {
        _errorMessage = result.error;
        _alreadyActivated = result.alreadyActivated;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    return PopScope(
      // No back-button dismissal mid-request.
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            AppleIconBadge(
              icon: done != null
                  ? Icons.verified_user_outlined
                  : Icons.how_to_reg_outlined,
              color: done != null ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                done != null ? 'Account activated' : 'Activate account',
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
          child: done != null ? _buildSuccess(done) : _buildForm(),
        ),
        actions: [done != null ? _buildDoneAction() : _buildFormActions()],
      ),
    );
  }

  // ── Form ──────────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPersonBox(),
        const SizedBox(height: 14),
        const Text(
          'This account was added without a real login, so it cannot be '
          'approved as is. Check who they are in person first, then enter '
          'their real email -- they will log in with it, and their batches and '
          'results stay with them. They will be asked for any missing ID or '
          'address after they sign in.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        _buildEmailInput(),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          _buildBanner(
            _errorMessage!,
            colour: _alreadyActivated ? AppColors.warning : AppColors.error,
            icon: _alreadyActivated ? Icons.info_outline : Icons.error_outline,
          ),
        ],
      ],
    );
  }

  Widget _buildPersonBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.fullName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          if (widget.subtitle != null && widget.subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              widget.subtitle!,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormActions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            key: const Key('activateAccount.cancel'),
            // Closing after "already activated" still asks for a refresh.
            onPressed: _saving
                ? null
                : () => Navigator.of(context).pop(_alreadyActivated),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(_alreadyActivated ? 'Close' : 'Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            key: const Key('activateAccount.confirm'),
            onPressed: _saving || _alreadyActivated ? null : _activate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                : const Text(
                    'Activate & Approve',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Success ───────────────────────────────────────────────────────────────

  Widget _buildSuccess(AccountActivationResult done) {
    final email = done.email ?? '';
    final steps = done.passwordSetupRequired
        ? 'To set a password they open iEvaluate, tap "Forgot Password?", '
            'enter $email and type the code that is emailed to them.'
        : 'They can now log in with $email.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.fullName} is approved and their login email is $email.',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          done.emailSent
              ? 'An email saying the SAO admin activated their account was '
                  'sent to $email. $steps'
              : steps,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        if (!done.emailSent) ...[
          const SizedBox(height: 12),
          _buildBanner(
            'The email to $email could not be sent. Please give them the '
            'steps above in person.',
            colour: AppColors.warning,
            icon: Icons.mark_email_unread_outlined,
          ),
        ],
      ],
    );
  }

  Widget _buildDoneAction() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        key: const Key('activateAccount.done'),
        onPressed: () => Navigator.of(context).pop(true),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: const Text(
          'Done',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

  Widget _buildBanner(String message, {required Color colour, required IconData icon}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colour, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: colour, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// Same field look as the registration screen and CompleteProfileDialog.
  Widget _buildEmailInput() {
    OutlineInputBorder border(Color colour, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colour, width: width),
        );

    return TextField(
      key: const Key('activateAccount.email'),
      controller: widget.emailController,
      enabled: !_saving && !_alreadyActivated,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.email],
      onChanged: (_) => setState(() {}), // refresh live error text
      onSubmitted: (_) => _activate(),
      decoration: InputDecoration(
        hintText: "Person's real email",
        errorText: _emailError,
        errorMaxLines: 3,
        prefixIcon:
            const Icon(Icons.email_outlined, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        enabledBorder: border(AppColors.borderHairline),
        focusedBorder: border(AppColors.primary, 1.5),
        errorBorder: border(AppColors.error),
        focusedErrorBorder: border(AppColors.error, 1.5),
        disabledBorder: border(AppColors.borderHairline),
      ),
    );
  }
}
