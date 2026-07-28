import 'package:flutter/material.dart';
import 'theme/app_colors.dart';

// AgreementScreen -- the legal gatekeeper. user cannot pass without agreeing.
// its not a screen, its a static dialog. we just call show() and it appear like a ghost.
class AgreementScreen {
  // show the NDA and DPA agreement dialog.
  // user must tick BOTH checkboxes or the Accept button stay disabled, wala choice.
  // onAccepted callback is called when user successfully agree to everything.
  static void show({
    required BuildContext context,
    required VoidCallback onAccepted, // called when user finally agree after reading (or not reading) the agreements
  }) {
    bool nda = false; // NDA checkbox state -- starts as unchecked, obviously
    bool dpa = false; // DPA checkbox state -- also unchecked at start

    showDialog(
      context: context,
      barrierDismissible: false, // they CANNOT dismiss by tapping outside, dili pwede escape
      builder: (context) {
        return StatefulBuilder(
          // StatefulBuilder used so dialog can rebuild itself when checkboxes change
          // without needing a whole StatefulWidget, clever lang
          builder: (context, setStateModal) {
            bool canProceed = nda && dpa; // both must be ticked or button stays dead

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Non-Disclosure & Data Privacy Agreement',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 16,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    // tell the user what they need to do, in case they confuse
                    const Text(
                      "Before continuing, you must agree to NDA and DPA.",
                      style: TextStyle(fontSize: 13),
                    ),

                    const SizedBox(height: 16),

                    // NDA checkbox -- ticking this says "yes i will keep my mouth shut"
                    CheckboxListTile(
                      value: nda,
                      onChanged: (v) {
                        setStateModal(() => nda = v ?? false); // update nda state, rebuild dialog
                      },
                      title: const Text("I agree to NDA"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                    // DPA checkbox -- ticking this says "yes i respect data privacy"
                    CheckboxListTile(
                      value: dpa,
                      onChanged: (v) {
                        setStateModal(() => dpa = v ?? false); // update dpa state, rebuild dialog
                      },
                      title: const Text("I agree to DPA"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                    const SizedBox(height: 10),

                    // reload / reset button -- uncheck everything so user can start over
                    // basin they want to re-read before agreeing, or they just click wrong
                    TextButton.icon(
                      onPressed: () {
                        setStateModal(() {
                          nda = false; // uncheck nda
                          dpa = false; // uncheck dpa
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text("Read Again / Reset"),
                    ),
                  ],
                ),
              ),

              actions: [
                // Cancel -- close the dialog without accepting anything, bahala na
                TextButton(
                  onPressed: () => Navigator.pop(context), // just close, no callback fired
                  child: const Text("Cancel"),
                ),
                // Accept -- only works when BOTH checkboxes are ticked, not just one
                ElevatedButton(
                  onPressed: canProceed
                      ? () {
                    Navigator.pop(context); // close the dialog first
                    onAccepted();          // then fire the callback, they agreed
                  }
                      : null, // button disabled when canProceed is false, ayaw enable prematurely
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textInverted,
                  ),
                  child: const Text("Accept"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}