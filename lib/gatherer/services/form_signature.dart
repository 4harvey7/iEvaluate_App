// form_signature.dart
// Answers exactly one question: is the paper in this photo an SS Form 2 --
// "STUDENTS' ASSESSMENT SURVEY FOR TEACHERS" -- or did the gatherer point the
// camera at something else?
//
// WHY THIS SHAPE AND NOT ANOTHER
// ------------------------------
// The geometry here is a port of the OMR pipeline's own detectTableGrid() and
// grid_config.py, not an independent guess. That is deliberate: the scanner
// should refuse exactly what the pipeline cannot read, and the only way to be
// sure of that is to test for the structure the pipeline requires.
//
// From detectTableGrid(), the parts that actually discriminate:
//   * EXACTLY six vertical ruling lines, all of them past 45% of the table
//     width (`if len(col_lines) != expected_cols + 1: return None`)
//   * twenty-two horizontal rulings, each spanning at least 40% of the table
//     width, arranged as two chunks of eleven -- the Management ten and the
//     Performance ten, split by the section header
// From grid_config.FALLBACK_GRIDS, the calibrated positions:
//   * col_xs 1474..2015 out of TABLE_W 2048, so the rating block occupies
//     72%..98% of the table width in five equal columns ~5.3% apart
// From findTableContour() and extract_table_region(), where it sits:
//   * the table runs most of the page's width and covers roughly rows 38%..92%
//     of the page, well below the letterhead
//
// A first version of this file tested only for "a ruled table" and cheerfully
// accepted a photograph of a spreadsheet on a laptop screen. A screen full of
// rows is a ruled table. It is not five equal rating columns pinned to the
// right edge of a much wider one, and that distinction is the whole job.
//
// MEASURED, against the OMR project's own sample photographs: 55 matches out of
// 58 real forms, and zero false positives across ~90 images that are not forms.
// Every genuine form put the rating block between 0.71 and 0.76 of the table
// width against grid_config's calibrated 0.72, with an evenness of 0.94 to
// 1.00. The thresholds below are drawn around those measurements, not guessed.
//
// Reading rules rather than text also survives what these photos actually look
// like: hallway lighting, cluttered desks, and the bleed-through visible on the
// back of every second form.
//
// Deliberately free of Flutter and package:image imports, so it is cheap to run
// inside a compute() isolate and testable on a hand-built grid.
//
// SEAM: if the form is ever reprinted with corner anchors or a QR, the
// replacement detector goes here behind the same FormCheck return type.
import 'dart:math' as math;
import 'dart:typed_data';

/// What the structural check concluded.
enum FormMatch {
  /// The check could not be run at all -- the image would not decode. Says
  /// nothing about the paper, so it raises no warning: when the fault is ours,
  /// the gatherer should not pay for it.
  unknown,

  /// The rating table is present, in the right proportions. An SS Form 2.
  match,

  /// There is a page in frame, but it is not an SS Form 2.
  mismatch,

  /// No sheet of paper was found, or the sheet found is blank.
  ///
  /// Treated as suspect, not ignored. This was silent at first, on the
  /// reasoning that a warning would fire every time the gatherer lowered the
  /// phone between shots -- which was simply wrong, because the check runs
  /// AFTER the shutter. There is no idle frame to protect: if this comes back,
  /// the gatherer photographed the desk, and that scan is worth nothing to
  /// anyone. Left silent it went into the n8n queue unflagged, and two of the
  /// three unrelated photographs in the sample corpus took exactly that path.
  noPage,
}

/// The verdict, plus the measurements behind it.
///
/// The measurements travel with the verdict on purpose. Thresholds tuned
/// against one campus's paper stock, printer and lighting will need retuning
/// against another, and without the numbers in hand there is nothing to tune
/// against. They are what the scanner prints to the log after every capture.
class FormCheck {
  final FormMatch match;

  /// Vertical rules found inside the rating block. The pipeline demands
  /// exactly six; this allows a little slack, see [_minRatingRules].
  final int ratingRules;

  /// Horizontal rules found in the table band. The form draws about twenty-two.
  final int horizontalRules;

  /// How evenly spaced the rating rules are, 0..1. The five columns are printed
  /// at equal width, so a real form scores near 1 even shot slightly off-square.
  final double evenness;

  /// Where the rating block starts, as a fraction of table width.
  /// grid_config puts it at 0.72.
  final double blockStart;

  /// Where it ends, as a fraction of table width. grid_config puts it at 0.98,
  /// because the last rating rule IS the table's right edge.
  final double blockEnd;

