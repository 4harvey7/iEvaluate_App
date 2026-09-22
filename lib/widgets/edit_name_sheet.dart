// The "edit first / last name" bottom sheet shared by the Instructor, Gatherer
// and Department Head settings screens.
//
// It used to be pasted into each of those screens as a StatefulBuilder, and
// every copy had the same three faults around the save:
//
//   1. It closed itself with `navigator.pop()`. That pops whatever route is on
//      top -- so if the sheet had already been swiped away while the save was
//      still in flight, it popped the SETTINGS SCREEN instead and threw the
//      user back to the dashboard mid-edit.
//   2. It called setSheetState() / setState() after the await without checking
//      the thing was still alive ("setState() called after dispose()").
//   3. Its TextEditingControllers were created on every open and never
//      disposed.
//
// Being a real StatefulWidget fixes 2 and 3 for free; 1 is handled in _save().

import 'package:flutter/material.dart';
import '../core/services/auth_service.dart';
import '../theme/app_colors.dart';

/// Opens the edit-name sheet pre-filled with [firstName] and [lastName].
///
/// [onSave] does the actual write (normally `AuthService.updateProfile`).
/// [onSaved] runs once it succeeds, with the trimmed names, so the caller can
/// refresh its own profile card -- the caller is responsible for its own
/// `mounted` check, since the sheet can outlive the screen that opened it.
Future<void> showEditNameSheet({
  required BuildContext context,
  required String firstName,
  required String lastName,
  required Future<AuthResult> Function(String firstName, String lastName) onSave,
  required void Function(String firstName, String lastName) onSaved,
  String title = 'Edit Profile',
}) {
  // The "Profile updated successfully!" bar from a previous save is drawn by
  // the outer Scaffold, on top of this sheet, right over the Save button. Edit
  // again straight away and Save was untappable until it timed out.
  ScaffoldMessenger.of(context).removeCurrentSnackBar();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // allows sheet to resize when keyboard appears
    backgroundColor: Colors.transparent,
    builder: (_) => EditNameSheet(
      title: title,
      firstName: firstName,
      lastName: lastName,
      onSave: onSave,
      onSaved: onSaved,
    ),
  );
}

class EditNameSheet extends StatefulWidget {
  const EditNameSheet({
    super.key,
    required this.title,
    required this.firstName,
    required this.lastName,
    required this.onSave,
    required this.onSaved,
  });

  final String title;
  final String firstName;
  final String lastName;
  final Future<AuthResult> Function(String firstName, String lastName) onSave;
  final void Function(String firstName, String lastName) onSaved;

  @override
  State<EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<EditNameSheet> {
  late final TextEditingController _firstController =
      TextEditingController(text: widget.firstName);
  late final TextEditingController _lastController =
      TextEditingController(text: widget.lastName);
  bool _isSaving = false; // prevent double-tap spam while saving

  @override
  void dispose() {
    _firstController.dispose();
    _lastController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Everything that needs a BuildContext is taken BEFORE the await -- the
    // sheet may be gone by the time the save comes back.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sheetRoute = ModalRoute.of(context);
    final String firstName = _firstController.text.trim();
    final String lastName = _lastController.text.trim();

    setState(() => _isSaving = true);

    AuthResult result;
    try {
      result = await widget.onSave(firstName, lastName);
    } catch (e) {
      result = AuthResult(success: false, error: '$e');
    }

    if (result.success) {
      widget.onSaved(firstName, lastName);
      // Close THIS sheet, and only if it is still the one on top. A bare
      // navigator.pop() here is what used to close the Settings screen when
      // the sheet had been dismissed during the save.
      if (sheetRoute != null && sheetRoute.isCurrent) navigator.pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('Profile updated successfully!'),
        backgroundColor: AppColors.success,
      ));
    } else {
      if (mounted) setState(() => _isSaving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(result.error ?? 'Profile update failed. Please try again.'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      // Push sheet up when keyboard is open so the fields are visible
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                // Close button — for when the user change their mind
                IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please ensure your name exactly matches your official school records. This name is used for scanner validation and official workflow reports. Change it wisely.',
                      style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildInput(label: 'First Name', controller: _firstController, icon: Icons.person),
            const SizedBox(height: 16),
            _buildInput(label: 'Last Name', controller: _lastController, icon: Icons.person_outline),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                // Disable button while saving to avoid double-click disaster
                onPressed: _isSaving ? null : _save,
                // Show spinner while saving, text when idle
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Changes', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Same field styling the settings screens use for their other forms.
  Widget _buildInput({required String label, required IconData icon, required TextEditingController controller}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      ),
    );
  }
}
