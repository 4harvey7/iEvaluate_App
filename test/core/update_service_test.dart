import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  group('UpdateService.sendWithRetry', () {
    final uri = Uri.parse('https://example.com/a.apk');
    const noWait = [Duration.zero, Duration.zero, Duration.zero];

    (http.Client, int Function()) fake(List<int> statuses) {
      var calls = 0;
      final client = MockClient.streaming((req, body) async {
        final status = statuses[calls < statuses.length ? calls : statuses.length - 1];
        calls++;
        return http.StreamedResponse(Stream.value([1, 2, 3]), status);
      });
      return (client, () => calls);
    }

    test('retries 504, 504 then succeeds on 200', () async {
      final (client, calls) = fake([504, 504, 200]);
      final res = await UpdateService.sendWithRetry(client, uri, delays: noWait);
      expect(res.statusCode, 200);
      expect(calls(), 3);
    });
    test('always 504 gives up after 4 attempts', () async {
      final (client, calls) = fake([504]);
      final res = await UpdateService.sendWithRetry(client, uri, delays: noWait);
      expect(res.statusCode, 504);
      expect(calls(), 4);
    });
    test('404 is not retried', () async {
      final (client, calls) = fake([404]);
      final res = await UpdateService.sendWithRetry(client, uri, delays: noWait);
      expect(res.statusCode, 404);
      expect(calls(), 1);
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
