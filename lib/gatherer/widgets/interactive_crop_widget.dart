// lib/gatherer/widgets/interactive_crop_widget.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// A full-image interactive crop tool.
///
/// Shows [imageFile] in full and overlays a draggable/resizable rectangle.
/// The user moves and resizes the rectangle over the region they want to crop,
/// then taps "Confirm Crop" to get back relative coordinates (0.0–1.0).
///
/// Usage:
/// ```dart
/// InteractiveCropWidget(
///   imageFile: File(localPath),
///   fieldName: 'instructor',
///   onConfirm: (rect) {
///     // rect = {x1f, y1f, x2f, y2f}  all in 0.0–1.0 range
///   },
///   onCancel: () => Navigator.pop(context),
/// )
/// ```
class InteractiveCropWidget extends StatefulWidget {
  final File imageFile;
  final String fieldName;
  final void Function(Map<String, double> relativeRect) onConfirm;
  final VoidCallback onCancel;

  const InteractiveCropWidget({
    super.key,
    required this.imageFile,
    required this.fieldName,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<InteractiveCropWidget> createState() => _InteractiveCropWidgetState();
}

class _InteractiveCropWidgetState extends State<InteractiveCropWidget> {
  // Rect in 0.0–1.0 relative coords
  double _x1 = 0.15;
  double _y1 = 0.15;
  double _x2 = 0.85;
  double _y2 = 0.40;

  // Handle size in logical pixels
  static const double _handleSize = 22.0;
  static const double _handleHit = 32.0; // larger hit area for easy touch

  // Image render area (set once image is laid out)
  final GlobalKey _imageKey = GlobalKey();
  Size _imageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    // Trigger _updateImageSize after the first frame so the crop box
    // appears immediately without needing to wait for a pan gesture.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateImageSize());
  }

  void _updateImageSize() {
    final box =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final s = box.size;
      if (s != _imageSize) setState(() => _imageSize = s);
    }
  }

  void _onPanRect(DragUpdateDetails d) {
    if (_imageSize == Size.zero) return;
    final dx = d.delta.dx / _imageSize.width;
    final dy = d.delta.dy / _imageSize.height;
    final w = _x2 - _x1;
    final h = _y2 - _y1;
    setState(() {
      _x1 = (_x1 + dx).clamp(0.0, 1.0 - w);
      _y1 = (_y1 + dy).clamp(0.0, 1.0 - h);
      _x2 = _x1 + w;
      _y2 = _y1 + h;
    });
  }

  void _onPanTopLeft(DragUpdateDetails d) {
    if (_imageSize == Size.zero) return;
    setState(() {
      _x1 = (_x1 + d.delta.dx / _imageSize.width).clamp(0.0, _x2 - 0.05);
      _y1 = (_y1 + d.delta.dy / _imageSize.height).clamp(0.0, _y2 - 0.02);
    });
  }

  void _onPanTopRight(DragUpdateDetails d) {
    if (_imageSize == Size.zero) return;
    setState(() {
      _x2 = (_x2 + d.delta.dx / _imageSize.width).clamp(_x1 + 0.05, 1.0);
      _y1 = (_y1 + d.delta.dy / _imageSize.height).clamp(0.0, _y2 - 0.02);
    });
  }

  void _onPanBottomLeft(DragUpdateDetails d) {
    if (_imageSize == Size.zero) return;
    setState(() {
      _x1 = (_x1 + d.delta.dx / _imageSize.width).clamp(0.0, _x2 - 0.05);
      _y2 = (_y2 + d.delta.dy / _imageSize.height).clamp(_y1 + 0.02, 1.0);
    });
  }

  void _onPanBottomRight(DragUpdateDetails d) {
    if (_imageSize == Size.zero) return;
    setState(() {
      _x2 = (_x2 + d.delta.dx / _imageSize.width).clamp(_x1 + 0.05, 1.0);
      _y2 = (_y2 + d.delta.dy / _imageSize.height).clamp(_y1 + 0.02, 1.0);
    });
  }

