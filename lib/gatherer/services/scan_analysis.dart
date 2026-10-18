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
//
// The decode itself is no longer done in Dart. Since camera 0.11 the still is
// a full-sensor 8 MP JPEG, usually with its rotation in an EXIF tag, and
// package:image took ~5 s on a desktop (several times that on the phone) to
// decode, rotate and shrink it -- the "ANALYZING SHARPNESS..." that never
// ended. [analyseCaptureFile] has the engine's native decoder do it (~0.1 s,
// EXIF applied), samples the 640px working image out of the result with
// exactly the pixels img.copyResize used to pick, and runs the maths on a
// background isolate. Same input to the same checks, so the same verdicts.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, debugPrint, visibleForTesting;
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

  /// True when the image is too dark or the camera lens is occluded.
  final bool isDarkOrOccluded;

  const ScanAnalysis({
    required this.isBlurry,
    required this.blurScore,
    required this.form,
    this.isDarkOrOccluded = false,
  });

  /// Used when the image cannot be decoded at all. Claims nothing: a decode
  /// failure is not evidence the photo is blurry or that the form is wrong.
  static const ScanAnalysis inconclusive = ScanAnalysis(
    isBlurry: false,
    blurScore: 0,
    form: FormCheck.unknown,
    isDarkOrOccluded: false,
  );

  @override
  String toString() => 'ScanAnalysis(blur=${blurScore.toStringAsFixed(1)} '
      'isBlurry=$isBlurry, dark=$isDarkOrOccluded, $form)';
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
  return analyseDecodedScan(decoded);
}

/// Analyse the captured photo at [path]: native decode, then the checks on a
/// background isolate. This is what the scanner runs after every capture.
///
/// Never throws. If the native decoder cannot read the file the slow Dart
/// path is tried instead (still off the UI thread), and if that fails too the
/// result is [ScanAnalysis.inconclusive] -- a check must never cost a scan.
Future<ScanAnalysis> analyseCaptureFile(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final working = await _decodeWorkingRgba(bytes);
    if (working != null) return await compute(analyseWorkingRgba, working);
    return await compute(analyseScan, bytes);
  } catch (_) {
    return ScanAnalysis.inconclusive;
  }
}

