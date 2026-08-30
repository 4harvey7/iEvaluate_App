// lib/signup_screen.dart
// this is the signup screen. user come here to beg the system for an account.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core/services/address_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/identity_validator.dart';
import 'theme/app_colors.dart';
import 'widgets/agreement_reader_page.dart';
import 'widgets/apple_ui.dart';
import 'widgets/duplicate_warning_dialog.dart';

/// Human wording for the raw role strings stored in the `roles` table.
///
/// The VALUE sent to the database must stay the raw string -- signUp looks the
/// role up by `roles.Roles`, and roleFromString in role_nav_config routes on it
/// -- so this is display only. Getting this wrong logs people into the wrong
/// dashboard, which is why the raw values are never rewritten.
///
/// FULL-TIME and PART-TIME are the two instructor roles; the table has no
/// separate INSTRUCTOR row. Shown as "Instructor" variants because
/// "FULL-TIME" on its own does not tell anyone what they are registering as.
const Map<String, String> kRoleLabels = <String, String>{
  'FULL-TIME': 'Instructor — Resident (Full-Time)',
  'PART-TIME': 'Instructor — Non-Resident (Part-Time)',
  'INSTRUCTOR': 'Instructor',
  'DEPARTMENT_HEAD': 'Department Head',
  'DEPARTMENT-HEAD': 'Department Head',
  'DEAN': 'Dean',
  'SAO_STAFF': 'SAO Staff (Data Gatherer)',
  'SAO_ADMIN': 'SAO Administrator',
};

/// Order the picker shows, most-registered first. The table returns rows
/// alphabetically, which interleaved "FULL-TIME" and "PART-TIME" between
/// "DEPARTMENT_HEAD" and the SAO roles and read as a jumble.
const List<String> kRoleOrder = <String>[
  'FULL-TIME',
  'PART-TIME',
  'INSTRUCTOR',
  'DEPARTMENT_HEAD',
  'DEPARTMENT-HEAD',
  'DEAN',
  'SAO_STAFF',
  'SAO_ADMIN',
];

/// Label for a raw role string.
///
/// A role that appears in the table without an entry in [kRoleLabels] is still
/// shown, just tidied -- a role nobody can read is a role nobody can register
/// as, and silently dropping it would lock those people out entirely.
String roleLabel(String raw) {
  final known = kRoleLabels[raw.toUpperCase().trim()];
  if (known != null) return known;
  return raw
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .toLowerCase()
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

/// Sorts raw role strings into [kRoleOrder], unknown ones last, alphabetically.
List<String> sortRoles(List<String> raw) {
  int rank(String r) {
    final i = kRoleOrder.indexOf(r.toUpperCase().trim());
    return i == -1 ? kRoleOrder.length : i;
  }

  final sorted = [...raw];
  sorted.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : roleLabel(a).compareTo(roleLabel(b));
  });
  return sorted;
}

/// State of a live "is this already taken?" lookup for one field.
enum _Availability {
  /// Nothing to say yet -- field empty, malformed, or the answer went stale.
  idle,
  checking,
  free,
  taken,
}

// the main widget for the signup screen. stateful because things gonna change
class SignUpScreen extends StatefulWidget {
  /// [authService] and [addressService] are injectable purely so tests can
  /// drive the lookups without a live Supabase, matching ForgotPasswordDialog.
  /// Production callers leave them null.
  const SignUpScreen({super.key, this.authService, this.addressService});

  final AuthService? authService;
  final AddressService? addressService;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

// the actual brain of the screen. holds all the messy state
class _SignUpScreenState extends State<SignUpScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();
  late final AddressService _addressService =
      widget.addressService ?? AddressService();
  final PageController _pageController = PageController(); // controls which step we on
  int _currentPage = 0; // which page we at right now, starts at 0 like normal people
  final int _totalSteps = 4; // 4 steps total, dili ta pwede make it less

  // all the text controllers, one for every field the user has to fill up
  // importente kaayo -- dispose all of these later or you get memory leak forever
  final TextEditingController _firstNameController       = TextEditingController();
  final TextEditingController _lastNameController        = TextEditingController();
  // Address is split in two. Philippine addresses are already structured --
  // house/street/purok, then barangay, municipality, province -- and only the
  // first half is genuinely free text. The second half comes from a list, so it
  // is typed once, spelt consistently, and picked in three keystrokes.
  // The two are joined back into one string for user_info.address, so nothing
  // downstream changes.
  final TextEditingController _streetController          = TextEditingController();
  final TextEditingController _barangayController        = TextEditingController();
  final FocusNode _barangayFocus                         = FocusNode();
  final TextEditingController _idController              = TextEditingController();
  final TextEditingController _emailController           = TextEditingController();
  final TextEditingController _departmentController      = TextEditingController();
  
