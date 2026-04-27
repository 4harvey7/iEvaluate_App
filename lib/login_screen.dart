// lib/login_screen.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'signup_screen.dart';
import 'sao_admin/admin_dashboard.dart';
import 'instructor/instructor_dashboard.dart';
import 'dept_head/department_dashboard_screen.dart';
import 'gatherer/data_gatherer_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin(String inputId) {
    Widget? targetScreen;
    if (inputId == 'sao' || inputId == 'admin') {
      targetScreen = const AdminDashboardScreen();
    } else if (inputId == 'instructor' || inputId == 'teach') {
      targetScreen = const InstructorDashboardScreen();
    } else if (inputId == 'dean' || inputId == 'head') {
      targetScreen = const DepartmentDashboardScreen();
    } else if (inputId == 'staff' || inputId == 'gatherer') {
      targetScreen = const DataGathererScreen();
    }

    if (targetScreen != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => targetScreen!),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Processing Login..."),
          backgroundColor: AppColors.royalBlue,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.deepBlue,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'iEvaluate',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 24.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.white,
              backgroundImage: AssetImage('assets/images/CTU_logo.png'),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Left-aligned for a modern look
              children: [
                // --- Brand Identity Section ---
                const Text(
                  'iEvaluate Portal',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepBlue,
                    letterSpacing: -1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Secure Access to Academic Evaluation Tools',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 48),

                // --- Input Section ---
                Column(
                  children: [
                    _buildTextField(
                      controller: _idController,
                      hintText: 'ID Number or Email',
                      icon: Icons.alternate_email_rounded,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _passwordController,
                      hintText: 'Password',
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          // Forgot Password logic
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.royalBlue,
                        ),
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      height: 58,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _handleLogin(_idController.text.trim().toLowerCase());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.deepBlue,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Sign In',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // --- Footer Section ---
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Need an account?",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SignUpScreen()),
                          );
                        },
                        child: const Text(
                          'Register Here',
                          style: TextStyle(
                            color: AppColors.royalBlue,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      style: const TextStyle(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        prefixIcon: Icon(icon, color: AppColors.deepBlue.withOpacity(0.7), size: 22),
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey.shade400,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        )
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.royalBlue, width: 1.5),
        ),
      ),
    );
  }
}