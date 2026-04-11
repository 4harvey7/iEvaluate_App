import 'package:flutter/material.dart';
import 'app_colors.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // --- Step Tracker ---
  int _currentStep = 0;

  // --- Controllers ---
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final List<String> _departments = [
    'Computer Studies',
    'Engineering',
    'Education',
    'Arts and Sciences',
    'Business and Management',
    'Technology',
    'Nursing',
    'Agriculture',
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _idController.dispose();
    _emailController.dispose();
    _departmentController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Pending Approval Dialog
  void _showPendingApprovalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.access_time_filled, color: AppColors.gold, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Registration Pending',
                  style: TextStyle(
                    color: AppColors.deepBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Your account details have been submitted successfully. \n\nYou must wait for the SAO-Admin to review and approve your account.',
            style: TextStyle(color: AppColors.darkGray, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Return to login
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.white,
                backgroundColor: AppColors.deepBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text('I Understand', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      // Removed the standard AppBar to use your custom header
      body: SafeArea(
        child: Column(
          children: [
            // ==========================================
            // 1. CUSTOM HEADER SECTION
            // ==========================================
            Container(
              padding: const EdgeInsets.only(
                  left: 8.0, right: 24.0, top: 20.0, bottom: 16.0), // Less left padding to fit the back button
              color: AppColors.deepBlue,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Back Button manually added to the custom header
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Create Account',
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
            // 2. STEPPER AREA
            // ==========================================
            Expanded( // Wrapped the Stepper in an Expanded widget so it scrolls properly below the header
              child: Theme(
                data: ThemeData(
                  colorScheme: const ColorScheme.light(primary: AppColors.deepBlue),
                  canvasColor: AppColors.white,
                ),
                child: Stepper(
                  type: StepperType.vertical,
                  currentStep: _currentStep,
                  onStepTapped: (step) => setState(() => _currentStep = step),
                  onStepContinue: () {
                    final isLastStep = _currentStep == _getSteps().length - 1;
                    if (isLastStep) {
                      _showPendingApprovalDialog();
                    } else {
                      setState(() => _currentStep += 1);
                    }
                  },
                  onStepCancel: () {
                    _currentStep == 0 ? null : setState(() => _currentStep -= 1);
                  },
                  controlsBuilder: (BuildContext context, ControlsDetails details) {
                    final isLastStep = _currentStep == _getSteps().length - 1;
                    return Padding(
                      padding: const EdgeInsets.only(top: 24.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: details.onStepContinue,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: AppColors.deepBlue,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Center(
                                child: Text(
                                  isLastStep ? 'Submit Registration' : 'Next Step',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                            ),
                          ),
                          if (_currentStep > 0) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: details.onStepCancel,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.darkGray,
                                  side: const BorderSide(color: Colors.grey),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Back',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                  steps: _getSteps(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Defining the Steps ---
  List<Step> _getSteps() => [
    // STEP 1: Personal Details
    Step(
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      isActive: _currentStep >= 0,
      title: const Text('Personal Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.deepBlue)),
      content: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildTextField(controller: _firstNameController, hintText: 'First Name', icon: Icons.person_outline)),
                const SizedBox(width: 12),
                Expanded(child: _buildTextField(controller: _lastNameController, hintText: 'Last Name', icon: Icons.person_outline)),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(controller: _addressController, hintText: 'Full Address', icon: Icons.location_on_outlined),
          ],
        ),
      ),
    ),

    // STEP 2: Academic Info
    Step(
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      isActive: _currentStep >= 1,
      title: const Text('Academic Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.deepBlue)),
      content: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            _buildTextField(controller: _idController, hintText: 'ID Number', icon: Icons.badge_outlined),
            const SizedBox(height: 16),
            _buildTextField(controller: _emailController, hintText: 'Email Address', icon: Icons.email_outlined),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
              child: DropdownMenu<String>(
                controller: _departmentController,
                expandedInsets: EdgeInsets.zero,
                hintText: 'Search/Select Department',
                leadingIcon: const Icon(Icons.domain, color: AppColors.royalBlue),
                textStyle: const TextStyle(color: AppColors.darkGray),
                menuStyle: MenuStyle(backgroundColor: WidgetStateProperty.all(AppColors.white)),
                inputDecorationTheme: InputDecorationTheme(
                  hintStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                ),
                dropdownMenuEntries: _departments.map((dept) => DropdownMenuEntry<String>(value: dept, label: dept)).toList(),
              ),
            ),
          ],
        ),
      ),
    ),

    // STEP 3: Security
    Step(
      state: _currentStep > 2 ? StepState.complete : StepState.indexed,
      isActive: _currentStep >= 2,
      title: const Text('Security', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.deepBlue)),
      content: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.lightGray, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            _buildPasswordField(controller: _passwordController, hintText: 'Password', isConfirm: false),
            const SizedBox(height: 16),
            _buildPasswordField(controller: _confirmPasswordController, hintText: 'Confirm Password', isConfirm: true),
          ],
        ),
      ),
    ),
  ];

  // Reusable Widgets
  Widget _buildTextField({required TextEditingController controller, required String hintText, required IconData icon}) {
    return Container(
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: AppColors.darkGray),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.grey),
          prefixIcon: Icon(icon, color: AppColors.royalBlue),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.royalBlue, width: 2)),
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildPasswordField({required TextEditingController controller, required String hintText, required bool isConfirm}) {
    bool obscureState = isConfirm ? _obscureConfirmPassword : _obscurePassword;
    return Container(
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
      child: TextField(
        controller: controller,
        obscureText: obscureState,
        style: const TextStyle(color: AppColors.darkGray),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.grey),
          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.royalBlue),
          suffixIcon: IconButton(
            icon: Icon(obscureState ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
            onPressed: () {
              setState(() => isConfirm ? _obscureConfirmPassword = !_obscureConfirmPassword : _obscurePassword = !_obscurePassword);
            },
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.royalBlue, width: 2)),
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }
}