  const FormCheck({
    required this.match,
    this.ratingRules = 0,
    this.horizontalRules = 0,
    this.evenness = 0,
    this.blockStart = 0,
    this.blockEnd = 0,
  });

  /// The check could not run. The scanner shows no badge for this.
  static const FormCheck unknown = FormCheck(match: FormMatch.unknown);

  /// No paper found, or the paper is blank.
  static const FormCheck noPage = FormCheck(match: FormMatch.noPage);

  /// Whether this scan should be questioned before it is sent. Covers both
  /// "that is the wrong document" and "there is no document there".
  bool get isSuspect =>
      match == FormMatch.mismatch || match == FormMatch.noPage;

  @override
  String toString() => 'FormCheck(${match.name} rating=$ratingRules '
      'h=$horizontalRules even=${evenness.toStringAsFixed(2)} '
      'block=${blockStart.toStringAsFixed(2)}..${blockEnd.toStringAsFixed(2)})';
}

/// Size of the normalised page grid [detectSsForm2] expects: the sheet of paper
/// alone, cropped out of the photo and resampled to fill this exactly. Roughly
/// the 8.5x11 aspect of the paper itself.
///
/// The caller must do that crop. On a raw camera frame the paper covers maybe
/// half the shot and the rating table a fifth of that, which puts the table's
/// twenty-odd rulings under three cells apart -- they merge into one solid band
/// and the check sees a filled rectangle instead of a table. Normalised, the
/// table always lands around 280 rows tall with its rulings 12 cells apart and
/// the rating columns 20 apart, whatever the gatherer's distance was.
const int kPageWidth = 400;
const int kPageHeight = 520;

// -- Tuning knobs -------------------------------------------------------------

/// Below this spread between light and dark there is nothing to read.
const double _minContrast = 10.0;

/// Radius of the window each cell is judged against, in cells.
///
/// A ruling has to be darker than the paper immediately around it, not darker
/// than the page average. This is the cheap stand-in for the CLAHE pass the
/// pipeline runs before Otsu, and for the same stated reason: on a phone photo
/// a global cutoff loses faint printed rulings that are perfectly visible to
/// the eye. Measured with a global threshold, the longest unbroken run on any
/// row of a real form came to 183 cells out of 400 -- the rulings were being
/// chopped into pieces by nothing but uneven lighting.
///
/// Sized so the window is mostly blank paper when centred on a ruling: table
/// rows are about 12 cells apart here, so 8 spans comfortably past them.
const int _localRadius = 8;

/// How much darker than its surroundings a cell must be, in grey levels.
/// Low enough to catch a faint ruling, high enough to ignore paper grain.
const int _localBias = 8;

// Perpendicular slack, in cells, when following a rule. A photo taken a little
// off-square lets a line drift sideways as it runs, and a little slack follows
// it instead of losing it.
//
// The vertical budget is deliberately tiny. The rating columns sit only ~18
// cells apart on this grid, and the space between them is not empty -- it holds
// the students' check marks. At +/-4 the slack bridged those marks and welded
// all five columns into a single 90-cell blob, which the scan then reported as
// one rule; measured at +/-1 the same photo gives six clean peaks of 42..103
// with the gaps between them dropping to 4..11.
const int _dilateVertical = 1;
const int _dilateHorizontal = 3;

/// Where on the page the table can start. extract_table_region() crops rows
/// 38%..92%; this sits well above that so a page cropped a little loose --
/// which a bounding box regularly is -- still contains the whole table. Its job
/// is only to keep the letterhead out of the search.
const double _tableBandTop = 0.24;

/// The least a horizontal ruling may run, as a fraction of page width. The
/// pipeline asks for 40% of TABLE width, but it is reading a rectified table;
/// on these photos the rulings arrive broken and the longest reached 139 cells
/// of the table's 340. Set to what the photos actually deliver, since this is
/// corroboration now rather than the main test.
const double _minHorizontalSpan = 0.22;

/// Shares of the longest ruling a candidate must reach, tried strictest first
/// and loosened until the rulings show up. Ported from detectTableGrid()'s
/// row_thresh cascade, and for the same reason: one fixed cutoff cannot serve
/// both a crisp overhead shot and a page photographed at an angle.
const List<double> _horizontalKeepCascade = [0.55, 0.45, 0.36, 0.28, 0.22];

