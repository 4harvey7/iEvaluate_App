// lib/widgets/profile_completion_gate.dart
//
// Wraps a role's home screen and, once it is on screen, asks the user to fill
// in a missing ID or address (see complete_profile_dialog.dart).
//
// Hooked in screenForRole (main.dart), the single place every successful login
// passes through, so it runs once per login for every role. Role switching
// (Dept Head -> Instructor view, SAO Admin -> Gatherer view) pushes the other
// screen directly rather than going through screenForRole, so the question is
// not asked again mid-session.
import 'package:flutter/material.dart';

import '../core/services/address_service.dart';
import '../core/services/profile_completion_service.dart';
import 'complete_profile_dialog.dart';

class ProfileCompletionGate extends StatefulWidget {
  const ProfileCompletionGate({
    super.key,
    required this.userId,
    required this.role,
    required this.child,
    this.service,
    this.addressService,
  });

  final String userId;

  /// Raw role string from the `roles` table (e.g. FULL-TIME, SAO_STAFF).
  final String role;
  final Widget child;

  /// Injectable for tests; production leaves these null.
  final ProfileCompletionService? service;
  final AddressService? addressService;

  /// Whether ID and address apply to [role].
  ///
  /// Every account -- instructors, department heads, deans, SAO staff and SAO
  /// admins -- has one `user_info` row with both `university_id` and `address`,
  /// and registration requires both for every role, so none is exempt today.
  /// This is the one place to exempt a role later.
  static bool appliesToRole(String role) => role.trim().isNotEmpty;

  /// Same rule as registration: SAO personnel call their ID a Staff ID.
  static bool isSaoRole(String role) => role.toUpperCase().contains('SAO');

  @override
  State<ProfileCompletionGate> createState() => _ProfileCompletionGateState();
}

class _ProfileCompletionGateState extends State<ProfileCompletionGate> {
  late final ProfileCompletionService _service =
      widget.service ?? ProfileCompletionService();

  /// Set once the check has run, so rebuilds never ask twice.
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: the dashboard should appear first, and showDialog
    // needs a mounted Navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checked || !mounted) return;
    _checked = true;
    if (!ProfileCompletionGate.appliesToRole(widget.role)) return;

    final status = await _service.fetchStatus(widget.userId);
    // Unknown (offline, RLS) or already complete: say nothing.
    if (!mounted || status == null || status.isComplete) return;

    // Only prompt while this route is the one on top, so the dialog does not
    // open over something the user navigated to in the meantime.
    if (ModalRoute.of(context)?.isCurrent == false) return;

    final saved = await showCompleteProfileDialog(
      context,
      userId: widget.userId,
      status: status,
      isSaoRole: ProfileCompletionGate.isSaoRole(widget.role),
      service: _service,
      addressService: widget.addressService,
    );
    if (!mounted || !saved) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Your information has been saved.')),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