  Widget _handle(void Function(DragUpdateDetails) onPan, Alignment alignment) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onPan,
        child: SizedBox(
          width: _handleHit,
          height: _handleHit,
          child: Center(
            child: Container(
              width: _handleSize,
              height: _handleSize,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Manual Crop',
                style:
                    TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            Text(
              'Cropping: ${widget.fieldName.toUpperCase()}',
              style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: widget.onCancel,
        ),
      ),
      body: Column(
        children: [
          // ── Instruction bar ─────────────────────────────────────────
          Container(
            width: double.infinity,
            color: AppColors.primary.withValues(alpha: 0.15),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.touch_app,
                    color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Drag the box to move. Drag the orange corners to resize. '
                    'Cover the field you want to read.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // ── Image + crop overlay ────────────────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTap: () {}, // absorb taps on image background
                  child: Stack(
                    children: [
                      // The full image
                      Positioned.fill(
                        child: Image.file(
                          widget.imageFile,
                          key: _imageKey,
                          fit: BoxFit.contain,
                        ),
                      ),

                      // Dark overlay outside the crop rect
                      if (_imageSize != Size.zero)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CropOverlayPainter(
                              imageSize: _imageSize,
                              containerSize: constraints.biggest,
                              x1: _x1,
                              y1: _y1,
                              x2: _x2,
                              y2: _y2,
                            ),
                          ),
                        ),

                      // Crop rect + handles
                      if (_imageSize != Size.zero)
                        _buildCropRect(constraints.biggest),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Bottom action buttons ────────────────────────────────────
          Container(
            color: const Color(0xFF1A1A1A),
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.white38),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: widget.onCancel,
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.crop, size: 18),
                    label: const Text('Confirm Crop',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      widget.onConfirm({
                        'x1f': _x1,
                        'y1f': _y1,
                        'x2f': _x2,
                        'y2f': _y2,
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropRect(Size containerSize) {
    // Compute image display rect inside Contain fit
    final imgAspect =
        _imageSize.width / _imageSize.height.clamp(1, double.infinity);
    final containerAspect = containerSize.width /
        containerSize.height.clamp(1, double.infinity);

    double displayW, displayH, offsetX, offsetY;
    if (imgAspect > containerAspect) {
      displayW = containerSize.width;
      displayH = containerSize.width / imgAspect;
      offsetX = 0;
      offsetY = (containerSize.height - displayH) / 2;
    } else {
      displayH = containerSize.height;
      displayW = containerSize.height * imgAspect;
      offsetY = 0;
      offsetX = (containerSize.width - displayW) / 2;
    }

    final rectLeft = offsetX + _x1 * displayW;
    final rectTop = offsetY + _y1 * displayH;
    final rectRight = offsetX + _x2 * displayW;
    final rectBottom = offsetY + _y2 * displayH;
    final rectW = rectRight - rectLeft;
    final rectH = rectBottom - rectTop;

    // Update _imageSize with actual display size for pan calculations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_imageSize.width != displayW || _imageSize.height != displayH) {
        setState(() => _imageSize = Size(displayW, displayH));
      }
    });

    return Positioned(
      left: rectLeft,
      top: rectTop,
      width: rectW,
      height: rectH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Move entire rect
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: _onPanRect,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
              ),
            ),
          ),
          // Field label inside rect
          Positioned(
            top: 4,
            left: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.fieldName.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          // Corner handles
          _handle(_onPanTopLeft, Alignment.topLeft),
          _handle(_onPanTopRight, Alignment.topRight),
          _handle(_onPanBottomLeft, Alignment.bottomLeft),
          _handle(_onPanBottomRight, Alignment.bottomRight),
        ],
      ),
    );
  }
}

/// Draws a semi-transparent dark overlay outside the crop rectangle,
/// with a clear "window" where the crop rect is.
class _CropOverlayPainter extends CustomPainter {
  final Size imageSize;
  final Size containerSize;
  final double x1, y1, x2, y2;

  const _CropOverlayPainter({
    required this.imageSize,
    required this.containerSize,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imgAspect = imageSize.width / imageSize.height.clamp(1, double.infinity);
    final containerAspect =
        containerSize.width / containerSize.height.clamp(1, double.infinity);

    double displayW, displayH, offsetX, offsetY;
    if (imgAspect > containerAspect) {
      displayW = containerSize.width;
      displayH = containerSize.width / imgAspect;
      offsetX = 0;
      offsetY = (containerSize.height - displayH) / 2;
    } else {
      displayH = containerSize.height;
      displayW = containerSize.height * imgAspect;
      offsetY = 0;
      offsetX = (containerSize.width - displayW) / 2;
    }

    final cropRect = Rect.fromLTRB(
      offsetX + x1 * displayW,
      offsetY + y1 * displayH,
      offsetX + x2 * displayW,
      offsetY + y2 * displayH,
    );

    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);

    // Paint full canvas then "punch out" the crop window
    final fullPath = Path()..addRect(Offset.zero & size);
    final cropPath = Path()..addRect(cropRect);
    final overlayPath =
        Path.combine(PathOperation.difference, fullPath, cropPath);
    canvas.drawPath(overlayPath, overlayPaint);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.x1 != x1 || old.y1 != y1 || old.x2 != x2 || old.y2 != y2 ||
      old.imageSize != imageSize;
}
