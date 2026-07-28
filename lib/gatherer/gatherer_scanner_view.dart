// The beast of the gatherer module. This file is BIG.
// It handles: camera init, tilt detection, blur detection,
// paper size selection, scan overlay painting, and the preview screen.
// If something wrong with scanning, this is the file to blame first.
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:image/image.dart' as img;
import '../theme/app_colors.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Paper size definitions (portrait width ÷ height ratio)
//  These ratios determine the shape of the guide frame on screen.
//  The fileTag also get embedded in the filename so Python backend know what size it is.
// ═══════════════════════════════════════════════════════════════════════════════

enum PaperSize {
  shortBond('Short Bond', '8.5 × 11"', 8.5 / 11.0),   // 0.773 — letter/short
  a4('A4',         '210 × 297 mm', 210.0 / 297.0),     // 0.707 — standard A4
  longBond('Long Bond', '8.5 × 13"', 8.5 / 13.0);     // 0.654 — legal/long

  const PaperSize(this.label, this.dimensions, this.ratio);
  final String label;
  final String dimensions; // shown as subtitle in the toggle
  final double ratio;      // portrait: width ÷ height

  /// Short tag embedded in the filename so Python can detect paper size.
  /// e.g. "SCAN-1234_A4.jpg" or "SCAN-5678_LONG.jpg"
  String get fileTag {
    switch (this) {
      case PaperSize.shortBond: return 'SHORT';
      case PaperSize.a4:        return 'A4';
      case PaperSize.longBond:  return 'LONG';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GathererScannerView
//  The full camera screen. This is where all the action happen.
//  Tap to focus, tilt guard, blur check, paper guide frame — all here.
// ═══════════════════════════════════════════════════════════════════════════════

class GathererScannerView extends StatefulWidget {
  final Function(String path) onScan; // called with image path when scan is accepted
  final VoidCallback onOpenSync; // jump to sync queue tab
  final int queueCount; // number shown on sync badge button
  final void Function(String url)? onSendFormLink; // for the form link modal
  final VoidCallback? onMenuPressed; // open the drawer

  const GathererScannerView({
    super.key,
    required this.onScan,
    required this.onOpenSync,
    required this.queueCount,
    this.onSendFormLink,
    this.onMenuPressed,
  });

  @override
  State<GathererScannerView> createState() => _GathererScannerViewState();
}

// the big state class — holds camera, sensors, animations, and all the logic
class _GathererScannerViewState extends State<GathererScannerView>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // ── Camera state ─────────────────────────────────────────────────────────────
  CameraController? _controller; // the main camera controller — null until initialized
  bool _isInitialized = false; // false while camera booting up
  bool _isTakingPicture = false; // true during capture — prevent double-tap
  bool _isFocusing = false; // true during AF lock — short delay before capture
  String? _capturedImagePath; // path to captured image — triggers preview screen
  FlashMode _flashMode = FlashMode.off; // flash starts off, user can toggle
  Offset? _focusPoint; // screen position of the tap-to-focus ring
  bool _showOrientationWarning = false; // true when phone is in landscape — bad for scanning

  // ── Blur Detection state ─────────────────────────────────────────────────────
  bool _isBlurry = false; // true if last captured image failed blur check
  double _blurScore = 0; // variance of laplacian — higher = sharper
  bool _isCheckingBlur = false; // true while running blur detection algorithm

  // ── Sensor state (Tilt Guard) ────────────────────────────────────────────────
  // we read accelerometer to detect if phone is too tilted for a good scan
  double _tiltAngle = 0; // current tilt in degrees — > 30 = warning shown
  StreamSubscription? _accelSub; // subscription to accelerometer stream

  // ── Paper size selection ──────────────────────────────────────────────────────
  // default to A4 because thats most common. user can change in top bar.
  PaperSize _selectedPaper = PaperSize.a4;

  // ── Frame-ready animation: primary colour → greenAccent ──────────────────────
  // the guide frame flashes green when AF locks — visual feedback before capture
  late AnimationController _frameAnimCtrl;
  late Animation<Color?> _frameColorAnim;

  bool _isInitializing = false; // guard flag to prevent concurrent camera init calls

  // ══════════════════════════════════════════════════════════════════════════════
  //  Lifecycle
  //  Setup camera, sensors, and animation on init. Dispose everything cleanly.
  // ══════════════════════════════════════════════════════════════════════════════

  // called once when widget first built — start everything
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // watch app lifecycle (pause/resume)
    // animation controller for the frame color flash — 700ms, primary -> greenAccent
    _frameAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _frameColorAnim = ColorTween(
      begin: AppColors.primary,
      end: Colors.greenAccent,
    ).animate(CurvedAnimation(parent: _frameAnimCtrl, curve: Curves.easeOut));

    // subscribe to accelerometer for tilt detection
    _accelSub = accelerometerEventStream().listen((e) {
      // Improved Tilt Logic:
      // We check if the phone is mostly upright (wall scan) or flat (table scan).
      final double x = e.x;
      final double y = e.y;
      final double z = e.z;
      // Calculate total magnitude to normalize — gravity is ~9.8 m/s²
      final double g = sqrt(x * x + y * y + z * z);

      if (g < 1.0) return; // Ignore if in freefall or invalid — murag gilabay ang phone

      double tilt;
      if (z.abs() > 7.0) {
        // CASE: Phone is mostly FLAT (Table scanning)
        // We use a higher dampening for flat mode to avoid jumpy warnings
        tilt = acos((z.abs() / g).clamp(-1.0, 1.0)) * 180 / pi;
        // Substantial buffer: if it's less than 8 degrees, call it zero — small wobble ok
        if (tilt < 8) tilt = 0;
      } else {
        // CASE: Phone is mostly UPRIGHT (Wall scanning)
        tilt = asin((x.abs() / g).clamp(-1.0, 1.0)) * 180 / pi;
      }

      if (mounted) setState(() => _tiltAngle = tilt); // update tilt for UI warning
    });

    _initializeCamera(); // start camera setup
  }

  // called when app go to background or come back — handle camera lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // app going to background — dispose camera to release hardware
      setState(() => _isInitialized = false);
      
      final CameraController? c = _controller;
      _controller = null; // clear reference first so listener can detect replacement
      c?.dispose(); // then dispose the old controller
    } else if (state == AppLifecycleState.resumed) {
      // app came back — re-initialize camera
      if (_controller == null || !_isInitialized) {
        _initializeCamera(); // restart camera on resume
      }
    }
  }

  // clean up everything — cancel sensors, dispose camera and animation
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // stop watching lifecycle
    _accelSub?.cancel(); // stop reading accelerometer
    _frameAnimCtrl.dispose(); // dispose animation controller
    _isInitialized = false;
    final c = _controller;
    _controller = null;
    c?.dispose(); // dispose camera controller last
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Camera helpers
  //  All the messy camera initialization logic lives here.
  //  Also: tap-to-focus, flash toggle, capture, blur detection, and preview.
  // ══════════════════════════════════════════════════════════════════════════════

  // initialize the camera — get available cameras, pick the first one (back camera)
  // dispose any existing controller safely before creating new one
  Future<void> _initializeCamera() async {
    if (_isInitializing || !mounted) return; // already initializing, dili mag-duplicate
    _isInitializing = true;

    try {
      if (mounted) {
        setState(() => _isInitialized = false); // show loading while reinitializing
      }

      final cameras = await availableCameras(); // get list of device cameras
      if (cameras.isEmpty || !mounted) {
        _isInitializing = false;
        return; // no camera found — device problem or permission denied
      }

      // Dispose existing controller safely — avoid leak from previous instance
      if (_controller != null) {
        final oldController = _controller;
        _controller = null; // null first so listeners know it replaced
        await oldController?.dispose();
      }

      if (!mounted) {
        _isInitializing = false;
        return; // widget unmounted during dispose, abort
      }

      // create new camera controller — max resolution for best scan quality
      final newController = CameraController(
        cameras.first, // use back camera (first in list on most devices)
        ResolutionPreset.max, // highest resolution — importente for OCR accuracy
        enableAudio: false, // no need for audio in a scanner
        imageFormatGroup: ImageFormatGroup.jpeg, // JPEG for smaller file sizes
      );

      _controller = newController;

      // listen for orientation changes to show warning if landscape
      newController.addListener(() {
        if (!mounted || _controller != newController) return;
        final isLandscape =
            newController.value.deviceOrientation ==
                DeviceOrientation.landscapeLeft ||
                newController.value.deviceOrientation ==
                    DeviceOrientation.landscapeRight;
        if (isLandscape != _showOrientationWarning) {
          setState(() => _showOrientationWarning = isLandscape); // show/hide warning
        }
      });

      await newController.initialize(); // this is where actual camera access happens
      
      // Check again if we were disposed or replaced during initialization
      // race condition possible if user navigate away quickly
      if (!mounted || _controller != newController) {
        await newController.dispose(); // we replaced, clean up
        return;
      }

      await newController.setFlashMode(_flashMode); // restore flash setting
      await newController.setFocusMode(FocusMode.auto); // start with auto-focus

      if (mounted) {
        setState(() => _isInitialized = true); // camera ready, show preview
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Camera init error: $e'); // failed to open camera — check permissions
      }
    } finally {
      _isInitializing = false; // always clear flag
    }
  }

  // ── Tap-to-focus ──────────────────────────────────────────────────────────────
  // user tap on preview to manually set focus point
  // converts screen coordinates to 0-1 range for camera API
  Future<void> _handleFocus(TapUpDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final size = MediaQuery.of(context).size;
    final pt = details.localPosition; // where user tapped on screen
    setState(() => _focusPoint = pt); // show focus ring at tap position
    try {
      // normalize screen coordinates to 0-1 range for camera API
      await _controller!
          .setFocusPoint(Offset(pt.dx / size.width, pt.dy / size.height));
      await _controller!.setFocusMode(FocusMode.auto); // trigger AF at that point
    } catch (e) {
      debugPrint('Focus error: $e');
    }
    // hide focus ring after 2 seconds — temporary UI indicator
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _focusPoint = null);
    });
  }

  // ── Flash toggle ──────────────────────────────────────────────────────────────
  // toggle between torch (on) and off — simple two-state toggle
  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final next =
    _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off; // flip the state
    try {
      await _controller!.setFlashMode(next);
      setState(() => _flashMode = next); // update UI icon
    } catch (e) {
      debugPrint('Flash error: $e'); // some devices dont support torch mode
    }
  }

  // ── Capture: focus-lock → animate green → shoot ───────────────────────────────
  // the full capture sequence:
  // 1. Lock AF to center (so it dont hunt during capture)
  // 2. Animate frame to green (visual feedback while AF settles)
  // 3. Take picture
  // 4. Run blur detection on the result
  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isTakingPicture || // already capturing — dili mag-double shoot
        _isFocusing || // still focusing — wait
        _showOrientationWarning || // landscape — bad position, block capture
        _tiltAngle > 30) return; // too tilted — block capture

    // Step 1 — lock AF to centre point before shooting
    setState(() => _isFocusing = true);
    try {
      await _controller!.setFocusPoint(const Offset(0.5, 0.5)); // center of frame
      await _controller!.setFocusMode(FocusMode.locked); // lock focus here
    } catch (_) {} // if focus lock fail, proceed anyway — bahala na

    // Step 2 — animate frame green while AF settles (700ms)
    _frameAnimCtrl.forward(from: 0); // start green flash animation
    await Future.delayed(const Duration(milliseconds: 700)); // wait for AF

    // Step 3 — shoot!
    setState(() {
      _isFocusing = false;
      _isTakingPicture = true; // show "HOLD STEADY" text
    });
    try {
      final XFile photo = await _controller!.takePicture(); // capture the image
      try {
        await _controller!.setFocusMode(FocusMode.auto); // unlock focus after capture
      } catch (_) {}

      // Run blur detection before showing preview — check image sharpness
      if (mounted) {
        setState(() {
          _isCheckingBlur = true; // show "ANALYZING SHARPNESS" tag
          _capturedImagePath = photo.path; // switch to preview screen
        });
      }

      await _runBlurDetection(photo.path); // this may take a moment on slow devices

      if (mounted) {
        setState(() {
          _isCheckingBlur = false; // blur check done, show result
        });
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      try {
        await _controller!.setFocusMode(FocusMode.auto); // restore auto-focus even on error
      } catch (_) {}
    } finally {
      _frameAnimCtrl.reset(); // reset the green frame animation
      if (mounted) setState(() => _isTakingPicture = false); // hide "HOLD STEADY"
    }
  }

  // ── Preview actions ───────────────────────────────────────────────────────────
  // discard the captured image and return to camera — user wants to retake
  void _retake() {
    if (_capturedImagePath != null) {
      final f = File(_capturedImagePath!);
      if (f.existsSync()) try { f.deleteSync(); } catch (_) {} // delete the bad image file
    }
    setState(() {
      _capturedImagePath = null; // clear path = go back to camera view
      _isBlurry = false; // reset blur state
      _blurScore = 0;
    });
  }

  // run blur detection using variance of Laplacian algorithm
  // this is a proper image processing technique — not just vibes
  // higher variance = sharper edges = less blur
  Future<void> _runBlurDetection(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      // Decode with a frame limit to avoid memory spikes
      final image = img.decodeImage(bytes);
      if (image == null) return; // decode fail — skip blur check

      // 1. Downscale for speed (processing a 12MP image in Dart is slow)
      // 640px is enough for blur detection accuracy
      final small = img.copyResize(image, width: 640);

      // 2. Grayscale — blur detection works on luminance, not color
      final gray = img.grayscale(small);

      // 3. Laplacian filter for edge detection
      // Standard 3x3 Laplacian kernel — detects edges by second derivative
      final laplacian = [
        0,  1, 0,
        1, -4, 1,
        0,  1, 0
      ];

      // Apply convolution — this produce an edge-magnitude image
      final edges = img.convolution(gray, filter: laplacian);

      // 4. Calculate Variance of Laplacian
      // Higher variance = sharper edges = less blur — math is importente here
      double sum = 0;
      double sumSq = 0;
      final pixelCount = edges.width * edges.height;

      for (final pixel in edges) {
        // In img 4.x, pixel is an object. luminance gives 0-255
        final l = pixel.luminance;
        sum += l;
        sumSq += l * l; // accumulate sum of squares for variance calculation
      }

      final mean = sum / pixelCount;
      final variance = (sumSq / pixelCount) - (mean * mean); // variance formula: E[X²] - (E[X])²

      if (mounted) {
        setState(() {
          _blurScore = variance;
          // Threshold of 150-250 is usually safe for 640px document images.
          // Lower values mean more blurry — 200 is a reasonable cutoff.
          _isBlurry = variance < 200;
        });
        debugPrint('Blur Detection Score: $variance (isBlurry: $_isBlurry)');
      }
    } catch (e) {
      debugPrint('Blur detection error: $e'); // blur check fail — just show nothing, proceed normally
    }
  }

  // user accepts the captured image — rename with paper tag and hand off to parent
  void _acceptImage() {
    if (_capturedImagePath == null) return;

    // Rename file to include paper size tag so the Python backend can read it
    // e.g.  SCAN-1234567890_A4.jpg  /  _LONG.jpg  /  _SHORT.jpg
    // This is how Python knows which template to use for grid cropping
    final orig = File(_capturedImagePath!);
    final dir  = orig.parent.path;
    final base = orig.path
        .split(Platform.pathSeparator)
        .last
        .replaceFirst(RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false), ''); // remove extension
    final newPath =
        '$dir${Platform.pathSeparator}${base}_${_selectedPaper.fileTag}.jpg'; // add paper tag before extension
    try {
      orig.renameSync(newPath); // rename in place
      widget.onScan(newPath); // pass the new path to parent for upload
    } catch (_) {
      // Rename failed (e.g. cross-device); fall back to original path
      // Not ideal but better than losing the scan entirely
      widget.onScan(_capturedImagePath!);
    }
    setState(() => _capturedImagePath = null); // clear path = go back to camera
  }

  // open the form link modal — dark bottom sheet with URL input
  void _openFormLinkModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // allow expanding for keyboard
      backgroundColor: Colors.transparent,
      builder: (_) => _FormLinkBottomSheet(
        controller: TextEditingController(),
        onSend: (url) => widget.onSendFormLink?.call(url), // pass URL to parent
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Guide-frame geometry — respects paper ratio, clamps to screen
  //  This calculate the exact Rect for the paper guide overlay.
  // ══════════════════════════════════════════════════════════════════════════════

  /// Returns the Rect for the paper guide frame in screen coordinates.
  /// Frame is pinned near the top (below the toolbar) rather than centred,
  /// so there is generous space below for the guidance text + capture button.
  Rect _frameRect(Size screen, {double hPad = 30.0}) {
    // How far from screen top the frame starts (approx: safeArea + toolbar height)
    const topOffset  = 110.0;
    // Reserve at the bottom for guidance text + capture button — dont overlap controls
    const botReserve = 205.0;

    final maxW = screen.width - hPad * 2; // max frame width with horizontal padding
    final maxH = screen.height - topOffset - botReserve; // max usable height for frame

    var fw = maxW;
    var fh = fw / _selectedPaper.ratio; // calculate height from ratio

    // If too tall, constrain by height — maintain ratio but shrink width
    if (fh > maxH) {
      fh = maxH;
      fw = fh * _selectedPaper.ratio; // recalculate width from constrained height
    }

    return Rect.fromLTWH(
      (screen.width - fw) / 2, // horizontally centered
      topOffset,   // ← pinned near top instead of vertically centred
      fw,
      fh,
    );
  }

  // true when camera is busy — either focusing or taking picture
  // used to dim the capture button and block re-entry
  bool get _busy => _isFocusing || _isTakingPicture;

  // ══════════════════════════════════════════════════════════════════════════════
  //  Build
  //  Returns camera view or preview screen based on _capturedImagePath
  // ══════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final CameraController? controller = _controller;

    // camera not ready yet — show dark loading screen
    if (!_isInitialized || controller == null || !controller.value.isInitialized) {
      return Container(
        color: const Color(0xFF0F0F0F), // near-black while loading
        child:
        const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    // if we captured an image, show the preview screen instead of camera
    if (_capturedImagePath != null) return _buildPreviewScreen();

    final screen = MediaQuery.of(context).size;
    final frame = _frameRect(screen); // calculate guide frame rect

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera preview with tap-to-focus
          // fills entire screen, user can tap anywhere to focus
          Positioned.fill(
            child: GestureDetector(
              onTapUp: _handleFocus, // tap to set focus point
              child: Center(
                child: CameraPreview(
                  controller,
                  key: ValueKey(controller), // key ensures rebuild when controller changes
                ),
              ),
            ),
          ),

          // 2. Dim overlay + aspect-correct guide frame (CustomPainter)
          // dims everything outside the guide frame — helps user align paper
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _frameColorAnim,
              builder: (_, __) => CustomPaint(
                painter: _ScanOverlayPainter(
                  frameRect: frame,
                  dimColor: Colors.black.withOpacity(0.55), // semi-transparent dim
                  frameColor: _showOrientationWarning
                      ? Colors.white24 // dim frame when in landscape (scanning disabled)
                      : (_frameColorAnim.value ?? AppColors.primary), // animate to green on capture
                ),
              ),
            ),
          ),

          // 3. Paper-size label (inside top-left of frame)
          // shows which paper size is selected — "A4", "Short Bond", etc.
          Positioned(
            left: frame.left + 12,
            top: frame.top + 12,
            child: _PaperLabel(label: _selectedPaper.label),
          ),

          // 4. Tap-to-focus ring — circular border at the tap point
          if (_focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 30,
              top: _focusPoint!.dy - 30,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 2), // colored ring
                  shape: BoxShape.circle,
                ),
              ),
            ),

          // 5. Orientation warning — overlays everything when phone is landscape
          if (_showOrientationWarning)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.screen_lock_portrait_rounded,
                        size: 80, color: Colors.white),
                    const SizedBox(height: 20),
                    const Text(
                      'PLEASE HOLD PORTRAIT',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'The scanner works best in upright mode',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // 6. UI controls (top bar + bottom guidance + capture button)
          SafeArea(
            child: Column(
              children: [
                // Top bar — [Flash] [Paper ▼]  |  Spacer  |  [Link] [Sync]
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      // Flash toggle — switches between torch and off
                      _ActionButton(
                        icon: _flashMode == FlashMode.torch
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        onTap: _toggleFlash,
                        activeColor: _flashMode == FlashMode.torch
                            ? Colors.yellow // yellow when torch is on — obvious
                            : Colors.white,
                      ),
                      const SizedBox(width: 8),

                      // ── Compact paper-size dropdown ─────
                      // tap to select Short Bond / A4 / Long Bond
                      _PaperDropdown(
                        selected: _selectedPaper,
                        onChanged: (p) =>
                            setState(() => _selectedPaper = p), // update and redraw frame
                      ),

                      const Spacer(), // push right buttons to the right edge
                      // Form link button — open bottom sheet to submit a Google Form URL
                      _ActionButton(
                        icon: Icons.link_rounded,
                        onTap: _openFormLinkModal,
                        activeColor: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      // Sync queue button — with badge showing queue count
                      _ActionButton(
                        icon: Icons.sync_rounded,
                        onTap: widget.onOpenSync,
                        badge: widget.queueCount, // red badge if items in queue
                      ),
                    ],
                  ),
                ),

                const Spacer(), // push capture button and guidance to the bottom

                // Bottom guidance text — changes based on current state
                _buildBottomGuidance(),
                const SizedBox(height: 24),

                // Capture button — big white circle at the bottom
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _takePicture, // trigger the capture sequence
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _busy ? Colors.white38 : Colors.white, // dim when busy
                              width: 4,
                            ),
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _busy ? Colors.white38 : Colors.white, // inner circle dimmed when busy
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'TAP TO CAPTURE',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // build the guidance text shown above the capture button
  // changes based on: tilt angle, focusing state, taking picture state
  Widget _buildBottomGuidance() {
    if (_tiltAngle > 30) {
      // phone too tilted — show tilt angle and warning to hold straight
      return Column(children: [
        const Icon(Icons.screen_rotation, color: Colors.redAccent, size: 36),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
          ),
          child: Text(
            'TILT: ${_tiltAngle.toStringAsFixed(0)}° — HOLD STRAIGHT', // show exact angle so user know how much to adjust
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              fontSize: 14,
            ),
          ),
        ),
      ]);
    }
    if (_isFocusing) {
      // AF is locking — tell user camera is working
      return const Column(children: [
        CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 2.5),
        SizedBox(height: 10),
        Text('FOCUSING…',
            style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                fontSize: 13)),
      ]);
    }
    if (_isTakingPicture) {
      // actively capturing — tell user to not move
      return const Column(children: [
        CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
        SizedBox(height: 10),
        Text('HOLD STEADY…',
            style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                fontSize: 13)),
      ]);
    }
    // default state — normal scanning instructions
    return Column(children: [
      Text(
        'FIT ${_selectedPaper.label.toUpperCase()} PAPER INSIDE THE FRAME', // remind user what paper they selected
        style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      const Text(
        'Leave a gap between paper and frame edges',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      ),
      const SizedBox(height: 4),
      Text(
        'Hold steady  •  Plain background  •  Good lighting', // the holy trinity of good scans
        style: TextStyle(
            color: Colors.white.withOpacity(0.55), fontSize: 11),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Preview screen
  //  Shown after capture — user sees the photo and decides retake or use
  // ══════════════════════════════════════════════════════════════════════════════

  // the preview screen — full-screen image with retake/use buttons and blur warning
  Widget _buildPreviewScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // show the captured image filling the screen
          Positioned.fill(
            child:
            Image.file(File(_capturedImagePath!), fit: BoxFit.contain),
          ),

          // Quality hint & Blur Warning — shown at top center of preview
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isCheckingBlur)
                      // still analyzing — spinning sync icon while blur check runs
                      _BlurStatusTag(
                        icon: Icons.sync,
                        label: 'ANALYZING SHARPNESS...',
                        color: Colors.white.withOpacity(0.8),
                        isSpinning: true,
                      )
                    else if (_isBlurry)
                      // blur detected — warn user image may be unclear for OCR
                      _BlurStatusTag(
                        icon: Icons.warning_amber_rounded,
                        label: 'IMAGE APPEARS BLURRY',
                        color: Colors.orangeAccent,
                      )
                    else
                      // image looks sharp — show paper label and check corners reminder
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.4)),
                        ),
                        child: Text(
                          '${_selectedPaper.label}  •  Check all 4 corners are visible & image is sharp',
                          style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Retake / Use buttons — at the bottom with gradient background
          SafeArea(
            child: Column(
              children: [
                const Spacer(), // push buttons to bottom
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 50),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.95), // dark at bottom
                        Colors.transparent // transparent at top — fade to image
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      // RETAKE — discard and go back to camera
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _retake,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: Colors.white, width: 2),
                            padding:
                            const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                          ),
                          child: const Text('RETAKE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // USE PHOTO — accept image and add to upload queue
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _acceptImage, // rename + hand to parent
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            padding:
                            const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                            elevation: 0,
                          ),
                          child: const Text('USE PHOTO',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CustomPainter — dims outside guide frame, draws corner brackets + outline
//  This is the cool scanner overlay effect. Paint on canvas directly.
// ═══════════════════════════════════════════════════════════════════════════════

class _ScanOverlayPainter extends CustomPainter {
  final Rect frameRect; // the paper guide area — inside is clear, outside is dimmed
  final Color dimColor; // semi-transparent black for the dim overlay
  final Color frameColor; // color of the corner brackets — animates to green on capture

  const _ScanOverlayPainter({
    required this.frameRect,
    required this.dimColor,
    required this.frameColor,
  });

  static const _radius     = Radius.circular(12); // rounded corners for the guide frame
  static const _bracketLen = 34.0; // length of the corner bracket lines
  static const _bracketW   = 3.5; // thickness of the corner bracket lines
  static const _borderW    = 1.5; // thickness of the faint full outline

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(frameRect, _radius);

    // Dim overlay with transparent hole where the guide frame is
    // using evenOdd fill rule: outer rect minus inner rounded rect = dim ring
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height)) // full screen
        ..addRRect(rrect) // punch hole for guide frame
        ..fillType = PathFillType.evenOdd, // this makes the hole transparent
      Paint()..color = dimColor,
    );

    // Faint full outline — subtle border around the entire guide frame
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = frameColor.withOpacity(0.4) // semi-transparent outline
        ..strokeWidth = _borderW
        ..style = PaintingStyle.stroke,
    );

    // Bright corner brackets — the four L-shapes at each corner
    // more visible than the full outline — helps user align paper corners
    final bp = Paint()
      ..color = frameColor // bright bracket color (animates to green)
      ..strokeWidth = _bracketW
      ..strokeCap = StrokeCap.round // rounded ends look cleaner
      ..style = PaintingStyle.stroke;

    // draw a bracket at each corner — dx/dy direction determines which corner
    _bracket(canvas, bp, frameRect.topLeft,      1,  1); // top-left: right + down
    _bracket(canvas, bp, frameRect.topRight,    -1,  1); // top-right: left + down
    _bracket(canvas, bp, frameRect.bottomLeft,   1, -1); // bottom-left: right + up
    _bracket(canvas, bp, frameRect.bottomRight, -1, -1); // bottom-right: left + up
  }

  // draw an L-shaped bracket at a corner — two lines extending in dx/dy direction
  void _bracket(Canvas c, Paint p, Offset corner, double dx, double dy) {
    c.drawLine(corner, corner + Offset(dx * _bracketLen, 0), p); // horizontal line
    c.drawLine(corner, corner + Offset(0, dy * _bracketLen), p); // vertical line
  }

  // only repaint if frame geometry or colors actually changed — performance optimization
  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.frameColor != frameColor ||
          old.frameRect != frameRect ||
          old.dimColor != dimColor;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Compact paper-size dropdown (sits next to the flash button in the top bar)
