// lib/gatherer/gatherer_scanner_view.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:ui';
import '../app_colors.dart';

class GathererScannerView extends StatefulWidget {
  final VoidCallback onScan;
  const GathererScannerView({super.key, required this.onScan});

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

    // ==========================================
    // UPDATED SIZING FOR A LARGER SCAN WINDOW
    // ==========================================
    final scanAreaWidth = size.width * 0.92;   // Widened to 92% of the screen
    final scanAreaHeight = size.height * 0.68; // Heightened to 68% of the screen

    // Re-balanced the center to 45% so the taller box doesn't crash into the shutter button
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
          // 1. LIVE CAMERA FEED
          CameraPreview(_cameraController!),

          // 2. THE PREMIUM DARK OVERLAY & CORNER BRACKETS
          CustomPaint(
            painter: _ScannerOverlayPainter(scanRect: scanRect),
          ),

          // 3. GLOWING LASER SCAN ANIMATION
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

          // 4. UI ELEMENTS
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // FROSTED GLASS INSTRUCTION CHIP
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

                    const SizedBox(height: 24), // Spacing between chip and button

                    // REFINED SHUTTER BUTTON
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

// ==========================================
// CUSTOM PAINTER FOR PRO SCANNER LOOK
// ==========================================
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