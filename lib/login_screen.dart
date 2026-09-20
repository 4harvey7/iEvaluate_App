// lib/login_screen.dart
// this is the login screen, the front door of the app
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'core/config/agreements.dart';
import 'core/services/auth_service.dart';
import 'main.dart' show screenForRole;
import 'signup_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_text_styles.dart';
import 'widgets/apple_ui.dart';
import 'widgets/forgot_password_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // auth service handle all the login logic, we just call it and pray
  final _authService = AuthService();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword =
      true; // hide the password by default, dili ta show-off
  bool _isLoading = false;
  bool _hasAcceptedAgreements = false;
  String?
  _errorMessage; // null means no error, something means user did something wrong

  // rate limiting to stop people from guessing password all day, 5 tries then lockout
  int _failedLoginAttempts = 0;
  DateTime? _lastFailedAttempt;
  static const _maxAttempts = 5;
  static const _lockoutDuration = Duration(
    minutes: 5,
  ); // 5 minutes timeout, take a break

  @override
  void dispose() {
    // clean up everything when this screen is gone, very important so we dont leak memory
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // grab what the user typed, trim the spaces so they dont fail because of accident whitespace
    final input = _idController.text.trim();
    final password = _passwordController.text;

    // if either field is empty we yell at the user nicely before even trying
    if (input.isEmpty || password.isEmpty) {
      setState(
        () => _errorMessage = 'Please enter your ID/email and password.',
      );
      return;
    }

    if (!_hasAcceptedAgreements) {
      setState(
        () => _errorMessage = 'Please agree to the NDA and DPA to log in.',
      );
      return;
    }

    // check if user already fail too many times and is currently locked out
    if (_failedLoginAttempts >= _maxAttempts && _lastFailedAttempt != null) {
      final elapsed = DateTime.now().difference(_lastFailedAttempt!);
      if (elapsed < _lockoutDuration) {
        // calculate how much time is left in the lockout so user know how long to wait
        final remaining = _lockoutDuration - elapsed;
        final mins = remaining.inMinutes;
        final secs = remaining.inSeconds % 60;
        setState(
          () => _errorMessage =
              'Too many failed attempts. Please wait ${mins}m ${secs}s before trying again.',
        );
        return;
      } else {
        // lockout already expired so we reset the counter, fresh start for the user
        _failedLoginAttempts = 0;
        _lastFailedAttempt = null;
      }
    }

    // show loading spinner and clear any old error message before we send the request
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // this is where we actually call the auth service to do the login, pray lang
    final result = await _authService.signIn(
      idOrEmail: input,
      password: password,
    );

    if (!mounted) {
      return; // safety check in case screen was closed while loading
    }
    setState(() => _isLoading = false);

    if (result.success) {
      // login success, reset the failed counter and send user to their dashboard
      _failedLoginAttempts = 0;
      _lastFailedAttempt = null;
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => screenForRole(result.role!, result.userId!),
        ),
      );
    } else {
      // login fail, increment the failed counter and show the error message
      _failedLoginAttempts++;
      _lastFailedAttempt = DateTime.now();
      setState(() => _errorMessage = result.error);
    }
  }

  void _showNdaDpaModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'NDA & DPA Agreements',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              MarkdownBody(data: Agreements.ndaText),
              Divider(height: 32, thickness: 1),
              MarkdownBody(data: Agreements.dpaText),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Forgot password — opens the in-app reset modal: email -> emailed code
  // -> new password. No reset link / browser round-trip involved.
  Future<void> _handleForgotPassword() async {
    final changed = await showForgotPasswordDialog(context);
    if (!mounted || changed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Password updated successfully! Please log in with your new password.',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            top: 115,
            left: -95,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.10),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppleEntrance(
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: AppColors.borderHairline,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x120B2540),
                                    blurRadius: 18,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Image.asset('assets/images/CTU_logo.png'),
                            ),
                            const SizedBox(width: 13),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CEBU TECHNOLOGICAL UNIVERSITY',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  'iEvaluate',
                                  style: AppTextStyles.titleLarge,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 38),
                      AppleEntrance(
                        delay: const Duration(milliseconds: 60),
                        child: Text(
                          'iEvaluate Portal',
                          style: AppTextStyles.displayLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppleEntrance(
                        delay: const Duration(milliseconds: 100),
                        child: Text(
                          'Secure access to academic evaluation tools.',
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppleEntrance(
                        delay: const Duration(milliseconds: 140),
                        child: AppleGlass(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              _buildTextField(
                                controller: _idController,
                                hintText:
                                    'University ID or Institutional Email',
                                icon: Icons.person_outline_rounded,
                              ),
                              const SizedBox(height: 14),
                              _buildTextField(
                                controller: _passwordController,
                                hintText: 'Password',
                                icon: Icons.lock_outline_rounded,
                                isPassword: true,
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _handleForgotPassword,
                                  child: const Text('Forgot Password?'),
                                ),
                              ),
                              Material(
                                color: AppColors.surfaceElevated,
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                    color: AppColors.borderHairline,
                                  ),
                                ),
                                child: CheckboxListTile(
                                  title: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'I agree to the NDA and DPA',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.info_outline_rounded,
                                          color: AppColors.primary,
                                        ),
                                        onPressed: _showNdaDpaModal,
                                        tooltip: 'Read agreements',
                                      ),
                                    ],
                                  ),
                                  value: _hasAcceptedAgreements,
                                  onChanged: (value) => setState(
                                    () =>
                                        _hasAcceptedAgreements = value ?? false,
                                  ),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  contentPadding: const EdgeInsets.only(
                                    left: 6,
                                    right: 2,
                                  ),
                                ),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 14),
                                _buildErrorMessage(),
                              ],
                              const SizedBox(height: 18),
                              ApplePressable(
                                onTap: _isLoading ? null : _handleLogin,
                                semanticLabel: 'Sign in',
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: double.infinity,
                                  height: 54,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _isLoading
                                        ? AppColors.primary.withValues(
                                            alpha: 0.65,
                                          )
                                        : AppColors.primary,
                                    borderRadius: BorderRadius.circular(15),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x2E0066CC),
                                        blurRadius: 18,
                                        offset: Offset(0, 7),
                                      ),
                                    ],
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.4,
                                          ),
                                        )
                                      : Text(
                                          'Sign In',
                                          style: AppTextStyles.titleMedium
                                              .copyWith(
                                                color: AppColors.textInverted,
                                              ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Need an account?',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SignUpScreen(),
                                ),
                              ),
                              child: const Text('Register'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    final message = _errorMessage!;
    final isNoInternet =
        message.toLowerCase().contains('no internet') ||
        message.toLowerCase().contains('wifi') ||
        message.toLowerCase().contains('mobile data');
    final icon = isNoInternet
        ? Icons.wifi_off_rounded
        : Icons.error_outline_rounded;
    final color = isNoInternet ? AppColors.warning : AppColors.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  // reusable text field builder so we dont repeat the same decoration code twice
  // one for the ID field, one for password, same look but different behavior
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      enabled: !_isLoading,
      style: AppTextStyles.bodyMedium,
      onSubmitted: isPassword ? (_) => _handleLogin() : null,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textTertiary,
        ),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 21),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 17,
          horizontal: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.borderHairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.borderHairline),
        ),
      ),
    );
  }
}
