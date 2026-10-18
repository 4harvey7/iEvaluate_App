// capture_normalise.dart
// Keeps a full-resolution capture within what the upload path is built for.
//
// Since camera 0.11 (CameraX on Android) ResolutionPreset.max takes the still
// at the sensor's full size — 3264 x 2448 (8 MP) on the Infinix the gatherers
// use — instead of the 1920 x 1080 video size camera_android used to hand
// back. More pixels per bubble and per stamp digit is the point, but three
// things are kept in check here, on a background isolate at upload time:
//
//   * orientation — CameraX may leave the rotation in the EXIF tag instead of
//     the pixels. Python's cv2.imdecode honours the tag, but every consumer
//     should not have to, so a tagged photo is re-encoded upright;
//   * size — a phone with a 50 MP sensor would send 15+ MB of base64 through
//     the Supabase proxy into n8n. The long side is capped at
//     [kMaxCaptureLongSide]. The Infinix X6525 actually stills at 4160 x
//     3120 (13 MP, seen in its logcat), so its photos are scaled to 3264 x
//     2448 here -- still above the ~2500 px the stamp digits need, and the
//     OMR server shrinks to a 1920 long side anyway;
//   * weight — anything still over [kMaxCaptureBytes] is re-encoded at
//     [kCaptureJpegQuality].
//
// The common case (upright 8 MP JPEG of a few MB) costs one header parse and
// is left exactly as the camera wrote it — no generation loss, no delay.
//
// The whole upload request body is built here too ([buildScanUploadBody]),
// from the file path, on the same background isolate: the UI isolate never
// holds the photo, its base64 or the JSON. compute() hands the finished bytes
// back with Isolate.exit, which moves them instead of copying.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest side kept. A bigger still (the Infinix X6525's is 4160 x 3120) is
/// scaled to this, which still gives the OMR ~2.5x the pixels of the old 1920
/// stills.
const int kMaxCaptureLongSide = 3264;

/// JPEG quality used whenever the photo has to be re-encoded.
const int kCaptureJpegQuality = 90;

/// A capture larger than this is re-encoded at [kCaptureJpegQuality].
const int kMaxCaptureBytes = 4500000;

/// The re-encoded JPEG for [bytes] plus the decoded image it came from, or
/// null when the capture is fine as it is (or is not a JPEG we can read —
/// a check must never cost the gatherer a scan).
({Uint8List jpeg, img.Image image})? normaliseCaptureBytes(Uint8List bytes) {
  final decoder = img.JpegDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null) return null;

  final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;
  final rotated = orientation > 1 && orientation <= 8;
  final tooBig = math.max(info.width, info.height) > kMaxCaptureLongSide;
  final tooHeavy = bytes.length > kMaxCaptureBytes;
  if (!rotated && !tooBig && !tooHeavy) return null;

  // decodeJpg applies the EXIF orientation to the pixels and drops the tag.
  var image = img.decodeJpg(bytes);
  if (image == null) return null;
  if (math.max(image.width, image.height) > kMaxCaptureLongSide) {
    image = image.width >= image.height
        ? img.copyResize(image,
            width: kMaxCaptureLongSide,
            interpolation: img.Interpolation.average)
        : img.copyResize(image,
            height: kMaxCaptureLongSide,
            interpolation: img.Interpolation.average);
  }
  return (
    jpeg: img.encodeJpg(image, quality: kCaptureJpegQuality),
    image: image,
  );
}

/// The bytes to upload for the capture at [path]: normalised (see
/// [normaliseCaptureBytes]) when it needs it, otherwise exactly as stored.
///
/// Runs at upload time, not at capture -- an 8 MP re-encode in Dart takes
/// seconds, and USE PHOTO used to wait for it. A normalised photo is written
/// back over the stored one (via a temp file and a rename, so a reader never
/// sees half a JPEG), which makes every retry after the first a plain read.
///
/// Anything going wrong in the normalising falls back to the original bytes:
/// a scan sent as taken beats a scan lost. Top-level and synchronous so it can
/// be handed to compute().
Uint8List readCaptureForUpload(String path) {
  final file = File(path);
  final bytes = file.readAsBytesSync();
  ({Uint8List jpeg, img.Image image})? normalised;
  try {
    normalised = normaliseCaptureBytes(bytes);
  } catch (_) {
    normalised = null; // keep the photo exactly as taken
  }
  if (normalised == null) return bytes;

  try {
    final temp = File('$path.normalising');
    temp.writeAsBytesSync(normalised.jpeg, flush: true);
    // The scan may have been deleted from the queue meanwhile; do not bring
    // it back.
    if (file.existsSync()) {
      temp.renameSync(path);
    } else {
      temp.deleteSync();
    }
  } catch (_) {
    // Could not store it; the upload still gets the normalised photo.
  }
  return normalised.jpeg;
}

/// [readCaptureForUpload], base64-encoded for the upload's JSON body, so the
/// encoding of a few megabytes happens off the UI thread as well.
String encodeCaptureForUpload(String path) =>
    base64Encode(readCaptureForUpload(path));

/// One scan upload, as [buildScanUploadBody] needs it: the capture's [path],
/// the request fields other than the image, and the [action] the request is
/// wrapped in ({"action": ..., "payload": ...}, as the n8n proxy expects), or
/// null to send the bare payload (direct-to-n8n testing).
typedef ScanUploadJob = ({
  String path,
  Map<String, Object?> payload,
  String? action,
});

/// The complete JSON request body for [job], as UTF-8 bytes: the capture is
/// read, normalised ([readCaptureForUpload]) and base64-encoded into
/// `payload.image`. Top-level so compute() can run it -- the UI isolate then
/// only passes a path in and gets finished bytes out, where it used to get a
/// 3-5 MB base64 string back and JSON-encode and UTF-8-encode it itself.
Uint8List buildScanUploadBody(ScanUploadJob job) {
  final payload = <String, Object?>{
    ...job.payload,
    'image': encodeCaptureForUpload(job.path),
  };
  final body = job.action == null
      ? payload
      : <String, Object?>{'action': job.action, 'payload': payload};
  final bytes = JsonUtf8Encoder().convert(body);
  return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}
