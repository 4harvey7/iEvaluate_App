// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'instructor/providers/subjects_provider.dart';
import 'login_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final subjectsProvider = SubjectsProvider();
  await subjectsProvider.load();

  runApp(MyApp(subjectsProvider: subjectsProvider));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.subjectsProvider});

  final SubjectsProvider subjectsProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SubjectsProvider>.value(
          value: subjectsProvider,
        ),
      ],
      child: MaterialApp(
        title: 'iEvaluate',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const LoginScreen(),
      ),
    );
  }
}
