// The fast analysis path must reach the same verdicts as the one it replaced.
//
// The blur cutoff and the form-check thresholds were tuned on what the old
// code computed: img.decodeJpg, nearest-neighbour copyResize to 640px, then
// per-pixel package:image maths. The new code decodes natively, samples the
// 640px image itself and works on raw bytes. These tests pin the two together
// against a verbatim copy of the old implementation (_reference* below).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ievaluateapp_final/gatherer/services/form_signature.dart';
import 'package:ievaluateapp_final/gatherer/services/scan_analysis.dart';

/// A white page with a table-ish grid of dark rulings on a darker desk,
/// plus some noise -- enough structure for both checks to have something to
/// measure. [blur] softens it.
img.Image _page(int w, int h, {int seed = 1, bool blur = false}) {
  final rnd = math.Random(seed);
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(60, 55, 50));
  final px = (w * 0.1).round(), py = (h * 0.08).round();
  img.fillRect(image,
      x1: px, y1: py, x2: w - px, y2: h - py, color: img.ColorRgb8(235, 235, 230));
  for (var i = 0; i < 24; i++) {
    final y = py + (h - 2 * py) * (0.3 + 0.025 * i);
    img.drawLine(image,
        x1: px + 20, y1: y.round(), x2: w - px - 20, y2: y.round(),
        color: img.ColorRgb8(20, 20, 20), thickness: 2);
  }
  for (var i = 0; i < 7; i++) {
    final x = px + 20 + (w - 2 * px - 40) * i / 6;
    img.drawLine(image,
        x1: x.round(), y1: (py + (h - 2 * py) * 0.3).round(),
        x2: x.round(), y2: (py + (h - 2 * py) * 0.875).round(),
        color: img.ColorRgb8(20, 20, 20), thickness: 2);
  }
  for (var i = 0; i < w * h ~/ 50; i++) {
    final v = rnd.nextInt(255);
    image.setPixelRgb(rnd.nextInt(w), rnd.nextInt(h), v, v, v);
  }
  return blur ? img.gaussianBlur(image, radius: 6) : image;
}

Uint8List _rgbaOf(img.Image image) =>
    image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);

void main() {
  group('sampleToWorkingWidth', () {
    for (final size in [(1224, 1632), (2448, 3264), (500, 300), (640, 853)]) {
      test('picks the pixels copyResize picks at ${size.$1}x${size.$2}', () {
        final src = _page(size.$1, size.$2, seed: size.$1);
        final expected = img.copyResize(src, width: 640);
        final got = sampleToWorkingWidth(_rgbaOf(src), size.$1, size.$2);
        expect(got.width, expected.width);
        expect(got.height, expected.height);
        expect(got.rgba, _rgbaOf(expected));
      });
    }
  });

  group('analysis matches the implementation the thresholds were tuned on', () {
    final cases = <String, img.Image>{
      'sharp page': _page(1224, 1632),
      'blurred page': _page(1224, 1632, seed: 2, blur: true),
      'dark frame': img.fill(img.Image(width: 900, height: 1200),
          color: img.ColorRgb8(8, 8, 8)),
      'landscape page': _page(1632, 1224, seed: 3),
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        final src = entry.value;
        final reference = _referenceAnalyse(src);
        final viaRgba = analyseWorkingRgba(
            sampleToWorkingWidth(_rgbaOf(src), src.width, src.height));
        final viaImage = analyseDecodedScan(src.clone());
        for (final got in [viaRgba, viaImage]) {
          expect(got.blurScore, reference.blurScore); // bit-for-bit
          expect(got.isBlurry, reference.isBlurry);
          expect(got.isDarkOrOccluded, reference.isDarkOrOccluded);
          expect(got.form.toString(), reference.form.toString());
        }
      });
    }

    test('the blurred page really is called blurry, the sharp one is not', () {
      expect(analyseDecodedScan(_page(1224, 1632)).isBlurry, isFalse);
      expect(
          analyseDecodedScan(_page(1224, 1632, seed: 2, blur: true)).isBlurry,
          isTrue);
    });
  });

  group('analyseCaptureFile (native decode)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('scan_analysis'));
    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('an EXIF-rotated capture is analysed upright', (tester) async {
      final upright = _page(1224, 1632, seed: 4);
      final stored = img.copyRotate(upright, angle: -90); // landscape pixels
      stored.exif.imageIfd.orientation = 6; // "rotate 90 CW to display"
      final rotatedPath = '${dir.path}/rotated.jpg';
      final uprightPath = '${dir.path}/upright.jpg';
      File(rotatedPath).writeAsBytesSync(img.encodeJpg(stored, quality: 95));
      File(uprightPath).writeAsBytesSync(img.encodeJpg(upright, quality: 95));

      await tester.runAsync(() async {
        final reference = analyseScan(File(rotatedPath).readAsBytesSync());
        final fromRotated = await analyseCaptureFile(rotatedPath);
        final fromUpright = await analyseCaptureFile(uprightPath);
        // Different JPEG decoders round a little differently; the score must
        // land within a couple of percent of the Dart decoder's.
        expect(fromRotated.blurScore,
            closeTo(reference.blurScore, reference.blurScore * 0.02));
        expect(fromRotated.isBlurry, reference.isBlurry);
        expect(fromRotated.form.match, reference.form.match);
        // The form grid is orientation-sensitive: an unrotated (landscape)
        // decode would not reproduce the upright photo's grid measurements.
        expect(fromRotated.form.toString(), fromUpright.form.toString());
      });
    });

    testWidgets('a missing or unreadable file is inconclusive, never a throw',
        (tester) async {
      final junk = '${dir.path}/junk.jpg';
      File(junk).writeAsBytesSync([1, 2, 3, 4]);
      await tester.runAsync(() async {
        final missing = await analyseCaptureFile('${dir.path}/gone.jpg');
        final garbage = await analyseCaptureFile(junk);
        for (final r in [missing, garbage]) {
          expect(r.isBlurry, isFalse);
          expect(r.isDarkOrOccluded, isFalse);
          expect(r.form.match, FormCheck.unknown.match);
        }
      });
    });
  });
}

