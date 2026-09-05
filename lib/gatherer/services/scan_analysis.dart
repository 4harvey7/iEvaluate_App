// scan_analysis.dart
// Everything the scanner needs to know about a captured photo, worked out in
// one pass on a background isolate.
//
// Two things used to be true of the preview screen and both were bad. The blur
// check decoded a 12-megapixel JPEG on the UI thread, which is the hitch the
// gatherer feels between pressing the shutter and seeing the photo. And there
// was no check at all on WHAT was photographed, so a spreadsheet on a laptop
// screen went into the n8n queue looking exactly like an evaluation form.
//
// Both checks want the same decoded, downscaled, grayscale image, so they now
// share one. Adding the document check costs a few milliseconds on top of a
// decode that had to happen anyway -- the reason it can be described as free.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;

import 'form_signature.dart';

/// Everything learned about one captured frame.
class ScanAnalysis {
  /// True when the image is too soft for OCR to read reliably.
  final bool isBlurry;

  /// Variance of the Laplacian. Higher is sharper. Kept for tuning -- the
  /// cutoff is a guess until someone measures it on the real phones.
  final double blurScore;

  /// Whether the paper looks like an SS Form 2.
  final FormCheck form;

  const ScanAnalysis({
    required this.isBlurry,
    required this.blurScore,
    required this.form,
  });

  /// Used when the image cannot be decoded at all. Claims nothing: a decode
  /// failure is not evidence the photo is blurry or that the form is wrong.
  static const ScanAnalysis inconclusive = ScanAnalysis(
    isBlurry: false,
    blurScore: 0,
    form: FormCheck.unknown,
  );

  @override
  String toString() => 'ScanAnalysis(blur=${blurScore.toStringAsFixed(1)} '
      'isBlurry=$isBlurry, $form)';
}

/// Sharpness cutoff on the variance of the Laplacian, measured at 640px wide.
/// 150-250 is the usual safe band for document photos; 200 sits in the middle.
const double _blurCutoff = 200.0;

/// Width the image is reduced to before any analysis. Enough detail for both
/// checks, small enough that the maths is irrelevant next to the decode.
const int _workingWidth = 640;

/// Coarse grid used only to find where the paper is. It needs to resolve a
/// bright rectangle against a dark desk and nothing finer, so it can stay small.
const int _locateWidth = 160;
const int _locateHeight = 214;

/// Whether a mismatch verdict is allowed to reach the gatherer.
///
/// On, based on measurement rather than hope. Swept across the OMR project's
/// sample photographs -- 58 real forms and about 90 images that are not forms
/// (field crops, projection plots, binarised debug renders, OCR composites and
/// a few unrelated photographs) -- the check matched 55 of the 58 forms and
/// raised NOT ONE false positive.
///
/// That asymmetry is the one worth having. A wrong document is caught, and the
/// cost of the remaining three is an extra tap on about one scan in twenty --
/// a dialog the gatherer can dismiss, never a refusal.
///
/// If this has to be turned off again, the analysis keeps running and keeps
/// logging its measurements after every capture; those numbers off the real
/// phones are what any retuning needs.
const bool kFormCheckEnforced = true;

/// Analyse one captured JPEG. Top-level and side-effect free so it can be
/// handed straight to compute().
ScanAnalysis analyseScan(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) return ScanAnalysis.inconclusive;

  // Downscale once, grayscale once. Both checks read luminance only.
  final gray = img.grayscale(img.copyResize(decoded, width: _workingWidth));

  // ORDER MATTERS. img.convolution() rewrites the image it is handed rather
  // than returning a fresh one, so _varianceOfLaplacian leaves `gray` holding
  // an edge map -- near black everywhere. Sampling the form grid after it
  // silently analysed that edge map instead of the photo, and every real scan
  // came back "unknown". Sample first, blur second.
  final form = _checkForm(gray);
  final blurScore = _varianceOfLaplacian(gray);

  return ScanAnalysis(
    isBlurry: blurScore < _blurCutoff,
    blurScore: blurScore,
    form: form,
  );
}

