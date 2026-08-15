// lib/splash_screen.dart
// this is the splash screen, the first thing user see when they open the app
// it look pretty and then kick them to login, thats literally all it do
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/services/auth_service.dart';
import 'login_screen.dart';
import 'theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // we create the auth service here so we can sign out the user on startup
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    // we check the session as soon as this screen wake up, no time to waste
    _checkSession();
  }

  Future<void> _checkSession() async {
    // ── Password-recovery deep-link guard ──────────────────────────────────
    // When a user taps the emailed reset link the OS cold-starts the app with
    // an active recovery session.  If we blindly call signOut() here we destroy
    // that session before LoginScreen (which has the passwordRecovery handler)
    // is ever mounted.  Fix: listen for the passwordRecovery auth event for the
    // duration of the splash delay.  If it fires, skip signOut and navigate
    // straight to LoginScreen so its onAuthStateChange handler shows the dialog.
    bool isPasswordRecovery = false;
    StreamSubscription<AuthState>? recoverySub;
    recoverySub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        isPasswordRecovery = true;
        recoverySub?.cancel();
      }
    });

    // we wait 2 seconds so the splash look nice, purely for aesthetic, hehe
    await Future.delayed(const Duration(milliseconds: 2000));
    await recoverySub.cancel(); // done listening — clean up regardless

    if (isPasswordRecovery) {
      // Recovery session detected — do NOT sign out.  Navigate to LoginScreen
      // which will receive the passwordRecovery event and show the reset dialog.
      debugPrint('[SPLASH] Password recovery deep-link detected — skipping signOut.');
      _navigateToLogin();
      return;
    }

    // Normal start — we force sign out every time app starts so user must log in again
    // this is a security requirement, no shortcuts allowed even if murag kadugay
    try {
      await _authService.signOut();
    } catch (e) {
      // if signout fail we just print it and move on, not the end of the world
      debugPrint('[SPLASH] Sign out error: $e');
    }

    // ok we done here, send them to login now
    _navigateToLogin();
  }

  void _navigateToLogin() {
    // we check if the widget is still alive before navigating, dili ta mag crash
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Logo - if the image missing it show a school icon, fallback lang
            Image.asset(
              'assets/images/CTU_logo.png',
              width: 120,
              height: 120,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.school,
                size: 80,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 32),
            // App Name
            const Text(
              'iEvaluate',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            // subtitle text, just to make it look official and stuff
            Text(
              'Academic Evaluation System',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 48),
            // loading spinner so user know something is happening and not frozen
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}
