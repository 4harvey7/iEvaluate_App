import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/sao_admin/live_system_metrics_screen.dart';

void main() {
  group('describeMetricsLoadError', () {
    test('offline and timeout say so', () {
      expect(describeMetricsLoadError(const SocketException('no route')),
          contains('offline'));
      expect(describeMetricsLoadError(TimeoutException('slow')),
          contains('offline'));
      expect(
        describeMetricsLoadError(Exception(
            'ClientException with SocketException: Failed host lookup')),
        contains('offline'),
      );
    });

    test('other failures get a generic message, never zeros', () {
      final msg = describeMetricsLoadError(Exception('permission denied'));
      expect(msg, contains("Couldn't load"));
    });
  });
}
