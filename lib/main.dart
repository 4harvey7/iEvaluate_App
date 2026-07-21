// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'core/config/env.dart';
import 'login_screen.dart';
import 'splash_screen.dart';
import 'instructor/providers/subjects_provider.dart';

// Import your dashboard screens here so the router can find them!
import 'sao_admin/admin_dashboard.dart';
import 'instructor/instructor_dashboard.dart';
import 'dept_head/department_dashboard_screen.dart';
import 'gatherer/data_gatherer_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  runApp(const MyApp());
}

// TEACHING POINT: The Role-Based Router
// We put this here so that both the initial app load AND the Login Screen
// can use the exact same logic to decide where a user belongs.
Widget screenForRole(String role, String userId) {
  print('[ROUTER] 🚀 Redirecting user with Role: $role and ID: $userId');
  switch (role) {
    case 'SAO_ADMIN':
      return AdminDashboardScreen(userId: userId);
    case 'FULL-TIME':
    case 'PART-TIME':
    case 'INSTRUCTOR':
      return InstructorDashboardScreen(userId: userId);
    case 'DEPARTMENT-HEAD': 
    case 'DEPARTMENT_HEAD': // Added underscore variant from database
    case 'DEAN':
      return DepartmentDashboardScreen(userId: userId);
    case 'SAO_STAFF':
      return DataGathererScreen(userId: userId);
    default:
      debugPrint('[ROUTER] ⚠️ Unrecognized role: "$role". Sending to Login.');
      return const LoginScreen();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SubjectsProvider()..load()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'iEvaluate',
        theme: ThemeData(primarySwatch: Colors.orange),
        home: const SplashScreen(),
      ),
    );
  }
}
