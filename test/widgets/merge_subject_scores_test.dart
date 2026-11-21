import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/widgets/instructor_detail_sheet.dart';

void main() {
  final subjects = [
    {'subject_id': 'a', 'subjects': {'subject_code': 'IT1', 'subject_name': 'Intro'}},
    {'subject_id': 'b', 'subjects': [{'subject_code': 'IT2', 'subject_name': 'Web'}]},
    {'subject_id': 'c', 'subjects': null},
  ];

  test('averages several rows per subject', () {
    final r = mergeSubjectScores(subjects, [
      {'subject_id': 'a', 'overall_management_mean': 4},
      {'subject_id': 'a', 'overall_management_mean': '5'},
    ]);
    expect(r[0]['score'], 4.5);
    expect(r[0]['subject_code'], 'IT1');
    expect(r[1]['subject_name'], 'Web');
  });

  test('missing or null score gives null, not 0', () {
    final r = mergeSubjectScores(subjects, [
      {'subject_id': 'b', 'overall_management_mean': null},
    ]);
    expect(r[0]['score'], isNull);
    expect(r[1]['score'], isNull);
    expect(r[2]['subject_code'], '');
  });
}
