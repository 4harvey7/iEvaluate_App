// lib/signup_screen.dart
import 'package:flutter/material.dart';
import 'theme/app_colors.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalSteps = 4;

  // --- Controllers ---
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // --- Validation States ---
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _hasAcceptedAgreements = false;
  bool _has8Chars = false;
  bool _hasUpper = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;
  bool _passwordsMatch = false;

  final List<String> _departments = [
    'Computer Studies', 'Engineering', 'Education', 'Arts and Sciences',
    'Business and Management', 'Technology', 'Nursing', 'Agriculture',
  ];

  @override
  void dispose() {
    _pageController.dispose();
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

  // --- Logic ---
  void _validatePassword(String value) {
    setState(() {
      _has8Chars = value.length >= 8;
      _hasUpper = value.contains(RegExp(r'[A-Z]'));
      _hasNumber = value.contains(RegExp(r'[0-9]'));
      _hasSpecial = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
      _validateMatch();
    });
  }

  void _validateMatch() {
    setState(() {
      _passwordsMatch = _passwordController.text.isNotEmpty &&
          _passwordController.text == _confirmPasswordController.text;
    });
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
    if (!value.endsWith('@ctu.edu.ph')) return 'Use @ctu.edu.ph email';
    return null;
  }

  void _onContinue() {
    if (_currentPage < _totalSteps - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _showPendingApprovalDialog();
    }
  }

  void _onBack() {
    if (_currentPage > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isSecurityStep = _currentPage == 2;
    bool isReviewStep = _currentPage == 3;
    bool passwordValid = _has8Chars && _hasUpper && _hasNumber && _hasSpecial && _passwordsMatch;
    bool canProceed = !isSecurityStep || passwordValid;
    if (isReviewStep) canProceed = _hasAcceptedAgreements;

    return Scaffold(
      backgroundColor: AppColors.surface,
      resizeToAvoidBottomInset: true, // Crucial for keyboard handling
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Registration', style: TextStyle(color: AppColors.textInverted, fontWeight: FontWeight.bold)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              // Forces the content to be at least as tall as the screen
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    // 1. Progress Bar
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: AppColors.textPrimary.withOpacity(0.05),
                      child: Row(
                        children: List.generate(_totalSteps, (index) => Expanded(
                          child: Container(
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: index <= _currentPage ? AppColors.primary : AppColors.borderSubtle,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        )),
                      ),
                    ),

                    // 2. PageView (Needs a fixed height inside a scrollable column)
                    // We use 500px as a baseline for your forms
                    SizedBox(
                      height: 520,
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (page) => setState(() => _currentPage = page),
                        children: [
                          _buildProfileStep(),
                          _buildAcademicStep(),
                          _buildSecurityStep(),
                          _buildReviewStep(),
                        ],
                      ),
                    ),

                    const Spacer(), // Pushes buttons to the bottom if there is extra space

                    // 3. Navigation Buttons
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Row(
                        children: [
                          if (_currentPage > 0)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _onBack,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Back', style: TextStyle(color: AppColors.textPrimary)),
                              ),
                            ),
                          if (_currentPage > 0) const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: canProceed ? _onContinue : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.textInverted,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(_currentPage == _totalSteps - 1 ? 'Complete Registration' : 'Continue'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildProfileStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Personal Profile", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _buildInput(controller: _firstNameController, hint: 'First Name', icon: Icons.person_outline)),
            const SizedBox(width: 12),
            Expanded(child: _buildInput(controller: _lastNameController, hint: 'Last Name', icon: Icons.person_outline)),
          ]),
          const SizedBox(height: 16),
          _buildInput(controller: _addressController, hint: 'Full Residential Address', icon: Icons.home_outlined),
        ],
      ),
    );
  }

  Widget _buildAcademicStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Academic Information", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          _buildInput(controller: _idController, hint: 'University ID Number', icon: Icons.badge_outlined),
          const SizedBox(height: 16),
          _buildInput(
            controller: _emailController,
            hint: 'Institutional Email (@ctu.edu.ph)',
            icon: Icons.email_outlined,
            onChanged: (val) => setState(() {}),
            errorText: _validateEmail(_emailController.text),
          ),
          const SizedBox(height: 16),
          _buildDropdown(),
        ],
      ),
    );
  }

  Widget _buildSecurityStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Security Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          _buildInput(
            controller: _passwordController,
            hint: 'Password',
            icon: Icons.lock_outline,
            isPass: true,
            state: _obscurePassword,
            toggle: () => setState(() => _obscurePassword = !_obscurePassword),
            onChanged: _validatePassword,
          ),
          const SizedBox(height: 12),
          _buildRequirementRow('At least 8 characters', _has8Chars),
          _buildRequirementRow('One uppercase letter', _hasUpper),
          _buildRequirementRow('One number', _hasNumber),
          _buildRequirementRow('One special character', _hasSpecial),
          const SizedBox(height: 24),
          _buildInput(
            controller: _confirmPasswordController,
            hint: 'Confirm Password',
            icon: Icons.lock_reset,
            isPass: true,
            state: _obscureConfirmPassword,
            toggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            onChanged: (val) => _validateMatch(),
            errorText: (_confirmPasswordController.text.isNotEmpty && !_passwordsMatch) ? 'Passwords do not match' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Review & Terms", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          Container(
            height: 180,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderHairline)),
            child: const SingleChildScrollView(
              child: Text("Data Privacy & NDA: By registering, you acknowledge that all evaluation data is sensitive and subject to university policy...", style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
            ),
          ),
          const Spacer(),
          CheckboxListTile(
            title: const Text("I accept terms and conditions", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            value: _hasAcceptedAgreements,
            onChanged: (val) => setState(() => _hasAcceptedAgreements = val!),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  Widget _buildInput({required TextEditingController controller, required String hint, required IconData icon, bool isPass = false, bool? state, VoidCallback? toggle, Function(String)? onChanged, String? errorText}) {
    return TextField(
      controller: controller,
      obscureText: state ?? false,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        suffixIcon: isPass ? IconButton(icon: Icon(state! ? Icons.visibility_off : Icons.visibility, size: 20), onPressed: toggle) : null,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.borderHairline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
      ),
    );
  }

  Widget _buildRequirementRow(String label, bool isMet) {
    return Row(
      children: [
        Icon(isMet ? Icons.check_circle : Icons.circle_outlined, size: 14, color: isMet ? AppColors.success : AppColors.textTertiary),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: isMet ? AppColors.success : AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderHairline)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          hint: const Text("Select Department"),
          isExpanded: true,
          value: _departmentController.text.isEmpty ? null : _departmentController.text,
          items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
          onChanged: (val) => setState(() => _departmentController.text = val!),
        ),
      ),
    );
  }

  void _showPendingApprovalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Center(child: Text('Submission Success', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold))),
          content: const Text('Your registration is complete and pending approval.', textAlign: TextAlign.center),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('Return to Login'),
              ),
            )
          ],
        );
      },
    );
  }
}