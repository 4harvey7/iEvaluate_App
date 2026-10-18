import 'dart:math' as math;

/// Deterministic packed word-cloud layout.
/// Pure Dart (no Flutter / pdf imports) so it can be unit tested.

/// Sums counts of rows that share the same word/phrase (trimmed, as-is).
Map<String, int> sumWordCounts(Iterable<MapEntry<String, int>> rows) {
  final out = <String, int>{};
  for (final r in rows) {
    final k = r.key.trim();
    if (k.isEmpty) continue;
    out[k] = (out[k] ?? 0) + (r.value < 1 ? 1 : r.value);
  }
  return out;
}

class CloudWord {
  final String word;
  final int count;
  final double fontSize;
  final double x; // left of the (post-rotation) box
  final double y; // top of the (post-rotation) box
  final double w; // post-rotation box width
  final double h; // post-rotation box height
  final bool rotated;
  const CloudWord(this.word, this.count, this.fontSize, this.x, this.y, this.w, this.h, this.rotated);
}

// Helvetica-Bold advance widths per 1000 em, a-z.
const List<int> _hb = [
  556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889,
  611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500,
];

double estimateTextWidth(String s, double fontSize) {
  var units = 0;
  for (final r in s.runes) {
    units += (r >= 97 && r <= 122) ? _hb[r - 97] : 556;
  }
  return units * fontSize / 1000;
}

/// Packs words along an Archimedean spiral from the centre. Deterministic.
/// Words that cannot be placed are skipped. Result is ordered by frequency.
List<CloudWord> layoutWordCloud(
  Map<String, int> freq, {
  required double width,
  required double height,
  double minSize = 7,
  double maxSize = 40,
  int maxWords = 100,
  double padding = 1.2,
}) {
  final entries = freq.entries.where((e) => e.key.isNotEmpty).toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  final words = entries.take(maxWords).toList();
  if (words.isEmpty) return const [];

  final maxC = words.first.value;
  final minC = words.last.value;
  final span = (maxC - minC) == 0 ? 1 : (maxC - minC);

  final placed = <CloudWord>[];
  final cx = width / 2, cy = height / 2;
  final aspect = width / height;
  final maxR = math.sqrt(width * width + height * height);

  bool fits(double x, double y, double w, double h) {
    if (x < 0 || y < 0 || x + w > width || y + h > height) return false;
    for (final p in placed) {
      if (x < p.x + p.w + padding &&
          x + w + padding > p.x &&
          y < p.y + p.h + padding &&
          y + h + padding > p.y) {
        return false;
      }
    }
    return true;
  }

  CloudWord? tryPlace(MapEntry<String, int> e, double size, bool rot) {
    final tw = estimateTextWidth(e.key, size) + 1;
    final th = size * 1.1;
    final w = rot ? th : tw;
    final h = rot ? tw : th;
    // Archimedean spiral r = k * theta, x stretched to the box aspect.
    const k = 0.9;
    for (var theta = 0.0; k * theta < maxR; theta += 0.15) {
      final r = k * theta;
      final x = cx + r * aspect * math.cos(theta) - w / 2;
      final y = cy + r * math.sin(theta) - h / 2;
      if (fits(x, y, w, h)) return CloudWord(e.key, e.value, size, x, y, w, h, rot);
    }
    return null;
  }

  for (var i = 0; i < words.length; i++) {
    final e = words[i];
    final t = math.sqrt((e.value - minC) / span);
    final size = minSize + (maxSize - minSize) * t;
    // ~25%, never the biggest item, and only short single words (never phrases).
    final canRot = !e.key.contains(' ') && e.key.length <= 12;
    final wantRot = canRot && i != 0 && (i + 1) % 4 == 0;
    final cw = tryPlace(e, size, wantRot) ?? (canRot ? tryPlace(e, size, !wantRot) : null);
    if (cw != null) placed.add(cw);
  }
  return placed;
}