//  Shows Short Bond / A4 / Long Bond as popup menu items.
// ═══════════════════════════════════════════════════════════════════════════════

class _PaperDropdown extends StatelessWidget {
  final PaperSize selected; // currently selected paper size
  final ValueChanged<PaperSize> onChanged; // called when user picks a different size
  const _PaperDropdown({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PaperSize>(
      onSelected: onChanged, // user picked a paper size
      color: const Color(0xFF1E1E1E), // dark background for the popup — fits the dark camera UI
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      offset: const Offset(0, 54),   // drops directly below the button
      itemBuilder: (_) => PaperSize.values.map((p) {
        final active = p == selected; // is this the currently selected size?
        return PopupMenuItem<PaperSize>(
          value: p,
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: active
                ? BoxDecoration(
              color: AppColors.primary.withOpacity(0.15), // highlight active item
              borderRadius: BorderRadius.circular(10),
            )
                : null,
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.label, // e.g. "A4", "Short Bond"
                      style: TextStyle(
                        color: active ? AppColors.primary : Colors.white,
                        fontSize: 14,
                        fontWeight: active ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    Text(
                      p.dimensions, // e.g. "210 × 297 mm"
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                // checkmark for the active item — visual confirmation
                if (active)
                  const Icon(Icons.check_rounded,
                      color: AppColors.primary, size: 18),
              ],
            ),
          ),
        );
      }).toList(),
      // The button itself — shows selected paper label with a dropdown arrow
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10), // subtle white tint
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected.label, // e.g. "A4"
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded,
                color: Colors.white70, size: 16), // dropdown arrow
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Paper size toggle — full-width 3-option segmented selector (kept for reference)
//  This was the old toggle before the compact dropdown replaced it.
//  Kept here in case we need to switch back — wala choice kung mag-revert
// ═══════════════════════════════════════════════════════════════════════════════

class _PaperSizeToggle extends StatelessWidget {
  final PaperSize selected;
  final ValueChanged<PaperSize> onChanged;
  const _PaperSizeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: PaperSize.values.map((p) {
          final active = p == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(p), // select this paper size
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : Colors.transparent, // fill active
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: active ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: active
                            ? FontWeight.bold
                            : FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.dimensions, // dimension text below label
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: active ? Colors.black54 : Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Small label shown inside the guide frame ──────────────────────────────────
// shows the currently selected paper size name inside the scan overlay
// e.g. "A4" or "Short Bond" — subtle reminder of what size is selected

class _PaperLabel extends StatelessWidget {
  final String label;
  const _PaperLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.50), // semi-transparent dark pill
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white60, fontSize: 11, letterSpacing: 1),
      ),
    );
  }
}