/// Decode [bytes] with the engine's codec (EXIF orientation applied, as
/// img.decodeJpg does) and reduce it to the working width. Null when the
/// codec cannot read the image.
///
/// The full-size decode is deliberate. Asking the codec for 640px directly is
/// faster still, but it averages pixels together on the way down, which
/// smooths away the fine edges the blur cutoff was tuned against: measured on
/// the OMR sample corpus it cut the blur score to about a third and flagged
/// 97 of 165 photos as blurry where the tuned path flags 29.
Future<({Uint8List rgba, int width, int height})?> _decodeWorkingRgba(
    Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec();
    final watch = Stopwatch()..start();
    image = (await codec.getNextFrame()).image;
    final decoded = watch.elapsedMilliseconds;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final readBack = watch.elapsedMilliseconds - decoded;
    // A few milliseconds of copying on this isolate, so that only the 2 MB
    // working image -- not the 32-52 MB decode -- is sent to the background
    // one. The only part of the analysis that runs on the UI isolate.
    final sampleWatch = Stopwatch()..start();
    final working = sampleToWorkingWidth(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      image.width,
      image.height,
    );
    debugPrint('ScanPerf: analysis native decode ${decoded}ms, '
        'read-back ${readBack}ms, sampling on UI isolate '
        '${sampleWatch.elapsedMilliseconds}ms '
        '(${image.width}x${image.height})');
    return working;
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Nearest-neighbour reduction of an RGBA buffer to [_workingWidth] wide,
/// picking exactly the source pixels img.copyResize(width: 640) picks -- the
/// blur cutoff was tuned on that sampling, so it has to stay the same.
@visibleForTesting
({Uint8List rgba, int width, int height}) sampleToWorkingWidth(
    Uint8List rgba, int width, int height) {
  const outW = _workingWidth;
  final outH = (outW * (height / width)).round();
  if (outW == width && outH == height) {
    return (rgba: rgba, width: width, height: height);
  }
  // One RGBA pixel per 32-bit word. The view needs 4-byte alignment.
  final aligned = rgba.offsetInBytes % 4 == 0 ? rgba : Uint8List.fromList(rgba);
  final src = aligned.buffer.asUint32List(aligned.offsetInBytes, width * height);
  final out = Uint32List(outW * outH);
  final scaleX = Int32List(outW);
  for (var x = 0; x < outW; x++) {
    scaleX[x] = (x * width) ~/ outW;
  }
  for (var y = 0; y < outH; y++) {
    final row = ((y * height) ~/ outH) * width;
    final o = y * outW;
    for (var x = 0; x < outW; x++) {
      out[o + x] = src[row + scaleX[x]];
    }
  }
  return (rgba: out.buffer.asUint8List(), width: outW, height: outH);
}

/// [analyseScan] for an RGBA image already at the working width (see
/// [sampleToWorkingWidth]). Top-level so it can be handed to compute().
ScanAnalysis analyseWorkingRgba(({Uint8List rgba, int width, int height}) w) {
  return analyseDecodedScan(img.Image.fromBytes(
    width: w.width,
    height: w.height,
    bytes: w.rgba.buffer,
    bytesOffset: w.rgba.offsetInBytes,
    numChannels: 4,
  ));
}

/// [analyseScan] for an image that is already decoded.
ScanAnalysis analyseDecodedScan(img.Image decoded) {
  // Downscale once, grayscale once. Both checks read luminance only.
  final gray = _Gray.of(
      img.grayscale(img.copyResize(decoded, width: _workingWidth)));

  // Check average luminance for pitch dark / lens occlusion
  var lumSum = 0.0;
  final pixelCount = gray.width * gray.height;
  for (final v in gray.v) {
    lumSum += _lum[v];
  }
  final avgLum = pixelCount > 0 ? lumSum / pixelCount : 255.0;
  final isDarkOrOccluded = avgLum < 30.0;

  // Neither check modifies `gray`. (The old blur check ran img.convolution(),
  // which rewrites its input in place, so the form grid had to be sampled
  // before it -- the byte-plane version below leaves the image alone.)
  final form = isDarkOrOccluded ? FormCheck.noPage : _checkForm(gray);
  final blurScore = _varianceOfLaplacian(gray);

  return ScanAnalysis(
    isBlurry: blurScore < _blurCutoff,
    blurScore: blurScore,
    form: form,
    isDarkOrOccluded: isDarkOrOccluded,
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
FormCheck _checkForm(_Gray gray) {
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
///
/// The standard 3x3 Laplacian kernel (0 1 0 / 1 -4 1 / 0 1 0), worked out
/// directly on the bytes. It reproduces img.convolution() exactly -- edge
/// pixels repeat, the response is clamped to 0..255 -- at a fraction of the
/// cost: that call was most of the analysis time.
double _varianceOfLaplacian(_Gray gray) {
  final w = gray.width;
  final h = gray.height;
  final v = gray.v;
  final count = w * h;
  if (count == 0) return 0;

  var sum = 0.0;
  var sumSq = 0.0;
  for (var y = 0; y < h; y++) {
    final up = (y == 0 ? 0 : y - 1) * w;
    final row = y * w;
    final down = (y == h - 1 ? y : y + 1) * w;
    for (var x = 0; x < w; x++) {
      final left = x == 0 ? 0 : x - 1;
      final right = x == w - 1 ? x : x + 1;
      var e = v[up + x] +
          v[row + left] +
          v[row + right] +
          v[down + x] -
          4 * v[row + x];
      if (e < 0) {
        e = 0;
      } else if (e > 255) {
        e = 255;
      }
      final l = _lum[e];
      sum += l;
      sumSq += l * l;
    }
  }

  final mean = sum / count;
  return (sumSq / count) - (mean * mean); // E[X^2] - E[X]^2
}

/// One luminance byte per pixel of a grayscale image. Reading these directly
/// instead of going through img.Image pixel objects is what makes the checks
/// cheap.
class _Gray {
  final Uint8List v;
  final int width;
  final int height;

  const _Gray(this.v, this.width, this.height);

  /// [gray] must already be grayscale (r == g == b).
  factory _Gray.of(img.Image gray) {
    final g = gray.format == img.Format.uint8
        ? gray
        : gray.convert(format: img.Format.uint8);
    final v = Uint8List(g.width * g.height);
    var i = 0;
    for (final p in g) {
      v[i++] = p.r.toInt();
    }
    return _Gray(v, g.width, g.height);
  }
}

/// What img.Pixel.luminance reports for a gray pixel of value v, so sums come
/// out exactly as they did when the pixels were read one object at a time.
final List<double> _lum = List<double>.generate(
    256, (v) => img.getLuminanceRgb(v, v, v).toDouble(),
    growable: false);
final List<int> _lumInt =
    List<int>.generate(256, (v) => _lum[v].toInt(), growable: false);

/// Reduce a region of [gray] to an [outW] x [outH] grid, keeping the DARKEST
/// pixel in each block rather than the average.
///
/// The minimum matters more than it looks. A table ruling is a hairline:
/// average it with the white paper around it and it vanishes at this scale,
/// taking the whole fingerprint with it. Taking the minimum keeps every thin
/// dark line intact, which is exactly the structure being looked for.
Uint8List _minPool(
  _Gray gray,
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
      final l = _lumInt[gray.v[y * gray.width + x]];
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
  final gray = _Gray.of(
      img.grayscale(img.copyResize(decoded, width: _workingWidth)));
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