// ── The implementation before the speed-up, copied verbatim ─────────────────

ScanAnalysis _referenceAnalyse(img.Image decoded) {
  final gray = img.grayscale(img.copyResize(decoded, width: 640));
  var lumSum = 0.0;
  final pixelCount = gray.width * gray.height;
  for (final p in gray) {
    lumSum += p.luminance;
  }
  final avgLum = pixelCount > 0 ? lumSum / pixelCount : 255.0;
  final isDarkOrOccluded = avgLum < 30.0;
  final form = isDarkOrOccluded ? FormCheck.noPage : _referenceForm(gray);
  final blurScore = _referenceLaplacian(gray);
  return ScanAnalysis(
    isBlurry: blurScore < 200.0,
    blurScore: blurScore,
    form: form,
    isDarkOrOccluded: isDarkOrOccluded,
  );
}

FormCheck _referenceForm(img.Image gray) {
  final locate = _referenceMinPool(gray, 160, 214);
  final box = paperBoxOf(locate, 160, 214);
  if (box == null) return FormCheck.noPage;
  final sx = gray.width / 160;
  final sy = gray.height / 214;
  final page = _referenceMinPool(gray, kPageWidth, kPageHeight,
      fromX: (box.left * sx).floor(),
      fromY: (box.top * sy).floor(),
      toX: (box.right * sx).ceil(),
      toY: (box.bottom * sy).ceil());
  return detectSsForm2(page);
}

double _referenceLaplacian(img.Image gray) {
  const laplacian = [0, 1, 0, 1, -4, 1, 0, 1, 0];
  final edges = img.convolution(gray, filter: laplacian);
  var sum = 0.0;
  var sumSq = 0.0;
  final count = edges.width * edges.height;
  if (count == 0) return 0;
  for (final pixel in edges) {
    final l = pixel.luminance.toDouble();
    sum += l;
    sumSq += l * l;
  }
  final mean = sum / count;
  return (sumSq / count) - (mean * mean);
}

Uint8List _referenceMinPool(img.Image gray, int outW, int outH,
    {int fromX = 0, int fromY = 0, int? toX, int? toY}) {
  final x0 = fromX.clamp(0, gray.width - 1);
  final y0 = fromY.clamp(0, gray.height - 1);
  final x1 = (toX ?? gray.width).clamp(x0 + 1, gray.width);
  final y1 = (toY ?? gray.height).clamp(y0 + 1, gray.height);
  final out = Uint8List(outW * outH)..fillRange(0, outW * outH, 255);
  final blockW = (x1 - x0) / outW;
  final blockH = (y1 - y0) / outH;
  if (blockW <= 0 || blockH <= 0) return out;
  for (var y = y0; y < y1; y++) {
    final gy = ((y - y0) / blockH).floor().clamp(0, outH - 1);
    final row = gy * outW;
    for (var x = x0; x < x1; x++) {
      final gx = ((x - x0) / blockW).floor().clamp(0, outW - 1);
      final l = gray.getPixel(x, y).luminance.toInt();
      final i = row + gx;
      if (l < out[i]) out[i] = l;
    }
  }
  return out;
}
