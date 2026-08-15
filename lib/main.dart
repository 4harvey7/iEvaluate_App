// lib/main.dart
// this is the main file. the big boss. the beginning of everything. dont mess it up
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'core/config/env.dart';
import 'login_screen.dart';
import 'splash_screen.dart';
import 'instructor/providers/subjects_provider.dart';
import 'theme/app_theme.dart';

// we import all the dashboard screens here so the router can find them, without this nothing work
import 'sao_admin/admin_dashboard.dart';
import 'instructor/instructor_dashboard.dart';
import 'dept_head/department_dashboard_screen.dart';
import 'gatherer/data_gatherer_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // secrets are injected at build time via --dart-define-from-file=.env.json
  // no runtime file loading needed, thank goodness
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  runApp(const MyApp());
}

// this is the role-based router, it decide where to send the user after login
// think of it like a bouncer but for screens, wala silay choice kung asa sila mapunta
Widget screenForRole(String role, String userId) {
  debugPrint('[ROUTER] Redirecting user with Role: $role');
  // we check the role and send the user to the right screen, simple as that
  switch (role) {
    case 'SAO_ADMIN':
      return AdminDashboardScreen(userId: userId);
    case 'FULL-TIME':
    case 'PART-TIME':
    case 'INSTRUCTOR':
      // all instructor types go to the same dashboard, we not picky here
      // SubjectsProvider is scoped here because only instructor role consumes it
      return ChangeNotifierProvider(
        create: (_) => SubjectsProvider(),
        child: InstructorDashboardScreen(userId: userId),
      );
    case 'DEPARTMENT-HEAD': 
    case 'DEPARTMENT_HEAD': // both variants work, the database cant make up its mind
    case 'DEAN':
      return DepartmentDashboardScreen(userId: userId);
    case 'SAO_STAFF':
      return DataGathererScreen(userId: userId);
    default:
      // if we dont know who this person is, we kick them back to login, safe lang
      debugPrint('[ROUTER] Unrecognized role: "$role". Sending to Login.');
      return const LoginScreen();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // we hide the debug banner, it look unprofessional
      title: 'iEvaluate',
      theme: AppTheme.light, // use the fully-configured project theme instead of bare primarySwatch
      home: const SplashScreen(), // always start at splash screen, then we figure out the rest
    );
  }
}
