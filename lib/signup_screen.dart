// lib/signup_screen.dart
// this is the signup screen. user come here to beg the system for an account.
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'core/config/agreements.dart';
import 'core/services/auth_service.dart';
import 'theme/app_colors.dart';

// the main widget for the signup screen. stateful because things gonna change
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

// the actual brain of the screen. holds all the messy state
class _SignUpScreenState extends State<SignUpScreen> {
  final _authService = AuthService(); // our trusty auth helper, wala choice but to use it
  final PageController _pageController = PageController(); // controls which step we on
  int _currentPage = 0; // which page we at right now, starts at 0 like normal people
  final int _totalSteps = 4; // 4 steps total, dili ta pwede make it less

  // all the text controllers, one for every field the user has to fill up
  // importente kaayo -- dispose all of these later or you get memory leak forever
  final TextEditingController _firstNameController       = TextEditingController();
  final TextEditingController _lastNameController        = TextEditingController();
  final TextEditingController _addressController         = TextEditingController();
  final TextEditingController _idController              = TextEditingController();
  final TextEditingController _emailController           = TextEditingController();
  final TextEditingController _departmentController      = TextEditingController();
  
  String _selectedEmploymentStatus = 'Full-Time'; // Default to Full-Time (Resident)
  final TextEditingController _roleController            = TextEditingController();
  final TextEditingController _passwordController        = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // booleans that track whether the password is strong enough to survive
  bool _obscurePassword        = true;  // hide the password by default, ayaw show it
  bool _obscureConfirmPassword = true;  // same for the confirm field
  bool _hasAcceptedAgreements  = false; // user must agree or they cant proceed, dili pwede skip
  bool _hasScrolledToBottom    = false; // user must scroll to bottom of NDA/DPA first
  bool _has8Chars              = false; // password length check
  bool _hasUpper               = false; // must have uppercase, murag shouting is required
  bool _hasNumber              = false; // at least one number, basin they forget
  bool _hasSpecial             = false; // special chars, like !@#, the weird ones
  bool _passwordsMatch         = false; // both passwords must be the same, obviously
  bool _isLoading              = false; // true when we waiting for server, patience ra
  String? _errorMessage;               // holds the error text if something went wrong

  List<String> _departments = []; // list of departments fetched from server
  List<String> _statusrole = [];  // list of roles, fetched too, same server
  bool _isFetchingMetadata = true; // true while we still loading departments and roles

  // called when widget first appear in the tree, we load the dropdown data here
  @override
  void initState() {
    super.initState();
    _loadMetadata(); // go fetch departments and roles, bahala na what happens
  }

  // fetch departments and roles from server so the dropdowns have something to show
  Future<void> _loadMetadata() async {
    final depts = await _authService.getDepartments(); // get all departments from db
    final roles = await _authService.getRoles();       // get all roles too
    if (mounted) {
      setState(() {
        _departments = depts;        // store departments
        _statusrole = roles;         // store roles
        _isFetchingMetadata = false; // done loading, dropdowns can show now
      });
    }
  }

  // cleanup all the controllers when screen die, very importente or memory go boom
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