// animated tag widget for blur detection status — shown in preview screen
// can spin if isSpinning is true (for the "analyzing" state)
class _BlurStatusTag extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSpinning; // true when blur check still running

  const _BlurStatusTag({
    required this.icon,
    required this.label,
    required this.color,
    this.isSpinning = false,
  });

  @override
  State<_BlurStatusTag> createState() => _BlurStatusTagState();
}

// the state handles the spinning animation for the "analyzing" state
class _BlurStatusTagState extends State<_BlurStatusTag>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl; // controls rotation animation

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2)); // 1 full rotation per 2s
    if (widget.isSpinning) _ctrl.repeat(); // spin continuously while analyzing
  }

  // always dispose animation controllers — memory leak if you forget
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85), // dark semi-opaque background
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: widget.color.withOpacity(0.5), width: 1.5), // colored border
        boxShadow: [
          BoxShadow(
              color: widget.color.withOpacity(0.2),
              blurRadius: 12,
              spreadRadius: 2) // subtle glow matching the tag color
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isSpinning)
            // spinning icon while analyzing — visual feedback
            RotationTransition(
              turns: _ctrl,
              child: Icon(widget.icon, color: widget.color, size: 20),
            )
          else
            Icon(widget.icon, color: widget.color, size: 20), // static icon for result
          const SizedBox(width: 10),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Existing helper widgets (unchanged public API)
