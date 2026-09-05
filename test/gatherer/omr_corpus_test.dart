// Measures the SS Form 2 check against real photographs.
//
// The corpus is the OMR project's own sample folder, which is not part of this
// repository -- so this test SKIPS unless that folder is present. It is kept
// because the thresholds in form_signature.dart were derived from these
// numbers, and without a way to reproduce them the constants are just magic.
//
// Point _omrDir at the OMR checkout to run it. Expected as of writing:
// 55 of 58 real forms matched, zero false positives across ~90 non-forms.
@Tags(['corpus'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ievaluateapp_final/gatherer/services/form_signature.dart';

/// The OMR project checkout holding the sample scans.
const _omrDir = r'C:\Projects\last-man staning original omer and ocr';

final _sep = Platform.pathSeparator;

/// A file is a photograph of a real form if it is one of the loose sample
/// scans, or one of the pipeline's own debug renders of a whole page or table.
/// Everything else under the folder -- field crops, projection plots,
/// binarised intermediates, unrelated photographs -- is not.
bool _isForm(String relativePath, String basename) =>
    !relativePath.contains(_sep) ||
    relativePath.startsWith('scans$_sep') ||
    basename.startsWith('table_') ||
    basename == 'result_paper_000.jpg' ||
    basename == 'result_fields_000.jpg';

void main() {
  test('matches real forms and rejects everything else', () {
    final root = Directory(_omrDir);
    if (!root.existsSync()) {
      markTestSkipped('OMR sample corpus not present at $_omrDir');
      return;
    }

    var forms = 0;
    var formsMatched = 0;
    var nonForms = 0;
    final falsePositives = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.jpg')) {
        continue;
      }
      final relative = entity.path.substring(_omrDir.length + 1);
      final basename = entity.uri.pathSegments.last;
      final grid = _normalisedPage(entity);
      final result =
          grid == null ? FormCheck.unknown : detectSsForm2(grid);

      if (_isForm(relative, basename)) {
        forms++;
        if (result.match == FormMatch.match) formsMatched++;
      } else {
        nonForms++;
        if (result.match == FormMatch.match) {
          falsePositives.add('$relative -> $result');
        }
      }
    }

    // ignore: avoid_print
    print('forms matched $formsMatched/$forms, '
        'false positives ${falsePositives.length}/$nonForms');

    // A false positive is the failure that matters: it waves a wrong document
    // through into the term's scores, where nothing downstream will catch it.
    expect(falsePositives, isEmpty);

    // A false negative only costs the gatherer a dismissed dialog, so the bar
    // here is a floor rather than a target -- but a sharp drop means something
    // in the geometry has broken.
    expect(formsMatched / forms, greaterThan(0.90));
  }, timeout: const Timeout(Duration(minutes: 25)));
}

/// Mirrors what scan_analysis does: find the page, resample it to the fixed
/// grid the check expects.
Uint8List? _normalisedPage(File file) {
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) return null;
  final gray = img.grayscale(img.copyResize(decoded, width: 640));
  final locate = _minPool(gray, 160, 214);
  final box = paperBoxOf(locate, 160, 214);
  if (box == null) return null;
  final sx = gray.width / 160;
  final sy = gray.height / 214;
  return _minPool(gray, kPageWidth, kPageHeight,
      fromX: (box.left * sx).floor(),
      fromY: (box.top * sy).floor(),
      toX: (box.right * sx).ceil(),
      toY: (box.bottom * sy).ceil());
}

Uint8List _minPool(img.Image gray, int outW, int outH,
    {int fromX = 0, int fromY = 0, int? toX, int? toY}) {
  final x0 = fromX.clamp(0, gray.width - 1);
  final y0 = fromY.clamp(0, gray.height - 1);
  final x1 = (toX ?? gray.width).clamp(x0 + 1, gray.width);
  final y1 = (toY ?? gray.height).clamp(y0 + 1, gray.height);
  final out = Uint8List(outW * outH)..fillRange(0, outW * outH, 255);
  final blockW = (x1 - x0) / outW;
  final blockH = (y1 - y0) / outH;
  for (var y = y0; y < y1; y++) {
    final gy = ((y - y0) / blockH).floor().clamp(0, outH - 1);
    for (var x = x0; x < x1; x++) {
      final gx = ((x - x0) / blockW).floor().clamp(0, outW - 1);
      final l = gray.getPixel(x, y).luminance.toInt();
      final i = gy * outW + gx;
      if (l < out[i]) out[i] = l;
    }
  }
  return out;
}
