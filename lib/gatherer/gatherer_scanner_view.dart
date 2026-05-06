// lib/gatherer/gatherer_scanner_view.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:ui';
import '../app_colors.dart';

class GathererScannerView extends StatefulWidget {
  final VoidCallback onScan;
  final VoidCallback onOpenSync;
  final int queueCount;
  final void Function(String url)? onSendFormLink;

  const GathererScannerView({
    super.key,
    required this.onScan,
    required this.onOpenSync,
    required this.queueCount,
    this.onSendFormLink,
  });

  @override
  State<GathererScannerView> createState() => _GathererScannerViewState();
}

class _GathererScannerViewState extends State<GathererScannerView> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCheckingQuality = false;

  late AnimationController _scanLineController;

  @override
  void initState() {
    super.initState();
    _initializeCamera();

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _cameraController = CameraController(
        cameras.firstWhere((cam) => cam.lensDirection == CameraLensDirection.back, orElse: () => cameras.first),
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Camera Initialization Error: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  Future<void> _captureAndCheckQuality() async {
    if (!_isCameraInitialized || _cameraController == null || _isCheckingQuality) return;

    setState(() => _isCheckingQuality = true);

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      await Future.delayed(const Duration(milliseconds: 1500));
      widget.onScan();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture failed. Try again.'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingQuality = false);
      }
    }
  }

  void _openFormLinkModal() {
    final TextEditingController urlController = TextEditingController();
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                    // FIX: Use a uniform border color so borderRadius works correctly
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border.all(
                        color: AppColors.gold.withOpacity(0.35),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.insert_link_rounded, color: AppColors.gold, size: 22),
                            const SizedBox(width: 10),
                            const Text(
                              'Send Form Link',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: urlController,
                          autofocus: true,
                          keyboardType: TextInputType.url,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          cursorColor: AppColors.gold,
                          decoration: InputDecoration(
                            hintText: 'Paste Google Form or survey link here...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                            prefixIcon: Icon(Icons.link, color: AppColors.gold.withOpacity(0.7)),
                            errorText: errorText,
                            errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.07),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.15), width: 1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppColors.gold.withOpacity(0.7), width: 1.5),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.redAccent, width: 1),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                            ),
                          ),
                          onChanged: (_) {
                            if (errorText != null) {
                              setModalState(() => errorText = null);
                            }
                          },
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                                    color: Colors.white.withOpacity(0.06),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  final url = urlController.text.trim();
                                  final uri = Uri.tryParse(url);
                                  final isValid = uri != null &&
                                      (uri.scheme == 'http' || uri.scheme == 'https') &&
                                      uri.host.isNotEmpty;

                                  if (!isValid) {
                                    setModalState(() => errorText = 'Please enter a valid URL (e.g. https://...)');
                                    return;
                                  }

                                  Navigator.of(context).pop();
                                  if (widget.onSendFormLink != null) {
                                    widget.onSendFormLink!(url);
                                  } else {
                                    debugPrint('Form link submitted: $url');
                                  }

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Form link sent!'),
                                      backgroundColor: AppColors.gold.withOpacity(0.9),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: AppColors.gold,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.gold.withOpacity(0.4),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Send',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraController == null) {
      return Container(
        color: Colors.black,
        width: double.infinity,
        child: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    final size = MediaQuery.of(context).size;
    final scanAreaWidth = size.width * 0.92;
    final scanAreaHeight = size.height * 0.68;

    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.45),
      width: scanAreaWidth,
      height: scanAreaHeight,
    );

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),

          CustomPaint(
            painter: _ScannerOverlayPainter(scanRect: scanRect),
          ),

          // Glowing laser animation
          AnimatedBuilder(
            animation: _scanLineController,
            builder: (context, child) {
              final currentY = scanRect.top + (_scanLineController.value * scanRect.height);
              return Positioned(
                top: currentY,
                left: scanRect.left,
                child: Container(
                  width: scanRect.width,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    boxShadow: [
                      BoxShadow(color: AppColors.gold.withOpacity(0.8), blurRadius: 15, spreadRadius: 3),
                      const BoxShadow(color: Colors.white, blurRadius: 4, spreadRadius: 0),
                    ],
                  ),
                ),
              );
            },
          ),

          // TOP NAVIGATION BAR — SCANNER label left, form link + sync buttons right
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SCANNER',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                Row(
                  children: [
                    // Send Form Link button — sits just to the left of sync
                    GestureDetector(
                      onTap: _openFormLinkModal,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold.withOpacity(0.5)),
                        ),
                        child: const Icon(Icons.insert_link_rounded, color: AppColors.gold, size: 28),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Sync button
                    GestureDetector(
                      onTap: widget.onOpenSync,
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: const Icon(Icons.cloud_sync, color: Colors.white, size: 28),
                          ),
                          if (widget.queueCount > 0)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              child: Text(
                                '${widget.queueCount}',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Controls
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: _isCheckingQuality ? Colors.orange.withOpacity(0.8) : Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isCheckingQuality) ...[
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                                const SizedBox(width: 12),
                              ],
                              Text(
                                _isCheckingQuality ? 'Validating Clarity...' : 'Align SS Form 2 in brackets',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _captureAndCheckQuality,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: _isCheckingQuality ? 76 : 88,
                        height: _isCheckingQuality ? 76 : 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.2),
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: _isCheckingQuality ? 32 : 70,
                            height: _isCheckingQuality ? 32 : 70,
                            decoration: BoxDecoration(
                              color: _isCheckingQuality ? AppColors.gold : Colors.white,
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.circular(_isCheckingQuality ? 8 : 50),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect scanRect;

  _ScannerOverlayPainter({required this.scanRect});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = Colors.black.withOpacity(0.7);
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final holePath = Path()..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16)));
    final finalPath = Path.combine(PathOperation.difference, backgroundPath, holePath);

    canvas.drawPath(finalPath, backgroundPaint);

    final borderPaint = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const double cornerLength = 45.0;
    const double r = 16.0;

    // Top Left Corner
    canvas.drawPath(Path()
      ..moveTo(scanRect.left, scanRect.top + cornerLength)
      ..lineTo(scanRect.left, scanRect.top + r)
      ..quadraticBezierTo(scanRect.left, scanRect.top, scanRect.left + r, scanRect.top)
      ..lineTo(scanRect.left + cornerLength, scanRect.top), borderPaint);

    // Top Right Corner
    canvas.drawPath(Path()
      ..moveTo(scanRect.right - cornerLength, scanRect.top)
      ..lineTo(scanRect.right - r, scanRect.top)
      ..quadraticBezierTo(scanRect.right, scanRect.top, scanRect.right, scanRect.top + r)
      ..lineTo(scanRect.right, scanRect.top + cornerLength), borderPaint);

    // Bottom Left Corner
    canvas.drawPath(Path()
      ..moveTo(scanRect.left, scanRect.bottom - cornerLength)
      ..lineTo(scanRect.left, scanRect.bottom - r)
      ..quadraticBezierTo(scanRect.left, scanRect.bottom, scanRect.left + r, scanRect.bottom)
      ..lineTo(scanRect.left + cornerLength, scanRect.bottom), borderPaint);

    // Bottom Right Corner
    canvas.drawPath(Path()
      ..moveTo(scanRect.right - cornerLength, scanRect.bottom)
      ..lineTo(scanRect.right - r, scanRect.bottom)
      ..quadraticBezierTo(scanRect.right, scanRect.bottom, scanRect.right, scanRect.bottom - r)
      ..lineTo(scanRect.right, scanRect.bottom - cornerLength), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}