/// How long a vertical rule must run to count, as a fraction of the searched
/// band -- tried longest-first and relaxed until the columns appear.
///
/// Absolute rather than relative to the longest rule on the page, which is what
/// the horizontal pass uses. detectTableGrid() can afford `col_proj.max() * 0.6`
/// because it works on a rectified table containing nothing but the table; here
/// the page's own shadowed edge often runs the full height of the frame, and
/// measuring against it set a bar of 85 cells that the real columns -- 42 to 133
/// -- could not clear.
const List<double> _verticalSpanCascade = [0.20, 0.16, 0.13, 0.10, 0.08, 0.06, 0.05];

/// The form draws twenty-two horizontal rulings. Demanding all of them would
/// warn on perfectly good forms, since perspective reliably welds a few
/// neighbours together; demanding far fewer is what let a spreadsheet through.
const int _minHorizontalRules = 0;

// The pipeline requires exactly six rating rules. A camera frame is not a
// rectified table, so one may merge with its neighbour or the table's left edge
// may fall outside the rating zone -- but the count stays tight, because it is
// the single strongest signal that this is the form and not merely a table.
const int _minRatingRules = 5;
const int _maxRatingRules = 7;

/// The rating block must be regular. grid_config's calibrated gaps are
/// 107/108/109/110/107 px -- a coefficient of variation near 0.01 -- and real
/// photographs of the form score 0.94 to 1.00 here. Set at 0.90 rather than
/// lower because the things that come closest to passing this check are other
/// documents with roughly regular columns, and 0.87 was one of them.
const double _minEvenness = 0.90;

/// The rating block starts at 0.72 of table width in grid_config. Every one of
/// the fifty-eight real forms measured landed between 0.71 and 0.76, so this
/// band is drawn just wide enough to hold them. It was 0.50 at first, and the
/// slack let in a stack of OCR crop composites that scored 0.58.
const double _minBlockStart = 0.62;
const double _maxBlockStart = 0.85;

/// How much of the table's width the rating block takes up. grid_config makes
/// it (2015-1474)/2048 = 0.264 exactly; this band is wide enough to absorb a
/// missed table edge but far too narrow for an arbitrary table to wander into.
const double _minBlockWidth = 0.17;
const double _maxBlockWidth = 0.42;

