// Tests for the pieces of the SS Form 2 check that are settled.
//
// The end-to-end verdict is NOT asserted here yet. It is still being tuned
// against real photographs (see real_scan_probe_test.dart), and a test that
// pinned today's behaviour would only make the tuning harder. What is covered
// is the machinery underneath it, where the contracts are already firm --
// including the two behaviours that must never regress, because both were
// found the hard way: an inconclusive frame must read as `unknown` rather than
// as a rejection, and binarisation must be local rather than global.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/gatherer/services/form_signature.dart';

Uint8List _filled(int value, {int w = kPageWidth, int h = kPageHeight}) =>
    Uint8List(w * h)..fillRange(0, w * h, value);

void main() {
  group('paperBoxOf', () {
    test('finds a bright sheet on a dark desk', () {
      const w = 160;
      const h = 214;
      final g = _filled(40, w: w, h: h);
      for (var y = 30; y < 180; y++) {
        for (var x = 20; x < 140; x++) {
          g[y * w + x] = 230;
        }
      }

      final box = paperBoxOf(g, w, h)!;
      expect(box.left, closeTo(20, 3));
      expect(box.top, closeTo(30, 3));
      expect(box.right, closeTo(140, 3));
      expect(box.bottom, closeTo(180, 3));
    });

    test('returns null on a frame with no bright region', () {
      expect(paperBoxOf(_filled(40, w: 160, h: 214), 160, 214), isNull);
    });

    test('ignores a bright patch too small to be a sheet', () {
      const w = 160;
      const h = 214;
      final g = _filled(40, w: w, h: h);
      for (var y = 10; y < 30; y++) {
        for (var x = 10; x < 30; x++) {
          g[y * w + x] = 240;
        }
      }
      expect(paperBoxOf(g, w, h), isNull);
    });
  });

  group('binariseAdaptive', () {
    test('finds a faint line under a lighting gradient', () {
      // The case a global threshold cannot handle, and the reason this function
      // exists: one end of the page is in shade, and the ruling in the bright
      // end is lighter than the PAPER in the dark end. Any single cutoff either
      // floods the shaded end or loses the line in the lit one.
      const w = 200;
      const h = 200;
      final g = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          g[y * w + x] = 90 + (x * 150 ~/ w); // paper, 90 -> 240
        }
      }
      for (var x = 0; x < w; x++) {
        g[100 * w + x] = (g[100 * w + x] - 40).clamp(0, 255); // the ruling
      }

      final mask = binariseAdaptive(g, w, h);

      // The ruling is found across the whole width, dark end and bright end
      // alike, and the blank paper either side of it is not.
      for (final x in [10, 60, 120, 190]) {
        expect(mask[100 * w + x], 1, reason: 'ruling missed at x=$x');
        expect(mask[80 * w + x], 0, reason: 'blank paper marked at x=$x');
      }
    });

    test('marks nothing on blank paper', () {
      const w = 100;
      const h = 100;
      final mask = binariseAdaptive(_filled(220, w: w, h: h), w, h);
      expect(mask.every((v) => v == 0), isTrue);
    });
  });

  group('detectSsForm2', () {
    test('questions a blank page instead of waving it through', () {
      // A blank sheet, or the lens covered. This was silent at first, on the
      // reasoning that a warning would fire every time the gatherer lowered
      // the phone -- wrong, because the check runs AFTER the shutter. Left
      // silent, a photo of the desk reached the n8n queue unflagged.
      final result = detectSsForm2(_filled(220));

      expect(result.match, FormMatch.noPage);
      expect(result.isSuspect, isTrue);
    });

    test('stays silent when the check itself could not run', () {
      // An undecodable image is our failure, not the gatherer's, and it says
      // nothing about the paper. Distinct from noPage on purpose.
      final result = detectSsForm2(Uint8List(10));

      expect(result.match, FormMatch.unknown);
      expect(result.isSuspect, isFalse,
          reason: 'our own failure must not cost the gatherer a scan');
    });
  });
}