//  These small widgets used in the camera top bar and form link modal.
// ═══════════════════════════════════════════════════════════════════════════════

// circular action button used in the camera top bar
// supports optional colored icon and a red badge count
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? activeColor; // if null, defaults to white
  final int badge; // if > 0, show a red circle with this number

  const _ActionButton({
    required this.icon,
    required this.onTap,
    this.activeColor,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none, // allow badge to overflow outside button bounds
        children: [
          // the circular button itself
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10), // subtle white fill
              shape: BoxShape.circle,
              border: Border.all(
                  color:
                  activeColor?.withOpacity(0.4) ?? Colors.white24), // colored border when active
            ),
            child: Icon(icon, color: activeColor ?? Colors.white, size: 22),
          ),
          // red badge positioned at top-right of button
          if (badge > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                    color: AppColors.error, shape: BoxShape.circle), // red circle
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

// bottom sheet for submitting a Google Form URL from the scanner screen
// dark theme to match the camera UI — user paste link and tap "Add to Queue"
class _FormLinkBottomSheet extends StatelessWidget {
  final TextEditingController controller; // for the URL input field
  final Function(String) onSend; // called with the URL when user confirm

  const _FormLinkBottomSheet(
      {required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), // push up with keyboard
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A), // very dark background — camera aesthetic
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Process Online Form',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            // URL input field — user paste the Google Form link here
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter Google Form URL',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05), // subtle dark fill
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none),
                prefixIcon:
                const Icon(Icons.link, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 24),
            // submit button — only active if URL not empty
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    onSend(controller.text); // pass URL to parent for processing
                    Navigator.pop(context); // close the sheet
                  }
                  // if empty, do nothing — ayaw mag-submit if empty
                },
                child: const Text('Add to Queue',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