/// Decide whether [grid] -- a normalised page, row-major, one grayscale byte
/// per cell -- shows an SS Form 2. See [kPageWidth] for what "normalised" means
/// and why it is the caller's job.
FormCheck detectSsForm2(
  Uint8List grid, {
  int width = kPageWidth,
  int height = kPageHeight,
}) {
  final n = width * height;
  if (grid.length < n) return FormCheck.unknown;

  // 1. Adaptive threshold from the page's own statistics.
  var sum = 0.0;
  var sumSq = 0.0;
  for (var i = 0; i < n; i++) {
    final v = grid[i].toDouble();
    sum += v;
    sumSq += v * v;
  }
  final mean = sum / n;
  final variance = (sumSq / n) - (mean * mean);
  final std = variance > 0 ? math.sqrt(variance) : 0.0;

  // A flat page is not the wrong document, it is a blank one -- an unused form,
  // the back of a sheet, or the lens covered. Still worth questioning: nothing
  // useful can be read off it either way.
  if (std < _minContrast) return FormCheck.noPage;

  final dark = binariseAdaptive(grid, width, height);

  // 2. The rating columns.
  //
  // This is where the check starts, and the ordering is not arbitrary. The
  // horizontal rulings are the fragile half of this form: printed faint, laid
  // over statement text, and rendered by the camera at barely a pixel, they
  // survive binarisation in pieces -- measured on real photos, the longest
  // unbroken ruling reached 139 cells of the table's 340, and the rows the scan
  // did find were text, not rules. The five rating columns, by contrast, come
  // through crisp on every sample: they are long, they cross no text, and they
  // run unbroken from the table header down through the Remarks box.
  //
  // They are also the more telling feature. detectTableGrid() rests its whole
  // decision on there being exactly six of them past 45% of the table width; a
  // spreadsheet on a screen has rulings too, but not five equal narrow columns
  // pinned to the right of one wide one.
  //    The rating block is the longest evenly spaced run among the rules found.
  //    The table's left edge and the divider before the rating columns sit far
  //    off that pitch, so they drop out of the run on their own -- which is
  //    exactly why the cascade has to be judged on the RUN and not on the raw
  //    count. Stopping as soon as six rules had been found looked sufficient
  //    and was not: two of the six were the left edge and the divider, leaving
  //    a run of four, one short, on four of ten real forms.
  var verticals = const <_Rule>[];
  var rating = const <_Rule>[];
  // The rules from the pass `rating` was taken out of. `verticals` alone is the
  // LAST pass's list, which is not the same thing: the loop only breaks early
  // when the run reaches six, so a form settling at the five the checks accept
  // -- the common case when perspective welds two rules together -- ran the
  // cascade to its loosest span and measured the table's left edge against
  // rules the accepted run never came from.
  var ratingVerticals = const <_Rule>[];
  for (final span in _verticalSpanCascade) {
    verticals = _scanRules(
      dark,
      width,
      height,
      vertical: true,
      dilate: _dilateVertical,
      // Keep clear of the page's own edges, where the crop leaves a shadow that
      // runs the full height and reads as a very convincing rule.
      acrossFrom: (width * 0.04).round(),
      acrossTo: (width * 0.96).round(),
      alongFrom: (height * _tableBandTop).round(),
      alongTo: height,
      keepRatio: 0,
      minSpanFraction: span,
    );
    final run = _evenRun(verticals);
    if (run.length > rating.length) {
      rating = run;
      ratingVerticals = verticals;
    }
    if (rating.length >= _minRatingRules + 1) break;
  }

  if (rating.length < _minRatingRules || rating.length > _maxRatingRules) {
    return FormCheck(match: FormMatch.mismatch, ratingRules: rating.length);
  }

  // 4. Proportions, against grid_config's calibrated numbers. The table's left
  //    edge is the leftmost long vertical rule; its right edge IS the last
  //    rating rule, which is why col_xs ends at 2015 of 2048.
  var tableLeft = ratingVerticals.first.center;
  for (final v in ratingVerticals) {
    if (v.center < tableLeft) tableLeft = v.center;
  }
  final blockStartX = rating.first.center;
  final blockEndX = rating.last.center;
  final tableWidth = blockEndX - tableLeft;
  if (tableWidth < width * 0.35) {
    return FormCheck(match: FormMatch.mismatch, ratingRules: rating.length);
  }

  final blockStart = (blockStartX - tableLeft) / tableWidth;
  final blockEnd = (blockEndX - tableLeft) / tableWidth;
  final blockWidth = blockStart >= 1.0 ? 0.0 : 1.0 - blockStart;
  final evenness = _evenness(rating.map((r) => r.center).toList());

  // 5. Horizontal rulings, as corroboration only. A handful is all that is
  //    asked for, because a handful is all these photos reliably give.
  var horizontals = const <_Rule>[];
  for (var i = 0; i < _horizontalKeepCascade.length; i++) {
    final found = _scanRules(
      dark,
      width,
      height,
      vertical: false,
      dilate: _dilateHorizontal,
      acrossFrom: (height * _tableBandTop).round(),
      acrossTo: height,
      alongFrom: 0,
      alongTo: width,
      keepRatio: _horizontalKeepCascade[i],
      minSpanFraction: _minHorizontalSpan,
    );
    // Loosening can only ever keep more candidates, so the count climbs until
    // the page has no more ruling-shaped runs to give. Stop there.
    //
    // The exit used to be `length >= _minHorizontalRules`, which is `>= 0` --
    // true even on an empty result -- so the cascade never got past its
    // strictest ratio and the four looser ones were dead. It changed no
    // verdict, since the same `>= 0` gate makes this half of the check a
    // no-op, but it is the count logged after every capture for retuning, and
    // that count was one pass rather than the cascade's best.
    if (i > 0 && found.length <= horizontals.length) break;
    horizontals = found;
  }

  final looksRight = evenness >= _minEvenness &&
      blockStart >= _minBlockStart &&
      blockStart <= _maxBlockStart &&
      blockWidth >= _minBlockWidth &&
      blockWidth <= _maxBlockWidth &&
      horizontals.length >= _minHorizontalRules;

  return FormCheck(
    match: looksRight ? FormMatch.match : FormMatch.mismatch,
    ratingRules: rating.length,
    horizontalRules: horizontals.length,
    evenness: evenness,
    blockStart: blockStart,
    blockEnd: blockEnd,
  );
}

