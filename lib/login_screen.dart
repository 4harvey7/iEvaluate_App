// lib/login_screen.dart
// this is the login screen, the front door of the app
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/agreements.dart';
import 'core/services/auth_service.dart';
import 'main.dart' show screenForRole;
import 'signup_screen.dart';
import 'theme/app_colors.dart';
import 'widgets/safe_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // auth service handle all the login logic, we just call it and pray
  final _authService = AuthService();
  final TextEditingController _idController       = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true; // hide the password by default, dili ta show-off
  bool _isLoading       = false;
  bool _hasAcceptedAgreements = false;
  String? _errorMessage; // null means no error, something means user did something wrong
  late final StreamSubscription<AuthState> _authSubscription;

  // rate limiting to stop people from guessing password all day, 5 tries then lockout
  int _failedLoginAttempts = 0;
  DateTime? _lastFailedAttempt;
  static const _maxAttempts = 5;
  static const _lockoutDuration = Duration(minutes: 5); // 5 minutes timeout, take a break

  @override
  void initState() {
    super.initState();
    // we listen to auth state changes here so we know when user click the password reset link
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      // if the event is password recovery, we show the update password dialog immediately
      if (event == AuthChangeEvent.passwordRecovery) {
        _showUpdatePasswordDialog();
      }
    });
  }

  @override
  void dispose() {
    // clean up everything when this screen is gone, very important so we dont leak memory
    _authSubscription.cancel();
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // grab what the user typed, trim the spaces so they dont fail because of accident whitespace
    final input    = _idController.text.trim();
    final password = _passwordController.text;

    // if either field is empty we yell at the user nicely before even trying
    if (input.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your ID/email and password.');
      return;
    }

    if (!_hasAcceptedAgreements) {
      setState(() => _errorMessage = 'Please agree to the NDA and DPA to log in.');
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
        setState(() => _errorMessage =
            'Too many failed attempts. Please wait ${mins}m ${secs}s before trying again.');
        return;
      } else {
        // lockout already expired so we reset the counter, fresh start for the user
        _failedLoginAttempts = 0;
        _lastFailedAttempt = null;
      }
    }

    // show loading spinner and clear any old error message before we send the request
    setState(() { _isLoading = true; _errorMessage = null; });

    // this is where we actually call the auth service to do the login, pray lang
    final result = await _authService.signIn(idOrEmail: input, password: password);

    if (!mounted) return; // safety check in case screen was closed while loading
    setState(() => _isLoading = false);

    if (result.success) {
      // login success, reset the failed counter and send user to their dashboard
      _failedLoginAttempts = 0;
      _lastFailedAttempt = null;
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => screenForRole(result.role!, result.userId!)),
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
        title: const Text('NDA & DPA Agreements', style: TextStyle(fontWeight: FontWeight.bold)),
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
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // show the forgot password dialog so user can request a reset link via email
  void _showForgotPasswordDialog() {
    final emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your institutional email to receive a reset link.'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                hintText: 'email@ctu.edu.ph',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          SafeElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return; // dont send anything if the field is blank
              
              // we store navigator and scaffold messenger before the async call
              // this is important so we dont use context after it might be gone
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              
              navigator.pop(); // close dialog first, then send the request
              final result = await _authService.sendPasswordResetEmail(email);
              
              // show snackbar to tell user if the reset email was sent or not
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(result.success
                      ? 'Reset link sent! Check your email.'
                      : 'Error: ${result.error}'),
                  backgroundColor: result.success ? AppColors.success : AppColors.error,
                ),
              );
            },
            child: const Text('Send Link'),
          ),
        ],
      ),
    );
  }

  // show the update password dialog when user click the reset link from their email
  // this pop up automatically when supabase detect the password recovery event
  void _showUpdatePasswordDialog() {
    final passwordController = TextEditingController();
    bool isUpdating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Set New Password', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your identity has been verified. Please enter a new password for your account.'),
              const SizedBox(height: 20),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_reset),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: isUpdating ? null : () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final newPass = passwordController.text.trim();

                // validate password strength, must meet all requirements or we reject it
                // same rules as signup so its consistent, dili ta puwede mag-cheat diri
                final hasLength  = newPass.length >= 8;
                final hasUpper   = newPass.contains(RegExp(r'[A-Z]'));
                final hasNumber  = newPass.contains(RegExp(r'[0-9]'));
                final hasSpecial = newPass.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));

                if (!hasLength || !hasUpper || !hasNumber || !hasSpecial) {
                  messenger.showSnackBar(const SnackBar(
                    content: Text(
                      'Password must be at least 8 characters and include '
                      'an uppercase letter, a number, and a special character.',
                    ),
                  ));
                  return;
                }

                setDialogState(() => isUpdating = true);
                try {
                  await Supabase.instance.client.auth.updateUser(
                    UserAttributes(password: newPass),
                  );
                  if (mounted) navigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Password updated successfully! Please login.'), backgroundColor: AppColors.success),
                  );
                } catch (e) {
                  setDialogState(() => isUpdating = false);
                  messenger.showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                  );
                }
              },
              child: isUpdating 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('iEvaluate', style: TextStyle(color: AppColors.surface, fontSize: 24, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 24.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryTint,
              backgroundImage: const AssetImage('assets/images/CTU_logo.png'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('iEvaluate Portal', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -1.0)),
                const SizedBox(height: 8),
                Text('Secure Access to Academic Evaluation Tools', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                const SizedBox(height: 48),

                _buildTextField(controller: _idController, hintText: 'University ID or Institutional Email', icon: Icons.alternate_email_rounded),
                const SizedBox(height: 20),
                _buildTextField(controller: _passwordController, hintText: 'Password', icon: Icons.lock_outline_rounded, isPassword: true),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPasswordDialog,
                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    child: const Text('Forgot Password?', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),

                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderHairline),
                  ),
                  child: CheckboxListTile(
                    title: Row(
                      children: [
                        const Expanded(child: Text('I agree to the NDA and DPA', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary))),
                        IconButton(
                          icon: const Icon(Icons.info_outline, color: AppColors.primary),
                          onPressed: _showNdaDpaModal,
                          tooltip: 'Read Agreements',
                        ),
                      ],
                    ),
                    value: _hasAcceptedAgreements,
                    onChanged: (val) => setState(() => _hasAcceptedAgreements = val ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.only(left: 8, right: 4),
                    dense: true,
                  ),
                ),
                const SizedBox(height: 12),

                if (_errorMessage != null) ...[
                  Builder(builder: (context) {
                    final isNoInternet = _errorMessage!.toLowerCase().contains('no internet') ||
                        _errorMessage!.toLowerCase().contains('wifi') ||
                        _errorMessage!.toLowerCase().contains('mobile data');
                    final icon = isNoInternet ? Icons.wifi_off_rounded : Icons.error_outline_rounded;
                    final color = isNoInternet ? Colors.orange.shade700 : AppColors.error;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: color, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: color, fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 8),
                SizedBox(
                  height: 58,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textInverted,
                      disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text('Sign In', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 40),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Need an account?", style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                        child: const Text('Register Here', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
      style: const TextStyle(fontWeight: FontWeight.w500),
      onSubmitted: isPassword ? (_) => _handleLogin() : null,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.textTertiary),
        prefixIcon: Icon(icon, color: AppColors.textPrimary.withValues(alpha: 0.7), size: 22),
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textTertiary, size: 20),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        )
            : null,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.borderHairline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.borderHairline)),
      ),
    );
  }
}