  // check if the password follow the rules, called every time user type a letter
  void _validatePassword(String value) {
    setState(() {
      _has8Chars  = value.length >= 8;                                         // at least 8 chars
      _hasUpper   = value.contains(RegExp(r'[A-Z]'));                          // need at least one big letter
      _hasNumber  = value.contains(RegExp(r'[0-9]'));                          // need a number too
      _hasSpecial = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));        // need weird symbol
      _validateMatch(); // also check if both passwords same after every change
    });
  }

  // check if password and confirm password are the same, ayaw typo
  void _validateMatch() {
    setState(() {
      _passwordsMatch = _passwordController.text.isNotEmpty &&
          _passwordController.text == _confirmPasswordController.text; // both must be identical
    });
  }

  // validate the email format, returns error string if bad, null if good
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return null; // empty is handled elsewhere, skip
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$'); // the classic email regex
    return emailRegex.hasMatch(value) ? null : 'Enter a valid email'; // either pass or fail, simple
  }

  // validate the current step before user allowed to go to next step
  // returns error message string if something wrong, null if all good
  String? _validateCurrentStep() {
    switch (_currentPage) {
      case 0: // Personal info -- name and address, basic stuff
        if (_firstNameController.text.trim().isEmpty) return 'First name is required';
        if (_lastNameController.text.trim().isEmpty) return 'Last name is required';
        if (_addressController.text.trim().isEmpty) return 'Address is required';
        return null;
      case 1: // Academic info -- ID, email, role, dept
        final id = _idController.text.trim();
        if (id.isEmpty) return 'University ID is required';
        if (id.length < 4) return 'University ID must be at least 4 characters';
        if (!RegExp(r'^[a-zA-Z0-9\-]+$').hasMatch(id)) return 'University ID must be letters, numbers, or hyphens only';
        if (_emailController.text.trim().isEmpty) return 'Institutional email is required';
        if (_validateEmail(_emailController.text.trim()) != null) return 'Enter a valid institutional email';
        if (_roleController.text.trim().isEmpty) return 'Please select a role';
        if (!_roleController.text.toUpperCase().contains('SAO') && _departmentController.text.trim().isEmpty) {
          return 'Please select a department'; // SAO users dili need department, lucky them
        }
        return null;
      default:
        return null; // other steps have no backend validation here, bahala na
    }
  }

  // called when user press Continue button. validate first, then move to next page.
  // on the last step, submit the form instead of going forward
  void _onContinue() {
    if (_currentPage < _totalSteps - 1) {
      final error = _validateCurrentStep(); // check if current step is filled properly
      if (error != null) {
        setState(() => _errorMessage = error); // show the error to the poor user
        return;
      }
      setState(() => _errorMessage = null); // clear old error if we passed
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); // slide to next page
    } else {
      _submitRegistration(); // last step, time to actually register the user
    }
  }

  // go back to the previous step, also clear any error message lying around
  void _onBack() {
    if (_currentPage > 0) {
      setState(() => _errorMessage = null); // wipe the error, fresh start on prev page
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  // the big final boss -- send all form data to auth service for actual registration
  Future<void> _submitRegistration() async {
    setState(() { _isLoading = true; _errorMessage = null; }); // show loading, hide errors

    // TODO: signUp() logic lives in AuthService. Add Supabase code there, not here.
    // This is the part where all the UI data is "sent" to the auth_service.dart
    // we just pass data here, auth_service do the heavy lifting
    final result = await _authService.signUp(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      address: _addressController.text,
      universityId: _idController.text,
      institutionalEmail: _emailController.text,
      departmentName: _departmentController.text,
      roleName: _roleController.text,
      password: _passwordController.text,
      employmentStatus: _selectedEmploymentStatus,
    );

    if (!mounted) return; // widget might be gone by now, ayaw crash
    setState(() => _isLoading = false); // done loading, show result

    if (result.success) {
      _showPendingApprovalDialog(); // success! tell user to wait for admin blessing
    } else {
      setState(() => _errorMessage = result.error); // something went wrong, show the error
    }
  }

  // build the whole screen -- progress bar on top, steps in middle, buttons at bottom
  @override
  Widget build(BuildContext context) {
    final bool isSecurityStep = _currentPage == 2; // step 3 is the password step
    final bool isReviewStep   = _currentPage == 3; // step 4 is review and accept terms
    final bool passwordValid  = _has8Chars && _hasUpper && _hasNumber && _hasSpecial && _passwordsMatch; // all password rules pass?
    bool canProceed           = !isSecurityStep || passwordValid; // only block if on security step with bad password
    if (isReviewStep) canProceed = _hasAcceptedAgreements; // on review step, must tick the checkbox

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textInverted),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Registration', style: TextStyle(color: AppColors.textInverted, fontWeight: FontWeight.bold)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    // progress bar at top -- shows how far along the user is
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: AppColors.textPrimary.withValues(alpha: 0.05),
                      child: Row(
                        children: List.generate(_totalSteps, (index) => Expanded(
                          child: Container(
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: index <= _currentPage ? AppColors.primary : AppColors.borderSubtle, // filled if reached, grey if not yet
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        )),
                      ),
                    ),

                    // the actual step pages, user cant swipe manually, buttons only
                    SizedBox(
                      height: 520,
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(), // dili ta pwede swipe manually
                        onPageChanged: (page) => setState(() => _currentPage = page), // update current page tracker
                        children: [
                          _buildProfileStep(),  // step 1: personal info
                          _buildAcademicStep(), // step 2: academic info
                          _buildSecurityStep(), // step 3: password creation
                          _buildReviewStep(),   // step 4: review and accept terms
                        ],
                      ),
                    ),

                    const Spacer(),

                    // error banner -- only shows when there is an error, obviously
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

                    // navigation buttons: Back and Continue/Register
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          // back button only appear if we past the first step
                          if (_currentPage > 0) ...[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isLoading ? null : _onBack, // disabled while loading
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
                              onPressed: (canProceed && !_isLoading) ? _onContinue : null, // disabled if cant proceed or loading
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.textPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2.5)) // spinning wheel of hope
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
              ),
            ),
          );
        },
      ),
    );
  }

  // step 1: ask for first name, last name, and home address. basic human information
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

  // step 2: ask for university ID, institutional email, role, and department
  // SAO role users skip the department field -- they too special for that
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
            onChanged: (val) => setState(() {}), // rebuild so email error updates live
            errorText: _validateEmail(_emailController.text),
          ),
          const SizedBox(height: 16),
          _buildDropdownforstatus(), // role selector -- pick what kind of person you are
          // Only show department and employment status for non-SAO roles
          if (!_roleController.text.toUpperCase().contains('SAO')) ...[
            const SizedBox(height: 16),
            _buildEmploymentStatusDropdown(),
            const SizedBox(height: 16),
            _buildDropdown(), // department selector, only for non-SAO people
          ],
        ],
      ),
    );
  }

  // step 3: create the password. many rules. must be strong. no shortcuts, ayaw
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
            toggle: () => setState(() => _obscurePassword = !_obscurePassword), // toggle show/hide
            onChanged: _validatePassword, // check rules on every keypress
          ),
          const SizedBox(height: 12),
          // show the password requirements checklist
          _buildRequirementRow('At least 8 characters', _has8Chars),
          _buildRequirementRow('One uppercase letter', _hasUpper),
          _buildRequirementRow('One number', _hasNumber),
          _buildRequirementRow('One special character', _hasSpecial),
          const SizedBox(height: 16),
          _buildInput(
            controller: _confirmPasswordController, hint: 'Confirm Password', icon: Icons.lock_reset,
            isPass: true, state: _obscureConfirmPassword,
            toggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            onChanged: (val) => _validateMatch(), // check if both passwords are same
            errorText: (_confirmPasswordController.text.isNotEmpty && !_passwordsMatch) ? 'Passwords do not match' : null,
          ),
        ],
      ),
    );
  }

  // step 4: show the data privacy/NDA text and a checkbox
  // user must scroll to bottom to accept, wala choice
  Widget _buildReviewStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review & Terms', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          const Text(
            'Please read and scroll through the Data Privacy Act (DPA) and Non-Disclosure Agreement (NDA) to continue.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification scrollInfo) {
                  if (!_hasScrolledToBottom && scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 20) {
                    setState(() => _hasScrolledToBottom = true);
                  }
                  return true;
                },
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      MarkdownBody(data: Agreements.ndaText),
                      Divider(height: 32, thickness: 1),
                      MarkdownBody(data: Agreements.dpaText),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderHairline),
            ),
            child: CheckboxListTile(
              title: const Text('I agree to the NDA and DPA', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
              subtitle: !_hasScrolledToBottom ? const Text('Scroll to the bottom to agree', style: TextStyle(fontSize: 12, color: AppColors.error)) : null,
              value: _hasAcceptedAgreements,
              onChanged: _hasScrolledToBottom
                  ? (val) => setState(() => _hasAcceptedAgreements = val ?? false)
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.only(left: 8, right: 4),
              dense: true,
            ),
          ),
        ],
      ),
    );
  }

  // reusable text field builder -- used for all input fields in the form
  // pass isPass: true for password fields so it can be hidden/shown
  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPass = false,          // is this a password field? default no
    bool? state,                  // current obscure state for password fields
    VoidCallback? toggle,         // function to toggle show/hide
    Function(String)? onChanged,  // callback when user type something
    String? errorText,            // error text shown below the field
  }) {
    return TextField(
      controller: controller,
      obscureText: state ?? false, // hide text if state is true, else show it
      onChanged: onChanged,
      enabled: !_isLoading, // disable all inputs while loading, ayaw let user spam
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        prefixIcon: Icon(icon, color: AppColors.primaryText, size: 20),
        suffixIcon: isPass
            ? IconButton(icon: Icon((state ?? false) ? Icons.visibility_off : Icons.visibility, size: 20), onPressed: toggle) // eye icon toggle
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

  // one row in the password requirement checklist
  // shows a check icon if the requirement is met, circle if not met yet
  Widget _buildRequirementRow(String label, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(isMet ? Icons.check_circle : Icons.circle_outlined, size: 14, color: isMet ? AppColors.success : AppColors.textSecondary), // green check or grey circle
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: isMet ? AppColors.success : AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildEmploymentStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderHairline)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedEmploymentStatus,
          items: const [
            DropdownMenuItem(value: 'Full-Time', child: Text('Resident (Full-Time)')),
            DropdownMenuItem(value: 'Part-Time', child: Text('Non-Resident (Part-Time)')),
          ],
          onChanged: _isLoading ? null : (val) => setState(() => _selectedEmploymentStatus = val!),
        ),
      ),
    );
  }

  // dropdown for department selection -- only shows if the role is not SAO
  // fetches from _departments list, which came from server earlier
  Widget _buildDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderHairline)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          hint: Text(_isFetchingMetadata ? 'Loading...' : 'Select Department'), // show loading text while fetching
          isExpanded: true,
          value: _departmentController.text.isEmpty ? null : _departmentController.text,
          items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
          onChanged: (_isLoading || _isFetchingMetadata) ? null : (val) => setState(() => _departmentController.text = val!), // disabled while loading
        ),
      ),
    );
  }

  // dropdown for role selection -- murag what kind of account user want
  // if SAO is selected, the department field disappears because SAO is special
  Widget _buildDropdownforstatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderHairline)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          hint: Text(_isFetchingMetadata ? 'Loading...' : 'Select Role'), // still loading? wait lang
          isExpanded: true,
          value: _roleController.text.isEmpty ? null : _roleController.text,
          items: _statusrole.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
          onChanged: (_isLoading || _isFetchingMetadata) ? null : (val) => setState(() {
            _roleController.text = val!;
            // Clear department when switching to SAO role
            // SAO people dili need department, so we wipe it out
            if (val.toUpperCase().contains('SAO')) {
              _departmentController.text = ''; // reset department field, SAO lang gyud
            }
          }),
        ),
      ),
    );
  }

  // show a dialog telling user the account is submitted and waiting for admin approval
  // barrierDismissible false means they MUST press the button, wala escape
  void _showPendingApprovalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // user must click the button, wala choice
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
                onPressed: () { Navigator.of(context).pop(); Navigator.of(context).pop(); }, // close dialog then close signup screen, go back to login
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.textPrimary),
                child: const Text('Return to Login'),
              ),
            ),
          ],
        );
      },
    );
  }
}