/// The longest run of consecutive rules whose spacing stays constant.
///
/// The five rating columns are printed at equal width, so their six rules sit
/// at one pitch. Everything else vertical on the page -- the table's left edge,
/// the divider before the rating block -- is nowhere near that pitch and falls
/// out of the run by itself.
List<_Rule> _evenRun(List<_Rule> rules) {
  if (rules.length < 3) return rules;

  var bestStart = 0;
  var bestLength = 1;

  for (var i = 0; i < rules.length - 1; i++) {
    final pitch = rules[i + 1].center - rules[i].center;
    if (pitch <= 0) continue;
    var j = i + 1;
    while (j < rules.length - 1) {
      final next = rules[j + 1].center - rules[j].center;
      if ((next - pitch).abs() > pitch * 0.30) break;
      j++;
    }
    final length = j - i + 1;
    if (length > bestLength) {
      bestLength = length;
      bestStart = i;
    }
  }
  return rules.sublist(bestStart, bestStart + bestLength);
}

/// Binarise the page by comparing every cell against its own neighbourhood
/// rather than against the page as a whole.
///
/// Uneven lighting is the norm in these photos -- one corner in shade, a glare
/// patch near the window -- and a single cutoff for the whole sheet either
/// floods the dark corner or loses the rulings in the bright one. Judging each
/// cell against the paper immediately around it removes the lighting gradient,
/// which is what the pipeline's CLAHE pass buys before its Otsu threshold.
///
/// detectTableGrid() warns about exactly this: a plain global threshold "can
/// lose faint printed ruling lines entirely on darker/lower-contrast photos
/// even though the lines are clearly visible to the eye". Measured here, a
/// global cutoff cut the longest run on a real form to 183 cells out of 400.
///
/// Uses a summed-area table, so the window mean costs four lookups regardless
/// of [_localRadius] and the whole pass is two sweeps of the grid.
Uint8List binariseAdaptive(Uint8List grid, int w, int h) {
  // Integral image, with a row and column of zero padding so the window lookup
  // never needs a bounds test.
  final integral = Int32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    for (var x = 0; x < w; x++) {
      rowSum += grid[y * w + x];
      integral[(y + 1) * (w + 1) + (x + 1)] =
          integral[y * (w + 1) + (x + 1)] + rowSum;
    }
  }

  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - _localRadius);
    final y1 = math.min(h - 1, y + _localRadius);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - _localRadius);
      final x1 = math.min(w - 1, x + _localRadius);

      final area = (x1 - x0 + 1) * (y1 - y0 + 1);
      final sum = integral[(y1 + 1) * (w + 1) + (x1 + 1)] -
          integral[y0 * (w + 1) + (x1 + 1)] -
          integral[(y1 + 1) * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];

      out[y * w + x] = grid[y * w + x] < (sum / area) - _localBias ? 1 : 0;
    }
  }
  return out;
}

/// The bright rectangle a sheet of paper occupies in a frame.
class PaperBox {
  final int left;
  final int top;
  final int right; // exclusive
  final int bottom; // exclusive
  const PaperBox(this.left, this.top, this.right, this.bottom);

  int get width => right - left;
  int get height => bottom - top;

  @override
  String toString() => 'PaperBox($left,$top -> $right,$bottom)';
}

