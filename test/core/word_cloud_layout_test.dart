import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/utils/word_cloud_layout.dart';

void main() {
  group('sumWordCounts', () {
    test('sums duplicates, trims, drops blanks', () {
      final r = sumWordCounts([
        const MapEntry('Fair grading', 2),
        const MapEntry(' Fair grading ', 3),
        const MapEntry('', 4),
        const MapEntry('Approachable teacher', 1),
      ]);
      expect(r, {'Fair grading': 5, 'Approachable teacher': 1});
    });
  });

  group('layoutWordCloud', () {
    final freq = <String, int>{
      for (var i = 0; i < 90; i++) 'word${String.fromCharCode(97 + i % 26)}${String.fromCharCode(97 + i ~/ 26)}': (90 / (i + 1)).ceil(),
    };
    const w = 290.0, h = 150.0;

    test('no overlaps, inside bounds, some rotated', () {
      final out = layoutWordCloud(freq, width: w, height: h);
      expect(out.length, greaterThan(20));
      for (final a in out) {
        expect(a.x, greaterThanOrEqualTo(0));
        expect(a.y, greaterThanOrEqualTo(0));
        expect(a.x + a.w, lessThanOrEqualTo(w));
        expect(a.y + a.h, lessThanOrEqualTo(h));
      }
      for (var i = 0; i < out.length; i++) {
        for (var j = i + 1; j < out.length; j++) {
          final a = out[i], b = out[j];
          final overlap = a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
          expect(overlap, isFalse, reason: '${a.word} vs ${b.word}');
        }
      }
      expect(out.any((e) => e.rotated), isTrue);
    });

    test('deterministic and biggest word first and largest', () {
      final a = layoutWordCloud(freq, width: w, height: h);
      final b = layoutWordCloud(freq, width: w, height: h);
      expect(a.map((e) => '${e.word}${e.x}${e.y}${e.rotated}').toList(),
          b.map((e) => '${e.word}${e.x}${e.y}${e.rotated}').toList());
      expect(a.first.count, 90);
      expect(a.first.rotated, isFalse);
      expect(a.first.fontSize, 40);
      expect(a.every((e) => e.fontSize <= a.first.fontSize), isTrue);
    });

    test('phrases are never rotated; long words are not rotated', () {
      final f = <String, int>{
        for (var i = 0; i < 40; i++) 'Fair grading ${String.fromCharCode(97 + i % 26)}$i': 40 - i,
        'extraordinarilylong': 3,
        'short': 2,
      };
      final out = layoutWordCloud(f, width: 290, height: 150);
      for (final c in out) {
        if (c.word.contains(' ') || c.word.length > 12) expect(c.rotated, isFalse, reason: c.word);
      }
    });

    test('empty input', () {
      expect(layoutWordCloud({}, width: w, height: h), isEmpty);
    });
  });
}
