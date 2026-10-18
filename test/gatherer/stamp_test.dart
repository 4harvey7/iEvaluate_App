import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/gatherer/services/stamp.dart';

void main() {
  group('Stamp.normalize / isValid / validationError', () {
    test('keeps leading zeros and strips non-digits', () {
      expect(Stamp.normalize(' 0100005 '), '0100005');
      expect(Stamp.normalize('0100-005'), '0100005');
      expect(Stamp.normalize(null), '');
      expect(Stamp.isValid('0100005'), isTrue);
    });

    test('3 to 12 digits only', () {
      expect(Stamp.isValid('12'), isFalse);
      expect(Stamp.isValid('123'), isTrue);
      expect(Stamp.isValid('123456789012'), isTrue);
      expect(Stamp.isValid('1234567890123'), isFalse);
      expect(Stamp.isValid('12a4'), isFalse);
      expect(Stamp.isValid(null), isFalse);
    });

    test('validation messages', () {
      expect(Stamp.validationError(''), isNull); // empty judged by the screen
      expect(Stamp.validationError('12'), contains('at least 3'));
      expect(Stamp.validationError('1234567890123'), contains('at most 12'));
      expect(Stamp.validationError('000123'), isNull);
    });

    test('payload: digits, or null for empty / invalid / no stamp', () {
      expect(Stamp.toPayload('000123'), '000123');
      expect(Stamp.toPayload(''), isNull);
      expect(Stamp.toPayload('12'), isNull);
      expect(Stamp.toPayload('000123', noStamp: true), isNull);
    });
  });

  group('Stamp reasons', () {
    test('labels and plain-English text', () {
      expect(Stamp.reasonLabel('stamp_missing'), 'No stamp found');
      expect(Stamp.reasonLabel('multiple_stamps'), 'Several stamps');
      expect(Stamp.reasonLabel('duplicate_stamp'), 'Already scanned');
      expect(Stamp.reasonLabel('stamp_check_failed'), 'Stamp not checked');
      expect(Stamp.reasonLabel('stamp_unreadable: 2 digits'), 'Stamp unreadable');
      expect(Stamp.reasonLabel('too_few_answers_3_of_20'), isNull);
      expect(Stamp.reasonText('stamp_unreadable'), isNotNull);
      expect(Stamp.reasonText('omr_fallback_grid'), isNull);
    });
  });

  group('QueueStamp.fromRow', () {
    test('column wins, partial_data is the fallback', () {
      final a = QueueStamp.fromRow({
        'stamp_no': '0100005',
        'stamp_source': 'gemini',
        'partial_data': {'stamp_no': '999', 'stamp_status': 'ok'},
      });
      expect(a.stampNo, '0100005');
      expect(a.source, 'gemini');
      expect(a.status, 'ok');
      expect(a.needsStaffInput, isFalse);

      final b = QueueStamp.fromRow({
        'stamp_no': null,
        'partial_data': {'stamp_no': '0042', 'stamp_status': 'ok'},
      });
      expect(b.stampNo, '0042');
    });

    test('multiple stamps: candidates de-duplicated, invalid dropped', () {
      final s = QueueStamp.fromRow({
        'review_reasons': ['multiple_stamps', 'omr_fallback_grid'],
        'partial_data': {
          'stamp_status': 'multiple',
          'stamp_candidates': ['0100005', '0100006', '0100005', '12', null],
        },
      });
      expect(s.stampNo, isNull);
      expect(s.source, isNull);
      expect(s.candidates, ['0100005', '0100006']);
      expect(s.choices, ['0100005', '0100006']);
      expect(s.reasons, ['multiple_stamps']);
      expect(s.needsStaffInput, isTrue);
    });

    test('missing stamp needs staff input; older rows do not', () {
      expect(
        QueueStamp.fromRow({
          'review_reasons': ['stamp_missing'],
          'partial_data': {'stamp_status': 'missing'},
        }).needsStaffInput,
        isTrue,
      );
      expect(QueueStamp.fromRow({'partial_data': {}}).needsStaffInput, isFalse);
      expect(QueueStamp.fromRow({}).stampNo, isNull);
    });
  });

  group('DuplicateStampAnswer.tryParse', () {
    test('reads the 409 body', () {
      final d = DuplicateStampAnswer.tryParse(409, {
        'success': false,
        'code': 'duplicate_stamp',
        'message': 'Stamp 0100005 is already saved for this term.',
        'duplicate_of': {
          'raw_id': 123,
          'submitted_date': '2026-10-03',
          'stamp_no': '0100005',
        },
      });
      expect(d, isNotNull);
      expect(d!.stampNo, '0100005');
      expect(d.submittedDate, '2026-10-03');
      expect(d.submittedDateLabel, 'Oct 3, 2026');
      expect(d.explanation, contains('Stamp 0100005 is already saved this term'));
      expect(d.explanation, contains('Oct 3, 2026'));
    });

    test('other errors are not duplicates', () {
      expect(DuplicateStampAnswer.tryParse(500, {'error': 'boom'}), isNull);
      expect(DuplicateStampAnswer.tryParse(409, 'conflict'), isNull);
      expect(DuplicateStampAnswer.tryParse(200, {'success': true}), isNull);
    });
  });

  group('ScanAnswer.tryParse', () {
    test('duplicate stamp auto-reject', () {
      const msg = 'Discarded automatically: this form was already scanned '
          '(stamp 0100005), so it is not counted.';
      final a = ScanAnswer.tryParse({'status': 'flagged', 'message': msg});
      expect(a, isNotNull);
      expect(a!.discard, ScanDiscard.duplicateStamp);
      expect(a.stampNo, '0100005');
      expect(a.message, msg);
      expect(a.outcomeCode, 'duplicate_stamp');

      final b = ScanAnswer.tryParse([
        {'auto_rejected': 'duplicate_stamp', 'stamp_no': '000777'},
      ]);
      expect(b!.discard, ScanDiscard.duplicateStamp);
      expect(b.stampNo, '000777');
      expect(b.message, contains('stamp 000777'));
    });

    test('min-5 auto-discard', () {
      final a = ScanAnswer.tryParse({
        'status': 'flagged',
        'message': 'Discarded automatically: fewer than 5 of the 20 items '
            'were answered (only 3), so this form is not counted.',
      });
      expect(a!.discard, ScanDiscard.tooFewAnswers);
      expect(a.outcomeCode, 'too_few_answers');
    });

    test('normal answers are not discards', () {
      expect(ScanAnswer.tryParse({'status': 'success'}), isNull);
      expect(
        ScanAnswer.tryParse({
          'status': 'flagged',
          'message': 'Flagged for manual review (stamp_missing).',
        }),
        isNull,
      );
      expect(ScanAnswer.tryParse(null), isNull);
    });
  });
}