/// Find the page, then hand the form check a normalised picture of just that.
///
/// The two-step matters more than it looks. Photographed from arm's length the
/// paper covers maybe half the frame, and the rating table only a fifth of it --
/// on a single fixed grid the table's twenty-odd rulings land less than three
/// cells apart and merge into one solid band, which reads as a filled rectangle
/// rather than a table. Cropping to the page and resampling to a fixed size
/// puts the table at the same scale every time, however far back the gatherer
/// stood. It is the cheap equivalent of the pipeline's isolate_paper() warp.
FormCheck _checkForm(img.Image gray) {
  final locate = _minPool(gray, _locateWidth, _locateHeight);
  final box = paperBoxOf(locate, _locateWidth, _locateHeight);
  // No sheet of paper in the shot. Reported rather than shrugged off -- see
  // FormMatch.noPage for why this used to be silent and should not have been.
  if (box == null) return FormCheck.noPage;

  // Back to source pixels. The locate grid is a plain scaling of the image, so
  // this is just the inverse of that scale.
  final sx = gray.width / _locateWidth;
  final sy = gray.height / _locateHeight;
  final page = _minPool(
    gray,
    kPageWidth,
    kPageHeight,
    fromX: (box.left * sx).floor(),
    fromY: (box.top * sy).floor(),
    toX: (box.right * sx).ceil(),
    toY: (box.bottom * sy).ceil(),
  );
  return detectSsForm2(page);
}

/// Variance of the Laplacian -- the standard sharpness measure. Higher
/// variance means stronger edges, which means less blur.
double _varianceOfLaplacian(img.Image gray) {
  // Standard 3x3 Laplacian kernel: second derivative, so it responds to edges.
  const laplacian = [
    0, 1, 0, //
    1, -4, 1, //
    0, 1, 0, //
  ];
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
  return (sumSq / count) - (mean * mean); // E[X^2] - E[X]^2
}

/// Reduce a region of [gray] to an [outW] x [outH] grid, keeping the DARKEST
/// pixel in each block rather than the average.
///
/// The minimum matters more than it looks. A table ruling is a hairline:
/// average it with the white paper around it and it vanishes at this scale,
/// taking the whole fingerprint with it. Taking the minimum keeps every thin
/// dark line intact, which is exactly the structure being looked for.
Uint8List _minPool(
  img.Image gray,
  int outW,
  int outH, {
  int fromX = 0,
  int fromY = 0,
  int? toX,
  int? toY,
}) {
  final x0 = fromX.clamp(0, gray.width - 1);
  final y0 = fromY.clamp(0, gray.height - 1);
  final x1 = (toX ?? gray.width).clamp(x0 + 1, gray.width);
  final y1 = (toY ?? gray.height).clamp(y0 + 1, gray.height);

  final out = Uint8List(outW * outH)..fillRange(0, outW * outH, 255);
  final blockW = (x1 - x0) / outW;
  final blockH = (y1 - y0) / outH;
  if (blockW <= 0 || blockH <= 0) return out;

  // One pass over the region, folding each pixel into its block.
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

/// Exposed so a probe can dump exactly what the check sees.
@visibleForTesting
Uint8List debugPageGrid(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) return Uint8List(kPageWidth * kPageHeight);
  final gray = img.grayscale(img.copyResize(decoded, width: _workingWidth));
  final locate = _minPool(gray, _locateWidth, _locateHeight);
  final box = paperBoxOf(locate, _locateWidth, _locateHeight);
  if (box == null) return Uint8List(kPageWidth * kPageHeight);
  final sx = gray.width / _locateWidth;
  final sy = gray.height / _locateHeight;
  return _minPool(
    gray,
    kPageWidth,
    kPageHeight,
    fromX: (box.left * sx).floor(),
    fromY: (box.top * sy).floor(),
    toX: (box.right * sx).ceil(),
    toY: (box.bottom * sy).ceil(),
  );
}