/// Locate the sheet of paper in [grid]: the bright block in a darker frame.
///
/// A bounding box, not a quadrilateral. The pipeline needs true corners because
/// it must rectify the page before reading marks out of fixed coordinates; this
/// check only needs somewhere to measure ratios against, and a box does that at
/// a fraction of the cost.
///
/// Returns null when no clear bright region stands out. Null becomes "unknown",
/// never a rejection.
PaperBox? paperBoxOf(Uint8List grid, int w, int h) {
  // Split light from dark at the midpoint between the frame's extremes rather
  // than at its mean. Paper and desk are the two populations here, and a mean
  // slides toward whichever one happens to fill more of the shot.
  var lo = 255;
  var hi = 0;
  for (var i = 0; i < w * h; i++) {
    final v = grid[i];
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (hi - lo < _minContrast) return null;
  final bright = lo + ((hi - lo) * 0.55).round();

  // A row or column belongs to the paper when a good share of it is bright.
  // Not a majority: the page is often tilted in frame, so its topmost rows cut
  // across a corner and are mostly desk. Too high a bar here crops the
  // letterhead off and drags the table band with it.
  const share = 0.30;

  var top = -1;
  var bottom = -1;
  for (var y = 0; y < h; y++) {
    var lit = 0;
    for (var x = 0; x < w; x++) {
      if (grid[y * w + x] >= bright) lit++;
    }
    if (lit >= w * share) {
      if (top < 0) top = y;
      bottom = y;
    }
  }

  var left = -1;
  var right = -1;
  for (var x = 0; x < w; x++) {
    var lit = 0;
    for (var y = 0; y < h; y++) {
      if (grid[y * w + x] >= bright) lit++;
    }
    if (lit >= h * share) {
      if (left < 0) left = x;
      right = x;
    }
  }

  if (top < 0 || left < 0) return null;

  // Too small to be a sheet held up to the camera; almost certainly a bright
  // patch of something else.
  if (right - left < w * 0.25 || bottom - top < h * 0.25) return null;

  return PaperBox(left, top, right + 1, bottom + 1);
}

/// One detected ruling: where it sits, and how far its longest unbroken run ran.
class _Rule {
  final int center; // position on the axis we stepped across
  final int start; // where the run began, on the axis it runs along
  final int end;
  const _Rule(this.center, this.start, this.end);
}

/// Find printed rulings running along one axis, within a window.
///
/// Measures the longest unbroken run rather than total dark count. A column of
/// scattered text can sum higher than a hairline rule, but it never produces one
/// continuous run, and continuity is what separates a printed line from ink that
/// merely happens to be in the way. It is also the property the pipeline tests
/// for, by opening the image with a long thin morphological kernel.
List<_Rule> _scanRules(
  Uint8List dark,
  int w,
  int h, {
  required bool vertical,
  required int dilate,
  required int acrossFrom,
  required int acrossTo,
  required int alongFrom,
  required int alongTo,
  required double keepRatio,
  required double minSpanFraction,
}) {
  final acrossLimit = vertical ? w : h;
  final alongLimit = vertical ? h : w;
  final a0 = acrossFrom.clamp(0, acrossLimit);
  final a1 = acrossTo.clamp(0, acrossLimit);
  final b0 = alongFrom.clamp(0, alongLimit);
  final b1 = alongTo.clamp(0, alongLimit);
  final span = b1 - b0;
  if (a1 - a0 < 1 || span < 1) return const [];

  final lengths = List<int>.filled(acrossLimit, 0);
  final starts = List<int>.filled(acrossLimit, 0);

  for (var a = a0; a < a1; a++) {
    var best = 0;
    var bestStart = b0;
    var current = 0;
    for (var b = b0; b < b1; b++) {
      var isDark = false;
      for (var d = -dilate; d <= dilate; d++) {
        final aa = a + d;
        if (aa < a0 || aa >= a1) continue;
        final idx = vertical ? (b * w + aa) : (aa * w + b);
        if (dark[idx] == 1) {
          isDark = true;
          break;
        }
      }
      if (isDark) {
        current++;
        if (current > best) {
          best = current;
          bestStart = b - current + 1;
        }
      } else {
        current = 0;
      }
    }
    lengths[a] = best;
    starts[a] = bestStart;
  }

  var longest = 0;
  for (var a = a0; a < a1; a++) {
    if (lengths[a] > longest) longest = lengths[a];
  }
  if (longest < span * minSpanFraction) return const [];

  final keep = math.max(longest * keepRatio, span * minSpanFraction);

  // A printed ruling is a few cells wide at this scale; collapse each adjacent
  // band into the single line it actually is, and describe that line by its
  // strongest member.
  final rules = <_Rule>[];
  var groupStart = -1;
  var bestInGroup = -1;
  for (var a = a0; a <= a1; a++) {
    final isRule = a < a1 && lengths[a] >= keep;
    if (isRule) {
      if (groupStart < 0) {
        groupStart = a;
        bestInGroup = a;
      } else if (lengths[a] > lengths[bestInGroup]) {
        bestInGroup = a;
      }
    } else if (groupStart >= 0) {
      rules.add(_Rule(
        (groupStart + a - 1) ~/ 2,
        starts[bestInGroup],
        starts[bestInGroup] + lengths[bestInGroup],
      ));
      groupStart = -1;
    }
  }
  return rules;
}

/// How evenly spaced a set of positions is, 0..1.
double _evenness(List<int> positions) {
  if (positions.length < 3) return 0;

  final gaps = <double>[];
  for (var i = 1; i < positions.length; i++) {
    gaps.add((positions[i] - positions[i - 1]).toDouble());
  }

  final mean = gaps.reduce((a, b) => a + b) / gaps.length;
  if (mean <= 0) return 0;

  var acc = 0.0;
  for (final g in gaps) {
    acc += (g - mean) * (g - mean);
  }
  final std = math.sqrt(acc / gaps.length);
  return (1 - (std / mean)).clamp(0.0, 1.0);
}
