import 'dart:math' as math;
import 'dart:ui';

/// Pure geometry for the scanner's paper guide frame.
///
/// The photo is saved whole (no crop), so "what is inside the frame" means:
/// the frame must sit inside the part of the screen the camera really shows,
/// and its position there maps 1:1 onto the still.

/// Portrait width / height of the camera image. [sensorAspect] is the
/// controller's landscape width / height (e.g. 4/3 or 16/9).
double portraitAspect(double sensorAspect) =>
    sensorAspect >= 1 ? 1 / sensorAspect : sensorAspect;

/// Largest rect of [aspect] (width / height) centred in [area] (BoxFit.contain).
Rect containRect(Size area, double aspect) {
  var w = area.width;
  var h = w / aspect;
  if (h > area.height) {
    h = area.height;
    w = h * aspect;
  }
  return Rect.fromLTWH((area.width - w) / 2, (area.height - h) / 2, w, h);
}

/// Smallest rect of [aspect] (width / height) that covers [area] completely,
/// centred (BoxFit.cover). It may extend past [area] on one axis.
Rect coverRect(Size area, double aspect) {
  var w = area.width;
  var h = w / aspect;
  if (h < area.height) {
    h = area.height;
    w = h * aspect;
  }
  return Rect.fromLTWH((area.width - w) / 2, (area.height - h) / 2, w, h);
}

/// Guide frame of [paperRatio] (width / height) inside [preview], centred
/// horizontally, kept [hPad] from the sides and [vPad] from top and bottom.
Rect frameInPreview(Rect preview, double paperRatio,
    {double hPad = 24, double vPad = 16}) {
  final maxW = preview.width - hPad * 2;
  final maxH = preview.height - vPad * 2;
  var fw = maxW;
  var fh = fw / paperRatio;
  if (fh > maxH) {
    fh = maxH;
    fw = fh * paperRatio;
  }
  return Rect.fromLTWH(preview.left + (preview.width - fw) / 2,
      preview.top + (preview.height - fh) / 2, fw, fh);
}

/// Maps [frame] (screen coords) onto the still of [image] pixels, given the
/// screen rect [preview] the still is displayed in. Clamped to the image so a
/// crop can never reach outside it (no black fill).
Rect frameToImageRect(Rect frame, Rect preview, Size image) {
  final sx = image.width / preview.width;
  final sy = image.height / preview.height;
  final l = ((frame.left - preview.left) * sx).clamp(0.0, image.width);
  final t = ((frame.top - preview.top) * sy).clamp(0.0, image.height);
  final r = ((frame.right - preview.left) * sx).clamp(0.0, image.width);
  final b = ((frame.bottom - preview.top) * sy).clamp(0.0, image.height);
  return Rect.fromLTRB(math.min(l, r), math.min(t, b), math.max(l, r),
      math.max(t, b));
}
