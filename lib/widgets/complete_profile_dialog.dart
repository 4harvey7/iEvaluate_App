// lib/widgets/complete_profile_dialog.dart
//
// "Complete your information" -- asks a signed-in user for whichever of their
// ID and address is missing from user_info, and saves it.
//
// Only the missing fields are shown. The address is asked for the same way
// registration asks for it (street / purok, then a barangay picked from the
// seeded list or typed) and composed into the same single string, so a profile
// completed here is indistinguishable from one created at signup.
import 'package:flutter/material.dart';

import '../core/services/address_service.dart';
import '../core/services/identity_validator.dart';
import '../core/services/profile_completion_service.dart';
import '../theme/app_colors.dart';
import 'apple_ui.dart';
import 'controller_disposer.dart';

/// Shows the dialog. Resolves to true once every missing field is saved, false
/// when the user chose "Later" (they are asked again at the next login).
///
/// [isSaoRole] only changes wording: SAO personnel call the same
/// `university_id` column a Staff ID, as registration and Personnel
/// Management do.
Future<bool> showCompleteProfileDialog(
  BuildContext context, {
  required String userId,
  required ProfileCompletionStatus status,
  bool isSaoRole = false,
  ProfileCompletionService? service,
  AddressService? addressService,
}) async {
  // Owned by ControllerDisposer rather than disposed after showDialog returns:
  // that Future completes before the exit animation, while the TextFields are
  // still mounted -- the use-after-dispose crash controller_disposer.dart fixes.
  final idController = TextEditingController();
  final streetController = TextEditingController();
  final barangayController = TextEditingController();
  final barangayFocus = FocusNode();

  final result = await showDialog<bool>(
    context: context,
    // Tapping outside must not lose what was typed; "Later" is the way out.
    barrierDismissible: false,
    builder: (_) => ControllerDisposer(
      controllers: [idController, streetController, barangayController, barangayFocus],
      child: CompleteProfileDialog(
        userId: userId,
        initialStatus: status,
        isSaoRole: isSaoRole,
        service: service ?? ProfileCompletionService(),
        addressService: addressService ?? AddressService(),
        idController: idController,
        streetController: streetController,
        barangayController: barangayController,
        barangayFocus: barangayFocus,
      ),
    ),
  );
  return result ?? false;
}

class CompleteProfileDialog extends StatefulWidget {
  const CompleteProfileDialog({
    super.key,
    required this.userId,
    required this.initialStatus,
    required this.isSaoRole,
    required this.service,
    required this.addressService,
    required this.idController,
    required this.streetController,
    required this.barangayController,
    required this.barangayFocus,
  });

  final String userId;
  final ProfileCompletionStatus initialStatus;
  final bool isSaoRole;
  final ProfileCompletionService service;
  final AddressService addressService;
  final TextEditingController idController;
  final TextEditingController streetController;
  final TextEditingController barangayController;
  final FocusNode barangayFocus;

  @override
  State<CompleteProfileDialog> createState() => _CompleteProfileDialogState();
}

class _CompleteProfileDialogState extends State<CompleteProfileDialog> {
  late ProfileCompletionStatus _status = widget.initialStatus;
  bool _saving = false;
  bool _submitted = false; // show "required" errors only after a Save press
  String? _errorMessage;

  List<AddressLocation> _locations = const [];
  AddressLocation? _selectedLocation;

  String get _idLabel => widget.isSaoRole
      ? IdentityValidator.staffIdLabel
      : IdentityValidator.defaultIdLabel;

  @override
  void initState() {
    super.initState();
    if (_status.needsAddress) _loadLocations();
  }

  Future<void> _loadLocations() async {
    // fetchLocations never throws; empty just means free text.
    final locations = await widget.addressService.fetchLocations();
    if (mounted) setState(() => _locations = locations);
  }

  String get _composedAddress => AddressService.compose(
        widget.streetController.text,
        _selectedLocation?.label ?? widget.barangayController.text,
      );

  String? get _idError {
    final text = widget.idController.text;
    if (!_submitted && text.trim().isEmpty) return null;
    return IdentityValidator.validateUniversityId(text, label: _idLabel);
  }

  String? get _streetError {
    if (!_submitted) return null;
    return IdentityValidator.clean(widget.streetController.text).isEmpty
        ? 'House number / street is required'
        : null;
  }

  String? get _barangayError {
    if (!_submitted) return null;
    return IdentityValidator.clean(widget.barangayController.text).isEmpty
        ? 'Barangay is required'
        : null;
  }

