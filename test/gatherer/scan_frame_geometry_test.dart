import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/gatherer/services/scan_frame_geometry.dart';

void main() {
  main2();
  const screen = Size(360, 800);
  const longBond = 8.5 / 13;

  for (final entry in {'4:3': 4 / 3, '16:9': 16 / 9}.entries) {
    test('${entry.key} still: frame inside preview and image, ratio kept', () {
      final preview = containRect(screen, portraitAspect(entry.value));
      expect(preview.width / preview.height,
          closeTo(portraitAspect(entry.value), 1e-6));
      final frame = frameInPreview(preview, longBond);
      expect(frame.width / frame.height, closeTo(longBond, 1e-6));
      expect(preview.contains(frame.topLeft), isTrue);
      expect(preview.contains(frame.bottomRight), isTrue);
      final image = entry.value == 4 / 3
          ? const Size(3120, 4160)
          : const Size(1080, 1920);
      final r = frameToImageRect(frame, preview, image);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(image.height));
      expect(r.width / r.height, closeTo(longBond, 0.01));
    });
  }

  test('frame overhanging the preview is clamped to the image', () {
    final preview = containRect(screen, 3 / 4);
    final r = frameToImageRect(
        Rect.fromLTWH(10, preview.top - 50, 340, preview.height + 200),
        preview,
        const Size(3120, 4160));
    expect(r.top, 0);
    expect(r.bottom, 4160);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(3120));
  });

  for (final entry in {'4:3': 4 / 3, '16:9': 16 / 9}.entries) {
    for (final ratio in [8.5 / 13, 210 / 297, 8.5 / 11]) {
      test('cover ${entry.key} ratio $ratio: frame fully visible and in image',
          () {
        const area = Size(400, 700);
        final preview = coverRect(area, portraitAspect(entry.value));
        expect(preview.width, greaterThanOrEqualTo(area.width - 1e-6));
        expect(preview.height, greaterThanOrEqualTo(area.height - 1e-6));
        const free = Rect.fromLTRB(12, 64, 388, 624);
        final visible = free
            .intersect(const Rect.fromLTWH(0, 0, 400, 700))
            .intersect(preview);
        final frame = frameInPreview(visible, ratio, hPad: 0, vPad: 0);
        expect(frame.width / frame.height, closeTo(ratio, 1e-6));
        expect(free.contains(frame.topLeft), isTrue);
        expect(frame.right, lessThanOrEqualTo(free.right + 1e-6));
        expect(frame.bottom, lessThanOrEqualTo(free.bottom + 1e-6));
        final image = Size(3000, 3000 / portraitAspect(entry.value));
        final r = frameToImageRect(frame, preview, image);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(image.width));
        expect(r.bottom, lessThanOrEqualTo(image.height));
      });
    }
  }
}

void main2() {
  test('long bond on a 375x600 camera area', () {
    const area = Size(375, 600);
    final preview = coverRect(area, 3 / 4);
    const free = Rect.fromLTRB(12, 64, 363, 520);
    final f = frameInPreview(free.intersect(preview), 8.5 / 13,
        hPad: 0, vPad: 0);
    // ignore: avoid_print
    print('FRAME ${f.width} x ${f.height}');
    expect(f.height, greaterThan(440));
  });
}
