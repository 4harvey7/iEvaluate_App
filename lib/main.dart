import 'package:flutter/material.dart';
import 'agreement_screen.dart'; // Import the new file

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iEvaluate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto', // Change to your preferred font
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA32121)),
        useMaterial3: true,
      ),
      // Set the AgreementScreen as the starting point of the app
      home: const AgreementScreen(),
    );
  }
}