  Future<void> _save() async {
    if (_saving) return; // double tap
    setState(() {
      _submitted = true;
      _errorMessage = null;
    });

    final String? formatError = _status.needsId && _idError != null
        ? _idError
        : _status.needsAddress
            ? ProfileCompletionService.validateAddress(
                widget.streetController.text,
                _selectedLocation?.label ?? widget.barangayController.text,
              )
            : null;
    if (formatError != null) {
      setState(() => _errorMessage = formatError);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final result = await widget.service.save(
      userId: widget.userId,
      universityId: _status.needsId ? widget.idController.text : null,
      address: _status.needsAddress ? _composedAddress : null,
      idLabel: _idLabel,
    );
    if (!mounted) return;

    if (result.success) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _errorMessage = result.error;
      // Partly saved: stop asking for what is already stored.
      if (result.addressSaved) _status = _status.copyWith(needsAddress: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back button acts as "Later", except mid-save.
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Row(
          children: [
            AppleIconBadge(
              icon: Icons.assignment_ind_outlined,
              color: AppColors.primary,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Complete your information',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _intro,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (_status.needsId) ...[
                const SizedBox(height: 16),
                _buildInput(
                  key: const Key('completeProfile.id'),
                  controller: widget.idController,
                  hint: _idLabel,
                  icon: Icons.badge_outlined,
                  errorText: _idError,
                  textInputAction: _status.needsAddress
                      ? TextInputAction.next
                      : TextInputAction.done,
                ),
              ],
              if (_status.needsAddress) ...[
                const SizedBox(height: 16),
                _buildInput(
                  key: const Key('completeProfile.street'),
                  controller: widget.streetController,
                  hint: 'House No. / Street / Purok',
                  icon: Icons.home_outlined,
                  errorText: _streetError,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.streetAddressLine1],
                ),
                const SizedBox(height: 12),
                _buildBarangayField(),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                _buildErrorBanner(_errorMessage!),
              ],
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Later'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  key: const Key('completeProfile.save'),
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _intro {
    final missing = [
      if (_status.needsId) 'your $_idLabel',
      if (_status.needsAddress) 'your address',
    ].join(' and ');
    return 'Your profile is missing $missing. Please add '
        '${_status.needsId && _status.needsAddress ? 'them' : 'it'} '
        'so your records are complete.';
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Same field look as the registration screen.
  Widget _buildInput({
    Key? key,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? errorText,
    FocusNode? focusNode,
    TextInputAction textInputAction = TextInputAction.next,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<String>? autofillHints,
    ValueChanged<String>? onChanged,
  }) {
    OutlineInputBorder border(Color colour, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colour, width: width),
        );

    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      enabled: !_saving,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      onChanged: (value) {
        onChanged?.call(value);
        setState(() {}); // refresh live error text
      },
      onSubmitted: textInputAction == TextInputAction.next
          ? (_) => FocusScope.of(context).nextFocus()
          : (_) => _save(),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        errorMaxLines: 3,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        enabledBorder: border(AppColors.borderHairline),
        focusedBorder: border(AppColors.primary, 1.5),
        errorBorder: border(AppColors.error),
        focusedErrorBorder: border(AppColors.error, 1.5),
        disabledBorder: border(AppColors.borderHairline),
      ),
    );
  }

  /// Barangay typeahead over the seeded list, free text accepted -- the same
  /// behaviour as the registration address picker.
  Widget _buildBarangayField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RawAutocomplete<AddressLocation>(
          textEditingController: widget.barangayController,
          focusNode: widget.barangayFocus,
          displayStringForOption: (location) => location.label,
          optionsBuilder: (value) =>
              AddressService.search(_locations, value.text),
          onSelected: (location) =>
              setState(() => _selectedLocation = location),
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            return _buildInput(
              key: const Key('completeProfile.barangay'),
              controller: controller,
              focusNode: focusNode,
              hint: 'Barangay, Municipality, Province',
              icon: Icons.location_on_outlined,
              errorText: _barangayError,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              // Typing after a pick means the pick no longer matches.
              onChanged: (_) => _selectedLocation = null,
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: AppColors.surface,
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 200, maxWidth: 320),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.borderHairline,
                    ),
                    itemBuilder: (context, index) {
                      final location = options.elementAt(index);
                      return InkWell(
                        onTap: () => onSelected(location),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Text(
                            location.label,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
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
}