  // Null until chosen, so the dropdown shows its "Employment Status" hint the
  // way Role and Department do. Only ever asked for roles whose name does not
  // already state it -- see _employmentIsAskable.
  String? _selectedEmploymentStatus;
  final TextEditingController _roleController            = TextEditingController();
  final TextEditingController _passwordController        = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // booleans that track whether the password is strong enough to survive
  bool _obscurePassword        = true;  // hide the password by default, ayaw show it
  bool _obscureConfirmPassword = true;  // same for the confirm field
  bool _hasAcceptedAgreements  = false; // user must agree or they cant proceed, dili pwede skip
  bool _hasScrolledToBottom    = false; // user must scroll to bottom of NDA/DPA first
  bool _reviewSummaryExpanded   = true;  // collapse it to give the NDA room to breathe
  bool _has8Chars              = false; // password length check
  bool _hasUpper               = false; // must have uppercase, murag shouting is required
  bool _hasNumber              = false; // at least one number, basin they forget
  bool _hasSpecial             = false; // special chars, like !@#, the weird ones
  bool _passwordsMatch         = false; // both passwords must be the same, obviously
  bool _isLoading              = false; // true when we waiting for server, patience ra
  String? _errorMessage;               // holds the error text if something went wrong

  // ── live "already taken?" checks ─────────────────────────────────────────
  // Deliberately the same idea as the password checklist further down: answer
  // the question while the user is still looking at the field. Before this, the
  // only duplicate check ran at the final Register press -- so you typed a
  // name, an ID, an email, a password, read two legal agreements, ticked the
  // box, and THEN got told the ID belonged to someone else, two steps back.
  static const Duration _availabilityDebounce = Duration(milliseconds: 600);
  Timer? _nameDebounce;
  Timer? _idDebounce;
  Timer? _emailDebounce;
  _Availability _nameStatus = _Availability.idle;
  _Availability _idStatus = _Availability.idle;
  _Availability _emailStatus = _Availability.idle;
  bool _isCheckingStep = false; // Continue pressed, confirming with the server

