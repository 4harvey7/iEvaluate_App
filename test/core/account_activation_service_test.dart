// Covers when the SAO admin's Approve button must open "Activate account"
// instead of approving in one tap, and the client side of the activation call:
//
//   * placeholder logins from batch scanning (placeholder-<uuid>@ievaluate.internal)
//     and blank emails always need activation
//   * an account with a real email keeps the one-tap approve, even when its ID or
//     address is missing (the person completes those after login)
//   * the email is validated before anything is sent, only the email is sent,
//     and server errors come back as sentences (duplicates, already activated)
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/account_activation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeActivationService extends AccountActivationService {
  FakeActivationService({this.response, this.error});

  final dynamic response;
  final Object? error;
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<dynamic> invokeActivate(Map<String, dynamic> body) async {
    calls.add(body);
    if (error != null) throw error!;
    return response;
  }
}

const _placeholder = 'placeholder-3f0b8c1e-1111-4a2b-9c3d-123456789abc@ievaluate.internal';

Map<String, dynamic> row({
  String? email = 'juan.cruz@ctu.edu.ph',
  String? universityId = '2024-0001',
  String? address = 'Purok 1, Lamacan, Argao, Cebu',
  String status = 'pending',
  bool? isPlaceholder,
}) =>
    {
      'email': email,
      'university_id': universityId,
      'address': address,
      'account_status': status,
      'is_placeholder': ?isPlaceholder,
    };

void main() {
  group('isPlaceholderEmail', () {
    test('website placeholder logins', () {
      expect(AccountActivationService.isPlaceholderEmail(_placeholder), isTrue);
      expect(AccountActivationService.isPlaceholderEmail('  ${_placeholder.toUpperCase()} '), isTrue);
      expect(AccountActivationService.isPlaceholderEmail('anything@ievaluate.internal'), isTrue);
    });

    test('blank counts as no login', () {
      expect(AccountActivationService.isPlaceholderEmail(null), isTrue);
      expect(AccountActivationService.isPlaceholderEmail('   '), isTrue);
    });

    test('real addresses do not', () {
      expect(AccountActivationService.isPlaceholderEmail('juan.cruz@ctu.edu.ph'), isFalse);
      // "placeholder" elsewhere in the address is not the pattern
      expect(AccountActivationService.isPlaceholderEmail('my.placeholder-x@gmail.com'), isFalse);
      expect(AccountActivationService.isPlaceholderEmail('juan@internal.ctu.edu.ph'), isFalse);
    });
  });

  group('requiresActivation', () {
    test('real email keeps one-tap approve, even with ID / address missing', () {
      // The person completes those after login, not the admin.
      expect(AccountActivationService.requiresActivation(row()), isFalse);
      expect(
        AccountActivationService.requiresActivation(row(universityId: null, address: '')),
        isFalse,
      );
    });

    test('placeholder or blank login always needs activation', () {
      expect(AccountActivationService.requiresActivation(row(email: _placeholder)), isTrue);
      expect(
        AccountActivationService.requiresActivation(row(email: _placeholder, status: 'disabled')),
        isTrue,
      );
      expect(AccountActivationService.requiresActivation(row(email: null)), isTrue);
    });

    test('is_placeholder from the website migration is honoured', () {
      expect(AccountActivationService.requiresActivation(row(isPlaceholder: true)), isTrue);
    });
  });

  group('validateEmail', () {
    test('format rule applies', () {
      expect(AccountActivationService.validateEmail(''), 'Email is required');
      expect(AccountActivationService.validateEmail('not-an-email'), 'Enter a valid email address');
    });

    test('placeholder is refused', () {
      expect(AccountActivationService.validateEmail(_placeholder), contains('real email'));
    });

    test('real address passes', () {
      expect(AccountActivationService.validateEmail('Juan.Cruz@CTU.edu.ph'), isNull);
    });
  });

  group('activate', () {
    test('invalid email never reaches the server', () async {
      final service = FakeActivationService(response: {});
      final bad = [
        await service.activate(userId: 'u1', email: _placeholder),
        await service.activate(userId: 'u1', email: ''),
        await service.activate(userId: 'u1', email: 'not-an-email'),
      ];
      expect(bad.every((r) => !r.success), isTrue);
      expect(service.calls, isEmpty);
    });

    test('sends only the target and the cleaned email', () async {
      final service = FakeActivationService(response: {
        'email': 'juan.cruz@ctu.edu.ph',
        'passwordSetupRequired': true,
        'emailSent': true,
      });
      final result = await service.activate(
        userId: 'u1',
        email: '  Juan.Cruz@CTU.edu.ph ',
      );
      expect(result.success, isTrue);
      expect(result.email, 'juan.cruz@ctu.edu.ph');
      expect(result.passwordSetupRequired, isTrue);
      expect(result.emailSent, isTrue);
      expect(service.calls.single, {
        'targetUserId': 'u1',
        'email': 'juan.cruz@ctu.edu.ph',
      });
    });

    test('email that could not be sent is reported, activation still succeeds', () async {
      final service = FakeActivationService(response: {
        'email': 'juan.cruz@ctu.edu.ph',
        'passwordSetupRequired': true,
        'emailSent': false,
      });
      final result = await service.activate(userId: 'u1', email: 'juan.cruz@ctu.edu.ph');
      expect(result.success, isTrue);
      expect(result.emailSent, isFalse);
    });

    test('duplicate email from the server becomes a sentence', () async {
      final service = FakeActivationService(
        error: const FunctionException(
          status: 409,
          details: {'error': 'Duplicate: this email address already belongs to another account.'},
        ),
      );
      final result = await service.activate(userId: 'u1', email: 'taken@ctu.edu.ph');
      expect(result.success, isFalse);
      expect(result.alreadyActivated, isFalse);
      expect(result.error, contains('already belongs to another account'));
    });

    test('already activated is flagged so the list is refreshed', () async {
      final service = FakeActivationService(
        error: const FunctionException(
          status: 409,
          details: {'error': 'Already activated: this account already has its own login and is approved. Refresh the list.'},
        ),
      );
      final result = await service.activate(userId: 'u1', email: 'juan@ctu.edu.ph');
      expect(result.success, isFalse);
      expect(result.alreadyActivated, isTrue);
    });

    test('"Invalid input:" prefix is dropped', () async {
      final service = FakeActivationService(
        error: const FunctionException(
          status: 400,
          details: {'error': 'Invalid input: Enter a valid email address'},
        ),
      );
      final result = await service.activate(userId: 'u1', email: 'juan@ctu.edu.ph');
      expect(result.error, 'Enter a valid email address');
    });

    test('function not deployed says so', () async {
      final service = FakeActivationService(
        error: const FunctionException(status: 404, details: 'Not Found'),
      );
      final result = await service.activate(userId: 'u1', email: 'juan@ctu.edu.ph');
      expect(result.error, contains(AccountActivationService.functionName));
    });

    test('unknown failure gets the generic message, never the raw error', () async {
      final service = FakeActivationService(error: Exception('boom: internal detail'));
      final result = await service.activate(userId: 'u1', email: 'juan@ctu.edu.ph');
      expect(result.error, 'Could not activate the account. Please try again.');
    });
  });
}
