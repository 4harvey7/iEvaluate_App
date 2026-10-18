// USE PHOTO must never wait on the sharpness / document checks.
//
// It used to: the checks also re-encoded the full-sensor photo, USE PHOTO
// awaited them, and on the phone the button did nothing for many seconds
// while the preview said "ANALYZING SHARPNESS...". The camera's takePicture()
// returning is the only thing the file needs; the verdict is a nice-to-have
// that only matters if it is in by the time the gatherer presses the button.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ievaluateapp_final/gatherer/gatherer_scanner_view.dart';
import 'package:ievaluateapp_final/gatherer/services/form_signature.dart';
import 'package:ievaluateapp_final/gatherer/services/scan_analysis.dart';

const _blurry = ScanAnalysis(
  isBlurry: true,
  blurScore: 12,
  form: FormCheck.unknown,
);

void main() {
  late Directory dir;
  late String photo;
  late List<(String, FormCheck)> scans;
  // One per capture, in order; each finishes only when the test says so.
  late List<Completer<ScanAnalysis>> analyses;

  setUp(() {
    // No tilt sensor under test: answer its channels so they stay quiet.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
        (_) async => null);
    messenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/sensors/accelerometer'),
        MockStreamHandler.inline(onListen: (_, _) {}));
    dir = Directory.systemTemp.createTempSync('scanner_use_photo');
    photo = '${dir.path}${Platform.pathSeparator}SCAN-1.jpg';
    File(photo).writeAsBytesSync(img.encodeJpg(img.Image(width: 8, height: 8)));
    scans = [];
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// No camera exists under test, so a capture is injected exactly where
  /// takePicture() would hand it over.
  Future<void> capture(WidgetTester tester, String path) async {
    (tester.state(find.byType(GathererScannerView)) as dynamic)
        .debugShowCapture(path);
    await tester.pump();
    expect(find.text('USE PHOTO'), findsOneWidget);
  }

  /// The scanner on the preview of [photo], its analysis still running.
  Future<void> showCapture(WidgetTester tester) async {
    // Made inside the test body so they complete in the fake-async zone.
    analyses = [];
    await tester.pumpWidget(MaterialApp(
      home: GathererScannerView(
        onScan: (path, form) => scans.add((path, form)),
        onOpenSync: () {},
        queueCount: 0,
        onOpenImportData: () {},
        analyseCapture: (_) {
          final c = Completer<ScanAnalysis>();
          analyses.add(c);
          return c.future;
        },
      ),
    ));
    await tester.pump();
    await capture(tester, photo);
  }

  /// A second photo, for the next capture.
  String secondPhoto() {
    final path = '${dir.path}${Platform.pathSeparator}SCAN-2.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(img.Image(width: 8, height: 8)));
    return path;
  }

  /// Tap USE PHOTO and let the hand-off (a platform call that fails under
  /// test, then a file rename) run to completion.
  Future<void> usePhoto(WidgetTester tester) async {
    await tester.tap(find.text('USE PHOTO'));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 200)));
    await tester.pump();
  }

  testWidgets('works while the analysis is still running', (tester) async {
    await showCapture(tester);
    expect(find.text('ANALYZING SHARPNESS...'), findsOneWidget);

    await usePhoto(tester);

    expect(scans, hasLength(1));
    expect(File(scans.single.$1).existsSync(), isTrue);
    // No verdict yet, so the scan is not flagged as a suspect document.
    expect(scans.single.$2.match, FormCheck.unknown.match);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('USE PHOTO'), findsNothing); // back on the camera

    // The next photo is on screen when the first one's verdict lands late.
    // It belongs to the photo already sent, not this one.
    await capture(tester, secondPhoto());
    analyses[0].complete(_blurry);
    await tester.pump();
    expect(find.text('ANALYZING SHARPNESS...'), findsOneWidget);
    expect(find.text('IMAGE APPEARS BLURRY'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(scans, hasLength(1));
  });

  testWidgets('a finished "blurry" verdict still asks before queueing',
      (tester) async {
    await showCapture(tester);
    analyses.single.complete(_blurry);
    await tester.pump();
    expect(find.text('IMAGE APPEARS BLURRY'), findsOneWidget);

    await tester.tap(find.text('USE PHOTO'));
    await tester.pump();
    expect(find.text('Image appears blurry'), findsOneWidget);
    expect(scans, isEmpty);

    await tester.tap(find.text('QUEUE ANYWAY'));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 200)));
    await tester.pump();
    expect(scans, hasLength(1));
  });

  testWidgets('a double tap queues the photo once', (tester) async {
    await showCapture(tester);
    await tester.tap(find.text('USE PHOTO'));
    await tester.tap(find.text('USE PHOTO'), warnIfMissed: false);
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 200)));
    await tester.pump();
    expect(scans, hasLength(1));
  });

  testWidgets('a retake drops the verdict of the photo it threw away',
      (tester) async {
    await showCapture(tester);
    await tester.tap(find.text('RETAKE'));
    await tester.pump();
    expect(find.text('USE PHOTO'), findsNothing);
    expect(File(photo).existsSync(), isFalse); // the bad photo is deleted

    await capture(tester, secondPhoto());
    analyses[0].complete(_blurry); // verdict on the photo thrown away
    await tester.pump();
    expect(find.text('ANALYZING SHARPNESS...'), findsOneWidget);
    expect(find.text('IMAGE APPEARS BLURRY'), findsNothing);

    analyses[1].complete(_blurry); // and this photo's own verdict shows
    await tester.pump();
    expect(find.text('IMAGE APPEARS BLURRY'), findsOneWidget);
  });

  testWidgets('leaving the scanner mid-analysis is harmless', (tester) async {
    await showCapture(tester);
    await tester.pumpWidget(const SizedBox());
    analyses.single.complete(_blurry); // setState here would throw
    await tester.pump();
  });

  // A 13 MP still decoded at full size is ~52 MB of pixels for one preview.
  testWidgets('the preview decodes the photo at screen width', (tester) async {
    await showCapture(tester);
    final image = tester.widget<Image>(find.byType(Image)).image;
    expect(image, isA<ResizeImage>());
    // Logical width x device pixel ratio = the screen's physical width.
    expect((image as ResizeImage).width,
        tester.view.physicalSize.width.round());
    expect(image.height, isNull); // aspect ratio kept
  });
}
