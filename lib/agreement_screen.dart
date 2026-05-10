import 'package:flutter/material.dart';
import 'theme/app_colors.dart';

class AgreementScreen {
  static void show({
    required BuildContext context,
    required VoidCallback onAccepted,
  }) {
    bool nda = false;
    bool dpa = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            bool canProceed = nda && dpa;

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
                    const Text(
                      "Before continuing, you must agree to NDA and DPA.",
                      style: TextStyle(fontSize: 13),
                    ),

                    const SizedBox(height: 16),

                    CheckboxListTile(
                      value: nda,
                      onChanged: (v) {
                        setStateModal(() => nda = v ?? false);
                      },
                      title: const Text("I agree to NDA"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                    CheckboxListTile(
                      value: dpa,
                      onChanged: (v) {
                        setStateModal(() => dpa = v ?? false);
                      },
                      title: const Text("I agree to DPA"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                    const SizedBox(height: 10),

                    // 🔁 reload / reset button
                    TextButton.icon(
                      onPressed: () {
                        setStateModal(() {
                          nda = false;
                          dpa = false;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text("Read Again / Reset"),
                    ),
                  ],
                ),
              ),

              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: canProceed
                      ? () {
                    Navigator.pop(context);
                    onAccepted();
                  }
                      : null,
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