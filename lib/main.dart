// lib/main.dart
// this is the main file. the big boss. the beginning of everything. dont mess it up
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env.dart';
import 'login_screen.dart';
import 'splash_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

// Role-based navigation — all routing now goes through MainScaffold.
// role_nav_config.dart is the single source of truth for what each role sees.
import 'core/navigation/main_scaffold.dart';
import 'core/navigation/role_nav_config.dart';

// TECHNICAL DEBT: The gatherer role bypasses MainScaffold because
// DataGathererScreen self-manages 5 internal tabs with tightly coupled state.
// See role_nav_config.dart and main_scaffold.dart for full explanation.
import 'gatherer/data_gatherer_screen.dart';

import 'package:firebase_core/firebase_core.dart';
import 'core/services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (will look for google-services.json automatically on Android)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // secrets are injected at build time via --dart-define-from-file=.env.json
  // no runtime file loading needed, thank goodness
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);

  runApp(const MyApp());
}

// Role-based router — resolves a DB role string to the correct entry screen.
// Non-gatherer roles go into MainScaffold; gatherer is passed through directly.
// To add a new role: add it to UserRole + roleNavConfigs in role_nav_config.dart,
// then add its string mapping in roleFromString() (also in role_nav_config.dart).
Widget screenForRole(String role, String userId) {
  debugPrint('[ROUTER] Redirecting user with role: "$role"');

  final userRole = roleFromString(role);

  if (userRole == null) {
    // Unrecognised role — boot back to login rather than crashing.
    debugPrint('[ROUTER] Unrecognized role: "$role". Sending to Login.');
    return const LoginScreen();
  }

  // TECHNICAL DEBT: Gatherer bypasses MainScaffold — see file-level comment above.
  if (userRole == UserRole.gatherer) {
    return DataGathererScreen(userId: userId);
  }

  // All other roles route through the shared scaffold.
  return MainScaffold(role: userRole, userId: userId);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.home});

  /// Allows tests and previews to render a destination without waiting for the
  /// production splash/session handoff.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner:
          false, // we hide the debug banner, it look unprofessional
      title: 'iEvaluate',
      theme: AppTheme
          .light, // use the fully-configured project theme instead of bare primarySwatch
      builder: (context, child) {
        // Global tablet/iPad responsiveness fix
        // Constrain the entire app's width so no screen stretches beyond 800 pixels
        return Container(
          color: AppColors.background, // Fills the empty side-space on tablets
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ClipRect(child: child),
            ),
          ),
        );
      },
      home:
          home ??
          const SplashScreen(), // production starts at splash; tests may inject a stable screen
    );
  }
}
