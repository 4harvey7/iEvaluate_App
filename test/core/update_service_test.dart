import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/update_service.dart';

void main() {
  group('UpdateService.isNewer', () {
    test('newer release code is an update', () {
      expect(UpdateService.isNewer(2, '1'), isTrue);
      expect(UpdateService.isNewer(10, '9'), isTrue); // numeric, not string compare
    });
    test('same or older release code is not an update', () {
      expect(UpdateService.isNewer(1, '1'), isFalse);
      expect(UpdateService.isNewer(1, '2'), isFalse);
    });
    test('unreadable installed build never triggers an update', () {
      expect(UpdateService.isNewer(5, ''), isFalse);
      expect(UpdateService.isNewer(5, 'abc'), isFalse);
    });
  });

  group('UpdateService.hashMatches', () {
    // SHA-256("abc"), the FIPS 180-2 test vector.
    const abc = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    final computed = sha256.convert(utf8.encode('abc')).toString();

    test('matches the computed digest, case-insensitive and trimmed', () {
      expect(UpdateService.hashMatches(abc, computed), isTrue);
      expect(UpdateService.hashMatches(' ${abc.toUpperCase()} \n', computed), isTrue);
    });
    test('rejects a different digest', () {
      final other = sha256.convert(utf8.encode('abd')).toString();
      expect(UpdateService.hashMatches(abc, other), isFalse);
      expect(UpdateService.hashMatches('', computed), isFalse);
    });
  });

  test('AppRelease.fromMap reads a Supabase row', () {
    final r = AppRelease.fromMap({
      'version_code': 3,
      'version_name': '1.0.2',
      'apk_url': 'https://example.com/a.apk',
      'sha256': 'x',
      'notes': null,
      'force': true,
    });
    expect(r.versionCode, 3);
    expect(r.force, isTrue);
    expect(r.notes, isNull);
  });
}
