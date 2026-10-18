import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ievaluateapp_final/gatherer/services/capture_normalise.dart';

Uint8List _jpeg(int w, int h, {int? orientation}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(200, 200, 200));
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(image, quality: 90);
}

void main() {
  test('an upright photo within limits is left exactly as taken', () {
    expect(normaliseCaptureBytes(_jpeg(300, 400)), isNull);
  });

  test('an EXIF-rotated photo is re-encoded upright', () {
    final out = normaliseCaptureBytes(_jpeg(400, 300, orientation: 6));
    expect(out, isNotNull);
    expect(out!.image.width, 300);
    expect(out.image.height, 400);
    final reread = img.decodeJpg(out.jpeg)!;
    expect(reread.width, 300);
    expect(img.decodeJpgExif(out.jpeg)?.imageIfd.orientation ?? 1, 1);
  });

  test('a photo larger than the cap is scaled to the long-side limit', () {
    final out = normaliseCaptureBytes(_jpeg(kMaxCaptureLongSide + 400, 200));
    expect(out, isNotNull);
    expect(out!.image.width, kMaxCaptureLongSide);
  });

  test('bytes that are not a JPEG are left alone', () {
    expect(normaliseCaptureBytes(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  group('readCaptureForUpload (runs at upload, not at USE PHOTO)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('capture_upload'));
    tearDown(() => dir.deleteSync(recursive: true));

    String write(String name, List<int> bytes) {
      final path = '${dir.path}${Platform.pathSeparator}$name';
      File(path).writeAsBytesSync(bytes);
      return path;
    }

    test('an upright photo within limits is sent byte for byte', () {
      final original = _jpeg(300, 400);
      final path = write('upright.jpg', original);
      expect(readCaptureForUpload(path), original);
      expect(File(path).readAsBytesSync(), original); // untouched on disk
    });

    test('an EXIF-rotated photo is sent upright and stored upright', () {
      final path = write('rotated.jpg', _jpeg(400, 300, orientation: 6));
      final sent = readCaptureForUpload(path);
      final decoded = img.decodeJpg(sent)!;
      expect((decoded.width, decoded.height), (300, 400));
      expect(img.decodeJpgExif(sent)?.imageIfd.orientation ?? 1, 1);

      // Written back, so a retry is a plain read of the same bytes.
      expect(File(path).readAsBytesSync(), sent);
      expect(readCaptureForUpload(path), sent);
      expect(File('$path.normalising').existsSync(), isFalse);
    });

    test('a photo that cannot be normalised is sent as it is', () {
      final junk = [1, 2, 3, 4, 5];
      final path = write('junk.jpg', junk);
      expect(readCaptureForUpload(path), junk);
    });

    test('a missing file is an error for the upload to report', () {
      expect(() => readCaptureForUpload('${dir.path}/gone.jpg'),
          throwsA(isA<FileSystemException>()));
    });

    test('encodeCaptureForUpload is the base64 of what would be sent', () {
      final path = write('rotated.jpg', _jpeg(400, 300, orientation: 6));
      final encoded = encodeCaptureForUpload(path);
      expect(base64Decode(encoded), File(path).readAsBytesSync());
    });
  });

  group('buildScanUploadBody (the whole request, built off the UI isolate)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('capture_body'));
    tearDown(() => dir.deleteSync(recursive: true));

    const fields = <String, Object?>{
      'user_id': 'user-1',
      'term_id': 'term-1',
      'task_id': 'SCAN-1',
      'filename': 'SCAN-1_SHORT.jpg',
      'paper_size': 'SHORT',
      'form_suspect': false,
      'timestamp': '2026-10-17T08:00:00.000',
    };

    String write(List<int> bytes) {
      final path = '${dir.path}${Platform.pathSeparator}SCAN-1_SHORT.jpg';
      File(path).writeAsBytesSync(bytes);
      return path;
    }

    test('runs on a background isolate from just the path', () async {
      final path = write(_jpeg(400, 300, orientation: 6));
      final body = await compute(buildScanUploadBody,
          (path: path, payload: fields, action: 'scan-upload'));

      // Exactly the envelope AutomationService.invokeAction sends the proxy.
      final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      expect(json.keys, unorderedEquals(['action', 'payload']));
      expect(json['action'], 'scan-upload');
      final payload = json['payload'] as Map<String, dynamic>;
      expect(payload.keys, unorderedEquals([...fields.keys, 'image']));
      fields.forEach((k, v) => expect(payload[k], v, reason: k));

      // The image is the normalised photo, which is also what is now stored.
      final sent = base64Decode(payload['image'] as String);
      final decoded = img.decodeJpg(sent)!;
      expect((decoded.width, decoded.height), (300, 400));
      expect(sent, File(path).readAsBytesSync());
    });

    test('an upright photo goes into the body byte for byte', () {
      final original = _jpeg(300, 400);
      final path = write(original);
      final body = buildScanUploadBody(
          (path: path, payload: fields, action: 'scan-upload'));
      final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      expect(base64Decode(json['payload']['image'] as String), original);
    });

    test('with no action the bare payload is sent (direct-to-n8n testing)', () {
      final path = write(_jpeg(300, 400));
      final body =
          buildScanUploadBody((path: path, payload: fields, action: null));
      final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      expect(json.keys, unorderedEquals([...fields.keys, 'image']));
      expect(json['task_id'], 'SCAN-1');
    });

    test('a missing file is an error for the upload to report', () {
      expect(
          () => buildScanUploadBody((
                path: '${dir.path}/gone.jpg',
                payload: fields,
                action: 'scan-upload',
              )),
          throwsA(isA<FileSystemException>()));
    });
  });
}
