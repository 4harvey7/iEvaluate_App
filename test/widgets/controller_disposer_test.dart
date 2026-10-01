// Regression test for the "edit name twice -> crash" bug. The sheet below
// mirrors the Settings "Edit Profile" sheet; the network call is a delay.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/widgets/controller_disposer.dart';


class Harness extends StatefulWidget {
  const Harness({super.key});
  @override
  State<Harness> createState() => _HarnessState();
}

class _HarnessState extends State<Harness> {
  String _firstName = 'Juan';
  String _lastName = 'Cruz';

  Widget _buildInput({required String label, TextEditingController? controller}) {
    return TextField(controller: controller, decoration: InputDecoration(labelText: label));
  }

  void _showEditProfileSheet() {
    final TextEditingController firstController = TextEditingController(text: _firstName);
    final TextEditingController lastController = TextEditingController(text: _lastName);
    bool isSaving = false;
    bool isSheetOpen = true;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ControllerDisposer(controllers: [firstController, lastController], child: StatefulBuilder(builder: (BuildContext context, StateSetter setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('close'),
                    icon: const Icon(Icons.close),
                    onPressed: isSaving
                        ? null
                        : () {
                            if (isSheetOpen) {
                              isSheetOpen = false;
                              Navigator.of(sheetContext).pop();
                            }
                          },
                  ),
                  _buildInput(label: 'First Name', controller: firstController),
                  _buildInput(label: 'Last Name', controller: lastController),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final newFirst = firstController.text.trim();
                            final newLast = lastController.text.trim();
                            final messenger = ScaffoldMessenger.of(this.context);
                            FocusScope.of(context).unfocus();
                            setSheetState(() => isSaving = true);
                            await Future<void>.delayed(const Duration(milliseconds: 300));
                            if (mounted) {
                              setState(() {
                                _firstName = newFirst;
                                _lastName = newLast;
                              });
                            }
                            if (isSheetOpen && sheetContext.mounted) {
                              isSheetOpen = false;
                              Navigator.of(sheetContext).pop();
                            }
                            messenger.showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
                          },
                    child: isSaving ? const CircularProgressIndicator() : const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          );
        }));
      },
    ).whenComplete(() {
      isSheetOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$_firstName $_lastName', key: const Key('name')),
          GestureDetector(onTap: _showEditProfileSheet, child: const Text('Edit Personal Details')),
        ]),
      ),
    );
  }
}

void main() {
  Future<void> open(WidgetTester t) async {
    await t.tap(find.text('Edit Personal Details'));
    await t.pumpAndSettle();
  }

  testWidgets('A: save then immediately reopen during exit animation', (t) async {
    await t.pumpWidget(const MaterialApp(home: Harness()));
    await open(t);
    await t.enterText(find.byType(TextField).first, 'Pedro');
    await t.tap(find.text('Save Changes'));
    await t.pump(const Duration(milliseconds: 300)); // save completes, pop starts
    await t.pump(const Duration(milliseconds: 50)); // mid exit animation
    await t.tap(find.text('Edit Personal Details'), warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.enterText(find.byType(TextField).last, 'Santos');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('B: focused field, close via X, reopen', (t) async {
    await t.pumpWidget(const MaterialApp(home: Harness()));
    await open(t);
    await t.showKeyboard(find.byType(TextField).first);
    await t.enterText(find.byType(TextField).first, 'Pedro');
    await t.tap(find.byKey(const Key('close')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    await open(t);
    await t.enterText(find.byType(TextField).first, 'Maria');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('C: focused field, swipe/barrier dismiss, reopen', (t) async {
    await t.pumpWidget(const MaterialApp(home: Harness()));
    await open(t);
    await t.showKeyboard(find.byType(TextField).first);
    await t.enterText(find.byType(TextField).first, 'Pedro');
    await t.tapAt(const Offset(10, 10));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    // IME sends an update mid-animation (e.g. composing region cleared)
    t.testTextInput.updateEditingValue(const TextEditingValue(text: 'Pedro'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('D: two sequential full edits', (t) async {
    await t.pumpWidget(const MaterialApp(home: Harness()));
    for (final n in ['Pedro', 'Maria']) {
      await open(t);
      await t.showKeyboard(find.byType(TextField).first);
      await t.enterText(find.byType(TextField).first, n);
      await t.tap(find.text('Save Changes'));
      await t.pumpAndSettle();
    }
    expect(find.text('Maria Cruz'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
