import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/pdf/pdf_service.dart';
import 'package:ievaluateapp_final/core/utils/theme_list_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('instructor detailed report builds exactly 2 pages without subjects', () async {
    final bytes = await PdfService().buildInstructorDetailedReport(
      instructorName: 'Juan Dela Cruz',
      department: 'Information Technology',
      college: 'College of Technology and Engineering',
      courseTaught: 'IT101 - Intro to Computing, IT102 - Programming 1',
      term: '1st Semester',
      academicYear: '2025-2026',
      mgmtScore: 4.67,
      perfScore: 4.68,
      overallScore: 4.68,
      totalEvals: 121,
      managementMeans: List<double?>.filled(10, 4.5),
      performanceMeans: List<double?>.filled(10, 4.6),
      aiSuggestion: '',
      studentInterpretation: 'Students describe him as clear and kind.',
      wordCloudData: const [
        {'word': 'good', 'count': 9},
        {'word': 'instructor', 'count': 7},
        {'word': 'clear', 'count': 2},
      ],
    );
    final text = latin1.decode(bytes, allowInvalid: true);
    final pages = RegExp(r'/Type\s*/Page(?![a-z])').allMatches(text).length;
    expect(pages, 2);
  });

  test('overall page + one page per subject + comments page', () async {
    SastSubjectReport sub(String c) => SastSubjectReport(
          courseTaught: c,
          totalEvals: 30,
          mgmtScore: 4.3,
          perfScore: 4.4,
          overallScore: 4.35,
          managementMeans: List<double?>.filled(10, 4.3),
          performanceMeans: List<double?>.filled(10, 4.4),
        );
    final bytes = await PdfService().buildInstructorDetailedReport(
      instructorName: 'Juan Dela Cruz',
      department: 'IT',
      term: '1st Semester',
      academicYear: '2025-2026',
      mgmtScore: 4.3,
      perfScore: 4.4,
      overallScore: 4.35,
      totalEvals: 90,
      managementMeans: List<double?>.filled(10, 4.3),
      performanceMeans: List<double?>.filled(10, 4.4),
      aiSuggestion: '',
      wordCloudData: const [],
      subjectReports: [sub('IT101 - A'), sub('IT102 - B'), sub('IT103 - C')],
    );
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page(?![a-z])').allMatches(text).length, 5);
  });

  test('comments page with a 2500+ char narrative still builds', () async {
    final bytes = await PdfService().buildInstructorDetailedReport(
      instructorName: 'Juan Dela Cruz',
      department: 'IT',
      term: '1st Semester',
      academicYear: '2025-2026',
      mgmtScore: 4.3,
      perfScore: 4.4,
      overallScore: 4.35,
      totalEvals: 90,
      managementMeans: List<double?>.filled(10, 4.3),
      performanceMeans: List<double?>.filled(10, 4.4),
      aiSuggestion: '',
      studentInterpretation: List.filled(60, 'Students describe the lessons as clear and engaging.').join(' '),
      wordCloudData: const [
        {'word': 'instructor', 'count': 9},
        {'word': 'good', 'count': 5},
      ],
    );
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page(?![a-z])').allMatches(text).length, 2);
  });

  test('comment text falls back gracefully without AI data', () {
    final t = PdfService.buildSastCommentText(
      instructorName: 'X', mgmt: 4.67, perf: 4.68, overall: 4.68);
    expect(t, contains('all Outstanding'));
    expect(PdfService.buildSastCommentText(instructorName: 'X', mgmt: null, perf: null, overall: null),
        'No evaluation results yet.');
  });

  group('parseThemeValue', () {
    test('postgres array, fully quoted (screenshot 6)', () {
      final v = parseThemeValue('{"Clear explanation of difficult topics","Strong preparedness"}');
      expect(v.items, ['Clear explanation of difficult topics', 'Strong preparedness']);
    });
    test('partially quoted array', () {
      final v = parseThemeValue('{"Teaching clarity","Fair grading",Accessibility}');
      expect(v.items, ['Teaching clarity', 'Fair grading', 'Accessibility']);
    });
    test('commas and escapes inside quotes', () {
      final v = parseThemeValue(r'{"Clear, concise","Says \"hi\"","Say ""yo""",NULL,""}');
      expect(v.items, ['Clear, concise', 'Says "hi"', 'Say "yo"']);
    });
    test('plain comma list', () {
      expect(parseThemeValue('Clarity, Fairness, Punctuality').items, ['Clarity', 'Fairness', 'Punctuality']);
    });
    test('prose stays text', () {
      final s = 'Students appreciate the clear lessons, but want more examples.';
      final v = parseThemeValue(s);
      expect(v.items, isEmpty);
      expect(v.text, s);
    });
    test('empty and null', () {
      expect(parseThemeValue(null).isEmpty, isTrue);
      expect(parseThemeValue('  ').isEmpty, isTrue);
      expect(parseThemeValue('{}').isEmpty, isTrue);
    });
    test('natural list and case-insensitive dedupe', () {
      expect(parseThemeValue('{A,b,B,C}').toNaturalList(), 'A, b, and C');
      expect(parseThemeValue('{A,B}').toNaturalList(), 'A and B');
    });
  });

  test('comment text is one flowing paragraph with all five columns', () {
    final t = PdfService.buildSastCommentText(
      instructorName: 'X', mgmt: 4.67, perf: 4.68, overall: 4.68,
      studentInterpretation: 'Students are happy with the clear lessons.',
      overallTone: 'Positive',
      aiSuggestion: 'Keep using real-world examples',
      wordCloudData: const [{'word': 'clear', 'count': 3}],
    );
    // ignore: avoid_print
    print(t);
    expect(t, startsWith('Integrated with the quantitative ratings'));
    expect(t, contains('(clear)'));
    expect(t, contains("indicates that students are happy with the clear lessons."));
    expect(t, isNot(contains('appreciated')));
    expect(t, contains('It is recommended that the instructor keep using real-world examples.'));
    expect(t, endsWith("Overall, the tone of the students' feedback is positive."));
    expect(t, isNot(contains('\n')));
    expect(t, isNot(contains('..')));
    expect(t, isNot(anyOf(contains('{'), contains('"'))));
  });

  test('comment text skips empty parts and keeps existing recommendations', () {
    final t = PdfService.buildSastCommentText(
        instructorName: 'X', mgmt: 4.0, perf: 4.0, overall: 4.0,
        aiSuggestion: 'It is recommended that the instructor add quizzes.');
    expect(t, contains('the overall evaluation of X is'));
    expect(t, isNot(contains('appreciated')));
    expect(t, isNot(contains('improvement')));
    expect(t, isNot(contains('tone')));
    expect(t, endsWith('It is recommended that the instructor add quizzes.'));
  });

  test('signatories default when row missing', () {
    expect(SastSignatories.fromRow(null).certifiedByName, 'EINGILBERT C. BENOLOIRAO');
  });
}
