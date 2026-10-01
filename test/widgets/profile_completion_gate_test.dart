// Covers the post-login "Complete your information" prompt:
//
//   * nothing is shown when the profile already has an ID and an address
//   * only the missing field(s) are asked for
//   * input is validated before anything is sent
//   * a failed save keeps the dialog open with the reason, and a partial save
//     stops asking for what was stored
//   * "Later" closes without saving
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/address_service.dart';
import 'package:ievaluateapp_final/core/services/profile_completion_service.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';
import 'package:ievaluateapp_final/widgets/profile_completion_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeProfileService extends ProfileCompletionService {
  FakeProfileService(this.status, {this.result = const ProfileCompletionResult.ok()});

  final ProfileCompletionStatus? status;
  ProfileCompletionResult result;
  final List<Map<String, String?>> saves = [];

  @override
  Future<ProfileCompletionStatus?> fetchStatus(String userId) async => status;

  @override
  Future<ProfileCompletionResult> save({
    required String userId,
    String? universityId,
    String? address,
    String idLabel = 'University ID',
  }) async {
    saves.add({'id': universityId, 'address': address, 'label': idLabel});
    return result;
  }
}

class FakeAddressService extends AddressService {
  @override
  Future<List<AddressLocation>> fetchLocations() async => const [];
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  Future<void> pumpGate(
    WidgetTester tester,
    FakeProfileService service, {
    String role = 'FULL-TIME',
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileCompletionGate(
          userId: 'user-1',
          role: role,
          service: service,
          addressService: FakeAddressService(),
          child: const Scaffold(body: Text('Dashboard')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const title = 'Complete your information';
  final idField = find.byKey(const Key('completeProfile.id'));
  final streetField = find.byKey(const Key('completeProfile.street'));
  final barangayField = find.byKey(const Key('completeProfile.barangay'));
  final saveButton = find.byKey(const Key('completeProfile.save'));

  testWidgets('complete profile shows no prompt', (tester) async {
    final service = FakeProfileService(
      const ProfileCompletionStatus(needsId: false, needsAddress: false),
    );
    await pumpGate(tester, service);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text(title), findsNothing);
  });

  testWidgets('unknown status (offline) shows no prompt', (tester) async {
    await pumpGate(tester, FakeProfileService(null));
    expect(find.text(title), findsNothing);
  });

  testWidgets('missing address only: asks for address, validates, saves',
      (tester) async {
    final service = FakeProfileService(
      const ProfileCompletionStatus(needsId: false, needsAddress: true),
    );
    await pumpGate(tester, service);

    expect(find.text(title), findsOneWidget);
    expect(idField, findsNothing);
    expect(streetField, findsOneWidget);
    expect(barangayField, findsOneWidget);

    // Empty save is refused locally.
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(service.saves, isEmpty);
    expect(find.text('House number / street is required'), findsWidgets);

    await tester.enterText(streetField, '123 Rizal St.');
    await tester.enterText(barangayField, 'Lamacan, Argao, Cebu');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.saves, hasLength(1));
    expect(service.saves.single['id'], isNull);
    expect(service.saves.single['address'], '123 Rizal St., Lamacan, Argao, Cebu');
    expect(find.text(title), findsNothing);
    expect(find.text('Your information has been saved.'), findsOneWidget);
  });

  testWidgets('missing ID only for SAO role: Staff ID wording and format check',
      (tester) async {
    final service = FakeProfileService(
      const ProfileCompletionStatus(needsId: true, needsAddress: false),
    );
    await pumpGate(tester, service, role: 'SAO_STAFF');

    expect(idField, findsOneWidget);
    expect(streetField, findsNothing);
    expect(find.text('Staff ID'), findsOneWidget);

    await tester.enterText(idField, 'ab');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(service.saves, isEmpty);
    expect(find.text('Staff ID must be at least 4 characters'), findsWidgets);

    await tester.enterText(idField, 'SAO-0042');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(service.saves.single['id'], 'SAO-0042');
    expect(service.saves.single['address'], isNull);
    expect(service.saves.single['label'], 'Staff ID');
    expect(find.text(title), findsNothing);
  });

  testWidgets('failed save keeps dialog open; partial save drops the address',
      (tester) async {
    final service = FakeProfileService(
      const ProfileCompletionStatus(needsId: true, needsAddress: true),
      result: const ProfileCompletionResult.failed(
        'ID refused for test',
        addressSaved: true,
      ),
    );
    await pumpGate(tester, service);

    await tester.enterText(idField, '2024-0001');
    await tester.enterText(streetField, 'Purok 1');
    await tester.enterText(barangayField, 'Poblacion, Argao, Cebu');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text(title), findsOneWidget);
    expect(find.text('ID refused for test'), findsOneWidget);
    expect(idField, findsOneWidget);
    expect(streetField, findsNothing); // already stored, no longer asked
  });

  testWidgets('Later closes without saving', (tester) async {
    final service = FakeProfileService(
      const ProfileCompletionStatus(needsId: true, needsAddress: true),
    );
    await pumpGate(tester, service);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
    expect(service.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  group('ProfileCompletionStatus.fromRow', () {
    test('null, empty and whitespace count as missing', () {
      final s = ProfileCompletionStatus.fromRow({'university_id': '  ', 'address': null});
      expect(s.needsId, isTrue);
      expect(s.needsAddress, isTrue);
      final ok = ProfileCompletionStatus.fromRow({'university_id': '1234', 'address': 'Argao'});
      expect(ok.isComplete, isTrue);
    });
  });
}
