// The edit-name sheet lives on a tab's NESTED Navigator, underneath the outer
// Scaffold that owns the bottom nav and draws the snackbars -- exactly how
// MainScaffold hosts the Settings screens. That arrangement is what made the
// old pasted-in sheet dangerous: its `navigator.pop()` closed whatever was on
// top, so a save finishing after the sheet was dismissed closed Settings
// instead. These tests rebuild that arrangement and pin the behaviour down.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/auth_service.dart';
import 'package:ievaluateapp_final/widgets/edit_name_sheet.dart';

/// Stand-in for a Settings screen: shows the name, opens the sheet.
class _Settings extends StatefulWidget {
  const _Settings({required this.onSave});
  final Future<AuthResult> Function(String, String) onSave;

  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  String _firstName = 'Juan';
  String _lastName = 'Cruz';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: Column(
        children: [
          Text('name: $_firstName $_lastName'),
          TextButton(
            onPressed: () => showEditNameSheet(
              context: context,
              firstName: _firstName,
              lastName: _lastName,
              onSave: widget.onSave,
              onSaved: (first, last) {
                if (!mounted) return;
                setState(() {
                  _firstName = first;
                  _lastName = last;
                });
              },
            ),
            child: const Text('Edit Personal Details'),
          ),
        ],
      ),
    );
  }
}

void main() {
  late Completer<AuthResult> save;
  late List<String> savedNames;
  late GlobalKey<NavigatorState> tabNavigator;

  Future<AuthResult> onSave(String first, String last) {
    savedNames.add('$first $last');
    save = Completer<AuthResult>();
    return save.future;
  }

  /// Dashboard tab with Settings pushed on top of it, inside an outer Scaffold.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    savedNames = [];
    tabNavigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Navigator(
            key: tabNavigator,
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('DASHBOARD')),
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Subjects'),
            ],
          ),
        ),
      ),
    );
    tabNavigator.currentState!.push(
      MaterialPageRoute(builder: (_) => _Settings(onSave: onSave)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('Edit Personal Details'));
    await tester.pumpAndSettle();
  }

  final sheet = find.byType(EditNameSheet);
  final firstNameField = find.widgetWithText(TextField, 'First Name');

  testWidgets('saving updates the name and closes only the sheet', (tester) async {
    await pumpSettings(tester);
    await openSheet(tester);

    await tester.enterText(firstNameField, '  Pedro ');
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    save.complete(const AuthResult(success: true));
    await tester.pumpAndSettle();

    expect(savedNames, ['Pedro Cruz']); // trimmed before it is sent
    expect(sheet, findsNothing);
    expect(find.text('name: Pedro Cruz'), findsOneWidget);
    expect(find.text('Profile updated successfully!'), findsOneWidget);
  });

  // The reported bug: finish one edit, go straight into another.
  testWidgets('can edit again straight after a save', (tester) async {
    await pumpSettings(tester);

    for (final name in ['Pedro', 'Pablo', 'Paolo']) {
      await tester.tap(find.text('Edit Personal Details'));
      await tester.pumpAndSettle();
      await tester.enterText(firstNameField, name);

      // The success bar from the previous save used to sit right on top of
      // this button, so the tap never reached it.
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      save.complete(const AuthResult(success: true));
      // Only a few frames: the sheet is still sliding away and the snackbar
      // still sliding in when the next round re-opens it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(savedNames, ['Pedro Cruz', 'Pablo Cruz', 'Paolo Cruz']);
    expect(find.text('name: Paolo Cruz'), findsOneWidget);
    expect(find.text('Account Settings'), findsOneWidget);
  });

  testWidgets('a save that lands after the sheet was dismissed leaves Settings open', (tester) async {
    await pumpSettings(tester);
    await openSheet(tester);

    await tester.enterText(firstNameField, 'Pedro');
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.tapAt(const Offset(20, 120)); // the scrim, mid-save
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    save.complete(const AuthResult(success: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('DASHBOARD'), findsNothing);
    expect(find.text('Account Settings'), findsOneWidget);
    expect(find.text('name: Pedro Cruz'), findsOneWidget); // the save still counted
  });

  testWidgets('a save that lands while the sheet is still sliding away leaves Settings open', (tester) async {
    await pumpSettings(tester);
    await openSheet(tester);

    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.tapAt(const Offset(20, 120));
    await tester.pump(const Duration(milliseconds: 50)); // mid-animation: still mounted
    expect(sheet, findsOneWidget);

    save.complete(const AuthResult(success: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Account Settings'), findsOneWidget);
  });

  testWidgets('a failed save that lands after the sheet was dismissed does not throw', (tester) async {
    await pumpSettings(tester);
    await openSheet(tester);

    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.tapAt(const Offset(20, 120));
    await tester.pumpAndSettle();

    save.complete(const AuthResult(success: false, error: 'That name is taken.'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // was: setState() called after dispose()
    expect(find.text('That name is taken.'), findsOneWidget);
    expect(find.text('name: Juan Cruz'), findsOneWidget);
  });

  testWidgets('a failed save keeps the sheet open and re-enables Save', (tester) async {
    await pumpSettings(tester);
    await openSheet(tester);

    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    save.complete(const AuthResult(success: false, error: 'That name is taken.'));
    await tester.pumpAndSettle();

    expect(sheet, findsOneWidget);
    expect(find.text('That name is taken.'), findsOneWidget);
    expect(find.text('name: Juan Cruz'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save Changes')).onPressed,
      isNotNull,
    );
  });

  testWidgets('a save finishing after Settings itself was closed does not throw', (tester) async {
    await pumpSettings(tester);
    await openSheet(tester);

    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    tabNavigator.currentState!.popUntil((route) => route.isFirst); // e.g. a forced sign-out
    await tester.pumpAndSettle();
    expect(find.text('DASHBOARD'), findsOneWidget);

    save.complete(const AuthResult(success: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });
}
