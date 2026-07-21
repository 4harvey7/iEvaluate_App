// lib/signup_screen.dart
import 'package:flutter/material.dart';

import 'core/services/auth_service.dart';
import 'theme/app_colors.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _authService = AuthService();
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalSteps = 4;

  final TextEditingController _firstNameController       = TextEditingController();
  final TextEditingController _lastNameController        = TextEditingController();
  final TextEditingController _addressController         = TextEditingController();
  final TextEditingController _idController              = TextEditingController();
  final TextEditingController _emailController           = TextEditingController();
  final TextEditingController _departmentController      = TextEditingController();
  final TextEditingController _roleController            = TextEditingController();
  final TextEditingController _passwordController        = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword        = true;
  bool _obscureConfirmPassword = true;
  bool _hasAcceptedAgreements  = false;
  bool _has8Chars              = false;
  bool _hasUpper               = false;
  bool _hasNumber              = false;
  bool _hasSpecial             = false;
  bool _passwordsMatch         = false;
  bool _isLoading              = false;
  String? _errorMessage;

  List<String> _departments = [];
  List<String> _statusrole = [];
  bool _isFetchingMetadata = true;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final depts = await _authService.getDepartments();
    final roles = await _authService.getRoles();
    if (mounted) {
      setState(() {
        _departments = depts;
        _statusrole = roles;
        _isFetchingMetadata = false;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _firstNameController.dispose(); _lastNameController.dispose();
    _addressController.dispose(); _idController.dispose();
    _emailController.dispose(); _departmentController.dispose();
    _roleController.dispose(); _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _validatePassword(String value) {
    setState(() {
      _has8Chars  = value.length >= 8;
      _hasUpper   = value.contains(RegExp(r'[A-Z]'));
      _hasNumber  = value.contains(RegExp(r'[0-9]'));
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
    if (value == null || value.isEmpty) return null;
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(value) ? null : 'Enter a valid email';
  }

  String? _validateCurrentStep() {
    switch (_currentPage) {
      case 0: // Personal info
        if (_firstNameController.text.trim().isEmpty) return 'First name is required';
        if (_lastNameController.text.trim().isEmpty) return 'Last name is required';
        if (_addressController.text.trim().isEmpty) return 'Address is required';
        return null;
      case 1: // Academic info
        final id = _idController.text.trim();
        if (id.isEmpty) return 'University ID is required';
        if (id.length < 4) return 'University ID must be at least 4 characters';
        if (!RegExp(r'^[a-zA-Z0-9\-]+$').hasMatch(id)) return 'University ID must be letters, numbers, or hyphens only';
        if (_emailController.text.trim().isEmpty) return 'Institutional email is required';
        if (_validateEmail(_emailController.text.trim()) != null) return 'Enter a valid institutional email';
        if (_roleController.text.trim().isEmpty) return 'Please select a role';
        if (!_roleController.text.toUpperCase().contains('SAO') && _departmentController.text.trim().isEmpty) {
          return 'Please select a department';
        }
        return null;
      default:
        return null;
    }
  }

  void _onContinue() {
    if (_currentPage < _totalSteps - 1) {
      final error = _validateCurrentStep();
      if (error != null) {
        setState(() => _errorMessage = error);
        return;
      }
      setState(() => _errorMessage = null);
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _submitRegistration();
    }
  }

  void _onBack() {
    if (_currentPage > 0) {
      setState(() => _errorMessage = null);
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Future<void> _submitRegistration() async {
    setState(() { _isLoading = true; _errorMessage = null; });

    // TODO: signUp() logic lives in AuthService. Add Supabase code there, not here.
    // This is the part where all the UI data is "sent" to the auth_service.dart
    final result = await _authService.signUp(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      address: _addressController.text,
      universityId: _idController.text,
      institutionalEmail: _emailController.text,
      departmentName: _departmentController.text,
      roleName: _roleController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      _showPendingApprovalDialog();
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSecurityStep = _currentPage == 2;
    final bool isReviewStep   = _currentPage == 3;
    final bool passwordValid  = _has8Chars && _hasUpper && _hasNumber && _hasSpecial && _passwordsMatch;
    bool canProceed           = !isSecurityStep || passwordValid;
    if (isReviewStep) canProceed = _hasAcceptedAgreements;

    return Scaffold(
      backgroundColor: AppColors.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Registration', style: TextStyle(color: AppColors.textInverted, fontWeight: FontWeight.bold)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: AppColors.textPrimary.withValues(alpha: 0.05),
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

                    const Spacer(),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: AppColors.error, size: 18),
                              const SizedBox(width: 10),
                              Expanded(child: Text(_errorMessage!, style: TextStyle(color: AppColors.error, fontSize: 13))),
                            ],
                          ),
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          if (_currentPage > 0) ...[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isLoading ? null : _onBack,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  side: const BorderSide(color: AppColors.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Back'),
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: (canProceed && !_isLoading) ? _onContinue : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.textInverted,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                  : Text(_currentPage == _totalSteps - 1 ? 'Register' : 'Continue',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildProfileStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Personal Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          _buildInput(controller: _firstNameController, hint: 'First Name', icon: Icons.person_outline),
          const SizedBox(height: 16),
          _buildInput(controller: _lastNameController, hint: 'Last Name', icon: Icons.person_outline),
          const SizedBox(height: 16),
          _buildInput(controller: _addressController, hint: 'Home Address', icon: Icons.home_outlined),
        ],
      ),
    );
  }

  Widget _buildAcademicStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Academic Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          _buildInput(controller: _idController, hint: 'University ID', icon: Icons.badge_outlined),
          const SizedBox(height: 16),
          _buildInput(
            controller: _emailController, hint: 'Institutional Email', icon: Icons.email_outlined,
            onChanged: (val) => setState(() {}),
            errorText: _validateEmail(_emailController.text),
          ),
          const SizedBox(height: 16),
          _buildDropdownforstatus(),
          // Only show department for non-SAO roles
          if (!_roleController.text.toUpperCase().contains('SAO')) ...[
            const SizedBox(height: 16),
            _buildDropdown(),
          ],
        ],
      ),
    );
  }

  Widget _buildSecurityStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Create Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          _buildInput(
            controller: _passwordController, hint: 'Password', icon: Icons.lock_outline,
            isPass: true, state: _obscurePassword,
            toggle: () => setState(() => _obscurePassword = !_obscurePassword),
            onChanged: _validatePassword,
          ),
          const SizedBox(height: 12),
          _buildRequirementRow('At least 8 characters', _has8Chars),
          _buildRequirementRow('One uppercase letter', _hasUpper),
          _buildRequirementRow('One number', _hasNumber),
          _buildRequirementRow('One special character', _hasSpecial),
          const SizedBox(height: 16),
          _buildInput(
            controller: _confirmPasswordController, hint: 'Confirm Password', icon: Icons.lock_reset,
            isPass: true, state: _obscureConfirmPassword,
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
          const Text('Review & Terms', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          Container(
            height: 180,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderHairline),
            ),
            child: const SingleChildScrollView(
              child: Text(
                'Data Privacy & NDA: By registering, you acknowledge that all evaluation '
                    'data is sensitive and subject to university policy. Sharing, reproducing, '
                    'or misusing evaluation results is strictly prohibited and may result in '
                    'disciplinary action in accordance with CTU data privacy regulations.',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
          ),
          const Spacer(),
          CheckboxListTile(
            title: const Text('I accept terms and conditions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            value: _hasAcceptedAgreements,
            onChanged: (val) => setState(() => _hasAcceptedAgreements = val!),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPass = false,
    bool? state,
    VoidCallback? toggle,
    Function(String)? onChanged,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      obscureText: state ?? false,
      onChanged: onChanged,
      enabled: !_isLoading,
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        suffixIcon: isPass
            ? IconButton(icon: Icon((state ?? false) ? Icons.visibility_off : Icons.visibility, size: 20), onPressed: toggle)
            : null,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.borderHairline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.borderHairline)),
      ),
    );
  }

  Widget _buildRequirementRow(String label, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(isMet ? Icons.check_circle : Icons.circle_outlined, size: 14, color: isMet ? AppColors.success : AppColors.textTertiary),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: isMet ? AppColors.success : AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderHairline)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          hint: Text(_isFetchingMetadata ? 'Loading...' : 'Select Department'),
          isExpanded: true,
          value: _departmentController.text.isEmpty ? null : _departmentController.text,
          items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
          onChanged: (_isLoading || _isFetchingMetadata) ? null : (val) => setState(() => _departmentController.text = val!),
        ),
      ),
    );
  }

  Widget _buildDropdownforstatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderHairline)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          hint: Text(_isFetchingMetadata ? 'Loading...' : 'Select Role'),
          isExpanded: true,
          value: _roleController.text.isEmpty ? null : _roleController.text,
          items: _statusrole.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
          onChanged: (_isLoading || _isFetchingMetadata) ? null : (val) => setState(() {
            _roleController.text = val!;
            // Clear department when switching to SAO role
            if (val.toUpperCase().contains('SAO')) {
              _departmentController.text = '';
            }
          }),
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
          title: const Center(child: Text('Registration Submitted!', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold))),
          content: const Text(
            'Your account has been created and is pending admin approval. '
                'You will be able to log in once an SAO Administrator approves your account.',
            textAlign: TextAlign.center,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () { Navigator.of(context).pop(); Navigator.of(context).pop(); },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.textInverted),
                child: const Text('Return to Login'),
              ),
            ),
          ],
        );
      },
    );
  }
}