import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../utils/word_cloud_layout.dart';

/// Shared packed word cloud (same layout and palette as the official PDF).
/// Fills the available width; height is fixed by [height].
class PackedWordCloud extends StatefulWidget {
  final Map<String, int> frequencies;
  final double height;

  /// Use the lighter viridis variant on dark panels.
  final bool onDarkBackground;
  final double minFontSize;
  final double maxFontSize;

  const PackedWordCloud({
    super.key,
    required this.frequencies,
    this.height = 220,
    this.onDarkBackground = false,
    this.minFontSize = 10,
    this.maxFontSize = 40,
  });

  // Brand-derived: biggest words get the strongest brand blue.
  static const List<Color> lightPalette = [
    AppColors.primaryDeep,
    AppColors.primary,
    Color(0xFF4745C4), // indigo, darkened for contrast on white
    Color(0xFF007A80), // teal, darkened for contrast on white
    Color(0xFF6B3FD4), // purple, darkened for contrast on white
    Color(0xFF3D6FA8), // muted brand blue
  ];

  // Light tints of the same hues for the blue hero-gradient panels.
  static const List<Color> darkPalette = [
    Color(0xFFFFFFFF),
    AppColors.onHeroGood,
    AppColors.accent,
    Color(0xFFA8E6E6), // teal tint
    Color(0xFFC8C7FF), // indigo tint
    Color(0xFFD8C8FF), // purple tint
  ];

  @override
  State<PackedWordCloud> createState() => _PackedWordCloudState();
}

class _PackedWordCloudState extends State<PackedWordCloud> {
  List<CloudWord> _placed = const [];
  Object? _key;

  List<CloudWord> _layout(double w, double h) {
    final key = (widget.frequencies, w, h, widget.minFontSize, widget.maxFontSize);
    if (_key != key) {
      _placed = layoutWordCloud(
        widget.frequencies,
        width: w,
        height: h,
        minSize: widget.minFontSize,
        maxSize: widget.maxFontSize < h * 0.25 ? widget.maxFontSize : h * 0.25,
      );
      _key = key;
    }
    return _placed;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.onDarkBackground ? PackedWordCloud.darkPalette : PackedWordCloud.lightPalette;
    return LayoutBuilder(builder: (context, c) {
      final w = c.hasBoundedWidth ? c.maxWidth : 300.0;
      final h = widget.height;
      final placed = _layout(w, h);
      return SizedBox(
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (var i = 0; i < placed.length; i++) _word(placed[i], i, palette),
          ],
        ),
      );
    });
  }

  Widget _word(CloudWord cw, int i, List<Color> palette) {
    final text = Text(
      cw.word,
      softWrap: false,
      maxLines: 1,
      style: TextStyle(
        fontSize: cw.fontSize,
        fontWeight: FontWeight.w800,
        height: 1.0,
        color: i == 0 ? palette.first : palette[(i * 5 + 1) % palette.length],
      ),
    );
    // Box sizes are estimates; FittedBox shrinks a word that measures wider
    // instead of letting it overflow into a neighbour.
    final inner = cw.rotated ? cw.h : cw.w;
    final cross = cw.rotated ? cw.w : cw.h;
    Widget box = SizedBox(
      width: inner,
      height: cross,
      child: FittedBox(fit: BoxFit.scaleDown, child: text),
    );
    if (cw.rotated) box = RotatedBox(quarterTurns: 3, child: box);
    return Positioned(left: cw.x, top: cw.y, width: cw.w, height: cw.h, child: box);
  }
}