  // Loaded once on open and filtered in memory, so suggestions keep up with
  // typing. Empty when the list could not be fetched, in which case the field
  // behaves as the plain free-text box it used to be.
  List<AddressLocation> _locations = [];
  AddressLocation? _selectedLocation;

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
    // Same trip as the dropdowns above. fetchLocations never throws -- an empty
    // list just means the address field stays free text.
    final locations = await _addressService.fetchLocations();
    if (mounted) {
      setState(() {
        _departments = depts;        // store departments
        _statusrole = sortRoles(roles); // most-registered role first
        _locations = locations;      // barangay suggestions
        _isFetchingMetadata = false; // done loading, dropdowns can show now
      });
    }
  }

  // cleanup all the controllers when screen die, very importente or memory go boom
  @override
  void dispose() {
    // Pending debounces would otherwise fire into a dead State.
    _nameDebounce?.cancel();
    _idDebounce?.cancel();
    _emailDebounce?.cancel();
    _pageController.dispose();
    _firstNameController.dispose(); _lastNameController.dispose();
    _streetController.dispose(); _barangayController.dispose();
    _barangayFocus.dispose();
    _idController.dispose();
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
      // Any non-alphanumeric, whitespace aside. The old list left out - _ + =
      // ; [ ] ~ / so a password like "Passw0rd_" was told it had no special
      // character, with no way to work out why.
      _hasSpecial = value.contains(RegExp(r'[^A-Za-z0-9\s]'));
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

  // live errorText under the email field. delegates to the shared rules so the
  // registration screen and both SAO Admin screens agree on what a valid
  // address is.
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return null; // empty is handled elsewhere, skip
    return IdentityValidator.validateEmail(value);
  }

  // ── what the chosen role implies ─────────────────────────────────────────

  bool get _isSaoRole => _roleController.text.toUpperCase().contains('SAO');

  /// SAO personnel are office staff, not students or faculty, so their number
  /// is a Staff ID. Same wording as Personnel Management, so the same field is
  /// not called two different things in two places.
  String get _idLabel => _isSaoRole
      ? IdentityValidator.staffIdLabel
      : IdentityValidator.defaultIdLabel;

  /// Whether employment status is still a real question.
  ///
  /// It is a separate column, but for two roles it is the same fact twice:
  /// FULL-TIME and PART-TIME already state it. Asking again let the two
  /// disagree -- role FULL-TIME with employment Part-Time -- and that is not
  /// cosmetic: the "Assign Second Dept" action in User Management is gated on
  /// employment_status, so a contradiction there hands out an ability the role
  /// was not supposed to have. Derived where the role settles it, asked only
  /// where it genuinely does not.
  bool get _employmentIsAskable {
    final role = _roleController.text.toUpperCase().trim();
    return role == 'DEPARTMENT_HEAD' ||
        role == 'DEPARTMENT-HEAD' ||
        role == 'DEAN';
  }

  String get _resolvedEmploymentStatus {
    final role = _roleController.text.toUpperCase().trim();
    if (role == 'FULL-TIME') return 'Full-Time';
    if (role == 'PART-TIME') return 'Part-Time';
    if (_employmentIsAskable) return _selectedEmploymentStatus ?? 'Full-Time';
    // SAO office staff. The column is only ever read for the instructor
    // second-department feature, so this value is inert for them.
    return 'Full-Time';
  }

  // ── availability lookups ─────────────────────────────────────────────────

  /// Restarts the debounce for the first/last name pair.
  void _scheduleNameCheck() {
    // Any edit invalidates the previous answer, so drop it immediately rather
    // than leaving a stale green tick under a name that just changed.
    setState(() => _nameStatus = _Availability.idle);
    _nameDebounce?.cancel();
    _nameDebounce = Timer(_availabilityDebounce, _checkNameAvailability);
  }

  void _scheduleIdCheck() {
    setState(() => _idStatus = _Availability.idle);
    _idDebounce?.cancel();
    _idDebounce = Timer(_availabilityDebounce, _checkIdAvailability);
  }

  void _scheduleEmailCheck() {
    setState(() => _emailStatus = _Availability.idle);
    _emailDebounce?.cancel();
    _emailDebounce = Timer(_availabilityDebounce, _checkEmailAvailability);
  }

  Future<void> _checkNameAvailability() async {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    // Only the PAIR can clash -- sharing just a first or just a last name is
    // allowed -- so there is nothing to ask until both halves are well-formed.
    if (IdentityValidator.validateName(first, 'First name') != null ||
        IdentityValidator.validateName(last, 'Last name') != null) {
      return;
    }
    setState(() => _nameStatus = _Availability.checking);
    final result = await _authService.checkIdentityAvailable(
      firstName: first,
      lastName: last,
    );
    // The user may have typed on while this was in flight. Applying a stale
    // answer would label the wrong name.
    if (!mounted ||
        _firstNameController.text.trim() != first ||
        _lastNameController.text.trim() != last) {
      return;
    }
    setState(() => _nameStatus =
        result.isAvailable ? _Availability.free : _Availability.taken);
  }

  Future<void> _checkIdAvailability() async {
    final id = _idController.text.trim();
    if (IdentityValidator.validateUniversityId(id) != null) return;
    setState(() => _idStatus = _Availability.checking);
    final result = await _authService.checkIdentityAvailable(universityId: id);
    if (!mounted || _idController.text.trim() != id) return;
    setState(() => _idStatus =
        result.isAvailable ? _Availability.free : _Availability.taken);
  }

  Future<void> _checkEmailAvailability() async {
    final email = _emailController.text.trim();
    if (IdentityValidator.validateEmail(email) != null) return;
    setState(() => _emailStatus = _Availability.checking);
    final result = await _authService.checkIdentityAvailable(email: email);
    if (!mounted || _emailController.text.trim() != email) return;
    setState(() => _emailStatus =
        result.isAvailable ? _Availability.free : _Availability.taken);
  }

  /// Server confirmation for the fields the current step owns, run on Continue.
  ///
  /// The debounced lookups above usually have the answer already, but a fast
  /// typist can press Continue before one lands. Returns the conflict, or null
  /// when the step is clear.
  Future<IdentityCheckResult?> _confirmStepAvailability() async {
    if (_currentPage != 0 && _currentPage != 1) return null;

    setState(() => _isCheckingStep = true);
    final IdentityCheckResult result = _currentPage == 0
        ? await _authService.checkIdentityAvailable(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
          )
        : await _authService.checkIdentityAvailable(
            email: _emailController.text.trim(),
            universityId: _idController.text.trim(),
          );
    if (!mounted) return null;

    setState(() {
      _isCheckingStep = false;
      if (_currentPage == 0) {
        _nameStatus =
            result.isAvailable ? _Availability.free : _Availability.taken;
      } else if (result.field == IdentityField.universityId) {
        _idStatus = _Availability.taken;
      } else if (result.field == IdentityField.email) {
        _emailStatus = _Availability.taken;
      } else {
        // The check reports one field at a time, so a clean answer clears both.
        _idStatus = _Availability.free;
        _emailStatus = _Availability.free;
      }
    });
    return result.isAvailable ? null : result;
  }

  // validate the current step before user allowed to go to next step
  // returns error message string if something wrong, null if all good
  String? _validateCurrentStep() {
    switch (_currentPage) {
      case 0: // Who you are: role, name, address
        // Role is asked first because it decides what step 2 even contains --
        // an SAO applicant should never be shown a department picker.
        if (_roleController.text.trim().isEmpty) {
          return 'Please choose what you are registering as';
        }
        // IdentityValidator owns the name rules, because the name is half of a
        // uniqueness key: first + last together must be unique, so both fields
        // have to be cleaned and checked the same way everywhere.
        final nameError = IdentityValidator.validateFormat(
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
        );
        if (nameError != null) return nameError;
        if (_streetController.text.trim().isEmpty) {
          return 'House number / street is required';
        }
        if (_barangayController.text.trim().isEmpty) {
          return 'Barangay is required';
        }
        return null;
      case 1: // What the role needs: ID, email, and a department if applicable
        final academicError = IdentityValidator.validateFormat(
          email: _emailController.text,
          universityId: _idController.text,
          idLabel: _idLabel,
        );
        if (academicError != null) return academicError;
        if (!_isSaoRole && _departmentController.text.trim().isEmpty) {
          return 'Please select a department'; // SAO users dili need department, lucky them
        }
        if (_employmentIsAskable && _selectedEmploymentStatus == null) {
          return 'Please select an employment status';
        }
        return null;
      default:
        return null; // other steps have no backend validation here, bahala na
    }
  }

  // called when user press Continue button. validate first, then move to next page.
  // on the last step, submit the form instead of going forward
  Future<void> _onContinue() async {
    if (_currentPage < _totalSteps - 1) {
      final error = _validateCurrentStep(); // check if current step is filled properly
      if (error != null) {
        setState(() => _errorMessage = error); // show the error to the poor user
        return;
      }
      setState(() => _errorMessage = null); // clear old error if we passed

      // Do not carry a known duplicate forward into three more steps.
      final conflict = await _confirmStepAvailability();
      if (!mounted) return;
      if (conflict != null) {
        await showDuplicateWarningDialog(
          context,
          message: conflict.error!,
          field: conflict.field,
        );
        return;
      }

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
    // Trimmed on the way out. AuthService cleans these again -- it has to,
    // since it is also reachable from elsewhere -- but sending raw text means
    // the value the user is told about and the value that gets stored differ.
    final result = await _authService.signUp(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      address: _composedAddress,
      universityId: _idController.text.trim(),
      institutionalEmail: _emailController.text.trim(),
      departmentName: _departmentController.text.trim(),
      roleName: _roleController.text.trim(),
      password: _passwordController.text,
      employmentStatus: _resolvedEmploymentStatus,
    );

    if (!mounted) return; // widget might be gone by now, ayaw crash
    setState(() => _isLoading = false); // done loading, show result

    if (result.success) {
      _showPendingApprovalDialog(); // success! tell user to wait for admin blessing
    } else if (result.conflictField != null) {
      // Already in the database. That is not a typo the user can fix by
      // squinting at red text, so it gets a modal they have to dismiss.
      await showDuplicateWarningDialog(
        context,
        message: result.error!,
        field: result.conflictField,
      );
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
    // Once we know a value belongs to somebody else, there is no point letting
    // them press Continue to be told again.
    if (_currentPage == 0 && _nameStatus == _Availability.taken) canProceed = false;
    if (_currentPage == 1 &&
        (_idStatus == _Availability.taken || _emailStatus == _Availability.taken)) {
      canProceed = false;
    }
    final bool busy = _isLoading || _isCheckingStep;

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

                    // The step pages. Height was pinned at 520 regardless of the
                    // device; taller phones wasted the space and the review step
                    // had to cram a summary, two agreements and a checkbox into
                    // it. Never goes BELOW 520, so short screens behave exactly
                    // as before and keep scrolling.
                    SizedBox(
                      height: math.max(520.0, constraints.maxHeight - 140),
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
                                onPressed: busy ? null : _onBack, // disabled while loading
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
                              onPressed: (canProceed && !busy) ? _onContinue : null, // disabled if cant proceed or loading
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.textInverted,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: busy
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)) // spinning wheel of hope
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
    return _scrollableStep(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Personal Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          // First question on the form, because the answer decides which fields
          // step 2 shows at all.
          _buildDropdownField<String>(
            hint: _isFetchingMetadata ? 'Loading...' : 'I am registering as',
            icon: Icons.work_outline,
            value: _roleController.text.isEmpty ? null : _roleController.text,
            items: _statusrole
                .map((r) => DropdownMenuItem(value: r, child: Text(roleLabel(r))))
                .toList(),
            onChanged: (_isLoading || _isFetchingMetadata)
                ? null
                : (val) => setState(() {
                      _roleController.text = val!;
                      // SAO staff have no department, so anything already
                      // chosen would be submitted for a field they never saw.
                      if (_isSaoRole) _departmentController.text = '';
                    }),
          ),
          const SizedBox(height: 16),
          _buildInput(
            controller: _firstNameController, hint: 'First Name', icon: Icons.person_outline,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.givenName],
            onChanged: (_) => _scheduleNameCheck(),
            // Only complains once there is something to complain about, so the
            // form does not open covered in red.
            errorText: _touchedError(_firstNameController.text,
                () => IdentityValidator.validateName(_firstNameController.text, 'First name')),
          ),
          const SizedBox(height: 16),
          _buildInput(
            controller: _lastNameController, hint: 'Last Name', icon: Icons.person_outline,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.familyName],
            onChanged: (_) => _scheduleNameCheck(),
            errorText: _touchedError(_lastNameController.text,
                () => IdentityValidator.validateName(_lastNameController.text, 'Last name')),
          ),
          // "Juan Cruz is available" / "already registered". Only the pair can
          // clash, so this sits under both fields rather than either one.
          _buildAvailabilityRow(
            _nameStatus,
            freeLabel: '${_firstNameController.text.trim()} ${_lastNameController.text.trim()} is available',
            takenLabel: 'Someone is already registered with this exact name',
          ),
          const SizedBox(height: 16),
          _buildInput(
            controller: _streetController, hint: 'House No. / Street / Purok',
            icon: Icons.home_outlined,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.streetAddressLine1],
            onChanged: (_) => setState(() {}), // keep the preview below in step
          ),
          const SizedBox(height: 16),
          _buildBarangayField(),
        ],
      ),
    );
  }

  /// Wraps a step's fields so they scroll if they do not fit.
  ///
  /// Only for steps built from a plain Column. The review step must not use
  /// this -- it has an Expanded child, and Expanded inside an unbounded-height
  /// scroll view throws.
  Widget _scrollableStep(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: child,
    );
  }

  // step 2: ask for university ID, institutional email, role, and department
  // SAO role users skip the department field -- they too special for that
  Widget _buildAcademicStep() {
    return _scrollableStep(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Heading follows the role: an SAO applicant is not filling in
          // academic details.
          Text(
            _isSaoRole ? 'Personnel Details' : 'Academic Information',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Registering as ${roleLabel(_roleController.text)}.',
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          _buildInput(
            controller: _idController, hint: _idLabel, icon: Icons.badge_outlined,
            onChanged: (_) => _scheduleIdCheck(),
            errorText: _touchedError(
                _idController.text,
                () => IdentityValidator.validateUniversityId(_idController.text,
                    label: _idLabel)),
          ),
          _buildAvailabilityRow(
            _idStatus,
            freeLabel: 'This $_idLabel is available',
            takenLabel: 'This $_idLabel is already registered',
          ),
          const SizedBox(height: 16),
          _buildInput(
            controller: _emailController, hint: 'Institutional Email', icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onChanged: (_) => _scheduleEmailCheck(),
            errorText: _validateEmail(_emailController.text),
          ),
          _buildAvailabilityRow(
            _emailStatus,
            freeLabel: 'This email is available',
            takenLabel: 'This email is already registered',
          ),
          // Department: everyone except SAO office staff.
          if (!_isSaoRole) ...[
            const SizedBox(height: 16),
            _buildDropdownField<String>(
              hint: _isFetchingMetadata ? 'Loading...' : 'Select Department',
              icon: Icons.apartment_outlined,
              value: _departmentController.text.isEmpty ? null : _departmentController.text,
              items: _departments
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (_isLoading || _isFetchingMetadata)
                  ? null
                  : (val) => setState(() => _departmentController.text = val!),
            ),
          ],
          // Employment status only where the role does not already state it.
          // Instructors picked Resident / Non-Resident as part of their role.
          if (_employmentIsAskable) ...[
            const SizedBox(height: 16),
            _buildDropdownField<String>(
              hint: 'Employment Status',
              icon: Icons.schedule_outlined,
              value: _selectedEmploymentStatus,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'Full-Time', child: Text('Resident (Full-Time)')),
                DropdownMenuItem(value: 'Part-Time', child: Text('Non-Resident (Part-Time)')),
              ],
              onChanged: _isLoading
                  ? null
                  : (val) => setState(() => _selectedEmploymentStatus = val!),
            ),
          ],
        ],
      ),
    );
  }

  // step 3: create the password. many rules. must be strong. no shortcuts, ayaw
  Widget _buildSecurityStep() {
    return _scrollableStep(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Create Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          _buildInput(
            controller: _passwordController, hint: 'Password', icon: Icons.lock_outline,
            autofillHints: const [AutofillHints.newPassword],
            isPass: true, state: _obscurePassword,
            toggle: () => setState(() => _obscurePassword = !_obscurePassword), // toggle show/hide
            onChanged: _validatePassword, // check rules on every keypress
          ),
          const SizedBox(height: 12),
          // show the password requirements checklist
          _buildRequirementRow('At least 8 characters', _has8Chars),
          _buildRequirementRow('One uppercase letter', _hasUpper),
          _buildRequirementRow('One number', _hasNumber),
          _buildRequirementRow('One special character (! @ # - _ …)', _hasSpecial),
          const SizedBox(height: 16),
          _buildInput(
            controller: _confirmPasswordController, hint: 'Confirm Password', icon: Icons.lock_reset,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
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
    // Safe to scroll now that the agreements have moved to their own page.
    // Previously this step held an Expanded for the agreements pane, and
    // Expanded inside an unbounded-height scroll view throws -- which is why
    // steps 1-3 were wrapped and this one deliberately was not.
    return _scrollableStep(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Review & Terms', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ),
              // The summary and the agreements share one screen, and on a
              // 640dp phone that leaves the NDA about two lines tall -- not
              // something anyone can read, let alone consent to. Collapsing the
              // summary hands those ~200px to the agreements pane.
              TextButton.icon(
                onPressed: () => setState(
                    () => _reviewSummaryExpanded = !_reviewSummaryExpanded),
                icon: Icon(
                  _reviewSummaryExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                ),
                label: Text(_reviewSummaryExpanded ? 'Hide' : 'Show'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_reviewSummaryExpanded)
            _buildReviewSummary()
          else
            _buildCollapsedSummary(),
          const SizedBox(height: 16),
          _buildAgreementsTile(),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderHairline),
            ),
            child: CheckboxListTile(
              title: const Text('I agree to the NDA and DPA', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
              subtitle: !_hasScrolledToBottom
                  ? const Text('Read the agreement above first',
                      style: TextStyle(fontSize: 12, color: AppColors.error))
                  : null,
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
    // Mobile keyboard behaviour. None of this was set before, so the email
    // field came up on a keyboard with no visible @ key, nothing autofilled,
    // and every field needed a manual tap because there was no Next action.
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.next,
    List<String>? autofillHints,
    TextCapitalization textCapitalization = TextCapitalization.none,
    FocusNode? focusNode, // supplied by RawAutocomplete for the barangay field
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: state ?? false, // hide text if state is true, else show it
      onChanged: onChanged,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      textCapitalization: textCapitalization,
      // TextInputAction.next only draws the key; moving focus is on us.
      onSubmitted: textInputAction == TextInputAction.next
          ? (_) => FocusScope.of(context).nextFocus()
          : null,
      enabled: !_isLoading, // disable all inputs while loading, ayaw let user spam
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
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

  /// A dropdown styled identically to [_buildInput].
  ///
  /// The three dropdowns used to be bare DropdownButtons inside a Container:
  /// no prefix icon, a different inner height, a different chevron, and no
  /// error slot -- so next to the text fields they read as a different kind of
  /// control on a different form. DropdownButtonFormField accepts the same
  /// InputDecoration, so there is now exactly one field appearance on this
  /// screen.
  Widget _buildDropdownField<T>({
    required String hint,
    required IconData icon,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    OutlineInputBorder border(Color colour, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colour, width: width),
        );

    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded,
          color: AppColors.textSecondary, size: 22),
      hint: Text(hint,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 15),
          overflow: TextOverflow.ellipsis),
      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        enabledBorder: border(AppColors.borderHairline),
        focusedBorder: border(AppColors.primary, 1.5),
        disabledBorder: border(AppColors.borderHairline),
        errorBorder: border(AppColors.error),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  /// The single string written to user_info.address.
  ///
  /// Prefers the picked location's canonical label over whatever is sitting in
  /// the text field, so "lamacan" becomes "Lamacan, Argao, Cebu". Falls back to
  /// the raw typing for anywhere not on the list.
  String get _composedAddress => AddressService.compose(
        _streetController.text,
        _selectedLocation?.label ?? _barangayController.text,
      );

  /// Barangay picker: type-to-search over the loaded list, free text accepted.
  ///
  /// RawAutocomplete rather than Autocomplete so the field keeps using
  /// _buildInput and therefore the exact same decoration as every other input
  /// on this screen -- the picker should not look like a different app.
  Widget _buildBarangayField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RawAutocomplete<AddressLocation>(
          textEditingController: _barangayController,
          focusNode: _barangayFocus,
          displayStringForOption: (location) => location.label,
          optionsBuilder: (value) =>
              AddressService.search(_locations, value.text),
          onSelected: (location) => setState(() => _selectedLocation = location),
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            return _buildInput(
              controller: controller,
              focusNode: focusNode,
              hint: 'Barangay, Municipality, Province',
              icon: Icons.location_on_outlined,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {
                // Typing after choosing means the choice no longer matches what
                // is on screen, so drop it and fall back to the raw text.
                _selectedLocation = null;
              }),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderHairline),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textPrimary.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, thickness: 1, color: AppColors.borderHairline),
                    itemBuilder: (context, index) {
                      final location = options.elementAt(index);
                      return InkWell(
                        onTap: () => onSelected(location),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  location.label,
                                  style: const TextStyle(
                                      fontSize: 14, color: AppColors.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        // Says out loud that the list is not a wall: staff from a town that is
        // not seeded can type their own and carry on.
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            _locations.isEmpty
                ? 'Type your barangay, municipality and province.'
                : 'Pick from the list, or type it in full if it is not there.',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }

  /// An error for a field the user has actually typed in.
  ///
  /// Returns null while the field is empty, so opening the form does not paint
  /// every field red before anyone has touched it. Empty-but-required is still
  /// caught by _validateCurrentStep when Continue is pressed.
  String? _touchedError(String value, String? Function() validate) {
    if (value.trim().isEmpty) return null;
    return validate();
  }

  /// The "already taken?" line under an identity field.
  ///
  /// Same icon size, text size and colours as _buildRequirementRow below, so
  /// this and the password checklist read as one idea rather than two.
  Widget _buildAvailabilityRow(
    _Availability status, {
    required String freeLabel,
    required String takenLabel,
  }) {
    if (status == _Availability.idle) return const SizedBox.shrink();

    final bool taken = status == _Availability.taken;
    final bool checking = status == _Availability.checking;
    final Color colour = checking
        ? AppColors.textSecondary
        : (taken ? AppColors.error : AppColors.success);

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(
        children: [
          if (checking)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.textTertiary),
            )
          else
            Icon(taken ? Icons.error_outline : Icons.check_circle, size: 14, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              checking ? 'Checking…' : (taken ? takenLabel : freeLabel),
              style: TextStyle(fontSize: 12, color: colour),
            ),
          ),
        ],
      ),
    );
  }

  /// Read-back of everything entered, shown above the agreements.
  ///
  /// The step has always been called "Review & Terms" but showed only the
  /// agreements, so nobody ever saw their own email again before submitting.
  /// One mistyped character there produces an account that can never receive
  /// its approval notice or a password reset -- which has already happened in
  /// this database. Each row taps back to the step that owns it.
  /// Entry point to the agreements, which live on their own full screen.
  ///
  /// Shows whether they have been read, because the agree checkbox below stays
  /// locked until they have and an unexplained disabled checkbox is the kind of
  /// dead end people abandon a signup over.
  Widget _buildAgreementsTile() {
    final bool read = _hasScrolledToBottom;

    return InkWell(
      onTap: _openAgreements,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: read ? AppColors.success : AppColors.borderSubtle,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            AppleIconBadge(
              icon: read ? Icons.check_rounded : Icons.description_outlined,
              color: read ? AppColors.success : AppColors.primary,
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NDA and Data Privacy Agreement',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Read state is carried by the icon and border rather than by
                  // colouring this line: AppColors.success is 4.36:1 on white,
                  // under AA for text this size.
                  Text(
                    read
                        ? 'Read — tap to view again'
                        : 'Tap to read. Required before you can agree.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  /// Opens the agreements and records whether the reader reached the end.
  Future<void> _openAgreements() async {
    final read = await showAgreementReader(
      context,
      alreadyRead: _hasScrolledToBottom,
    );
    if (!mounted) return;
    setState(() => _hasScrolledToBottom = read);
  }

  /// One-line stand-in shown while the summary is collapsed.
  ///
  /// Hiding the details should not hide *what* was entered. Name and email are
  /// the two fields a typo actually costs you -- a wrong email produces an
  /// account that can never receive its approval notice or a password reset --
  /// so they stay visible, and the whole strip taps back open.
  Widget _buildCollapsedSummary() {
    final String fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
    final String email = _emailController.text.trim();
    final String line =
        [fullName, email].where((v) => v.isNotEmpty).join('  ·  ');

    return GestureDetector(
      onTap: () => setState(() => _reviewSummaryExpanded = true),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                line.isEmpty ? 'Tap to review your details' : line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            const Icon(Icons.unfold_more_rounded,
                size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewSummary() {
    final bool isSao = _isSaoRole;
    final String fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          // Role lives on step 1 now, so its row jumps back there.
          _buildSummaryRow('Registering as', roleLabel(_roleController.text), 0),
          _buildSummaryRow('Name', fullName, 0),
          _buildSummaryRow('Address', _composedAddress, 0),
          _buildSummaryRow(_idLabel, _idController.text.trim(), 1),
          _buildSummaryRow('Email', _emailController.text.trim(), 1),
          if (!isSao) _buildSummaryRow('Department', _departmentController.text.trim(), 1),
          if (!isSao)
            _buildSummaryRow(
              'Employment',
              _resolvedEmploymentStatus == 'Full-Time'
                  ? 'Resident (Full-Time)'
                  : 'Non-Resident (Part-Time)',
              // Derived from the role for instructors, so that row points back
              // at step 1 where the role was chosen.
              _employmentIsAskable ? 1 : 0,
            ),
        ],
      ),
    );
  }

  /// One line of the review card. Tapping jumps back to [stepIndex] so a typo
  /// costs one tap instead of two Back presses.
  Widget _buildSummaryRow(String label, String value, int stepIndex) {
    return InkWell(
      onTap: _isLoading
          ? null
          : () => _pageController.animateToPage(
                stepIndex,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '--' : value,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.edit_outlined, size: 14, color: AppColors.textTertiary),
          ],
        ),
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
          Icon(isMet ? Icons.check_circle : Icons.circle_outlined, size: 14, color: isMet ? AppColors.success : AppColors.textTertiary), // green check or grey circle
          const SizedBox(width: 8),
          // Expanded, because a bare Text in a Row overflows the moment a label
          // gets longer than the screen -- which is exactly what happened when
          // the special-character rule started listing examples.
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: isMet ? AppColors.success : AppColors.textSecondary)),
          ),
        ],
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
          // Naming the address back to them is a last chance to notice a typo
          // in the one field that everything later depends on -- approval
          // notices and password resets both go there.
          content: Text(
            'Your account is waiting for an SAO Administrator to approve it. '
                'You will be able to log in once that happens.\n\n'
                'Notifications will be sent to ${_emailController.text.trim()}. '
                'If you have not heard anything after a few working days, '
                'please contact the SAO office.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.45),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () { Navigator.of(context).pop(); Navigator.of(context).pop(); }, // close dialog then close signup screen, go back to login
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