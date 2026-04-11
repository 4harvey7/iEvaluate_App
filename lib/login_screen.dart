// lib/login_screen.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'signup_screen.dart';
import 'sao_admin/admin_dashboard.dart'; // 👈 IMPORT THE ADMIN DASHBOARD HERE
import 'instructor/instructor_dashboard.dart'; // 👈 ADDED INSTRUCTOR DASHBOARD IMPORT
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==========================================
            // 1. HEADER SECTION
            // ==========================================
            Container(
              padding: const EdgeInsets.only(
                  left: 24.0, right: 24.0, top: 20.0, bottom: 16.0),
              color: AppColors.deepBlue,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        'iEvaluate',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.white,
                    backgroundImage: AssetImage('assets/images/CTU_logo.png'),
                  ),
                ],
              ),
            ),

            // ==========================================
            // 2. SCROLLABLE CONTENT AREA with Card
            // ==========================================
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  children: [
                    const Text(
                      'AI-Driven Instructor Evaluation System',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.darkGray,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),

                    Card(
                      elevation: 5,
                      color: AppColors.lightGray,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Welcome Back!',
                              style: TextStyle(
                                color: AppColors.darkGray,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Please login to your account to continue',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 24),

                            _buildTextField(
                              controller: _idController,
                              hintText: 'Enter ID Number or Email',
                              icon: Icons.person_outline,
                              inputColor: AppColors.white,
                            ),

                            const SizedBox(height: 16),

                            _buildTextField(
                              controller: _passwordController,
                              hintText: 'Password',
                              icon: Icons.lock_outline,
                              isPassword: true,
                              inputColor: AppColors.white,
                            ),

                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  // TODO: Implement forgot password
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

                            // ==========================================
                            // 3. LOGIN BUTTON LOGIC
                            // ==========================================
                            SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: () {
                                  // 👈 SMART ROUTING LOGIC UPDATED HERE
                                  String inputId = _idController.text.trim().toLowerCase();

                                  if (inputId == 'sao') {
                                    // Open the Admin Dashboard
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
                                    );
                                  } else if (inputId == 'instructor') {
                                    // Open the Instructor Dashboard
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (context) => const InstructorDashboardScreen()),
                                    );
                                  } else if (inputId == 'dean' || inputId == 'head') {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (context) => const DepartmentDashboardScreen()),
                                    );
                                  } else if (inputId == 'staff' || inputId == 'gatherer') {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (context) => const DataGathererScreen()),
                                    );
                                  }else {
                                    // Otherwise, show the normal prototype loading message
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Processing Login..."),
                                        backgroundColor: AppColors.royalBlue,
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.gold,
                                  foregroundColor: AppColors.deepBlue,
                                  elevation: 4,
                                  shadowColor: AppColors.gold.withOpacity(0.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Login',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Don't have an account? ",
                                  style: TextStyle(color: AppColors.darkGray),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const SignUpScreen()),
                                    );
                                  },
                                  child: const Text(
                                    "Sign Up",
                                    style: TextStyle(
                                      color: AppColors.royalBlue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // REUSABLE TEXT FIELD WIDGET
  // ==========================================
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    Color? inputColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: inputColor ?? AppColors.lightGray,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        style: const TextStyle(color: AppColors.darkGray),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.grey),
          prefixIcon: Icon(icon, color: AppColors.royalBlue),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.royalBlue, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }
}