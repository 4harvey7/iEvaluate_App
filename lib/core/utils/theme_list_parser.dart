/// Result of parsing a stored theme column (positive_themes /
/// improvement_insights). Either [items] (a list) or [text] (prose), or both
/// empty when there is nothing to show.
class ThemeValue {
  final List<String> items;
  final String text;
  const ThemeValue({this.items = const [], this.text = ''});

  bool get isEmpty => items.isEmpty && text.isEmpty;

  /// "A", "A and B", "A, B, and C"; prose is returned unchanged.
  String toNaturalList() {
    if (items.isEmpty) return text;
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
  }
}

/// Parses Postgres array literals ({"a","b",c}), JSON-ish arrays, plain comma
/// lists and plain prose into a [ThemeValue].
ThemeValue parseThemeValue(Object? raw) {
  if (raw == null) return const ThemeValue();
  if (raw is Iterable) {
    return ThemeValue(items: _dedupe(raw.map((e) => _clean(e.toString()))));
  }
  final s = raw.toString().trim();
  if (s.isEmpty || s.toUpperCase() == 'NULL') return const ThemeValue();

  final wrapped = (s.startsWith('{') && s.endsWith('}')) ||
      (s.startsWith('[') && s.endsWith(']'));
  if (wrapped) {
    final inner = s.substring(1, s.length - 1);
    return ThemeValue(items: _dedupe(_splitOutsideQuotes(inner)));
  }

  // Plain comma list: several short fragments and no sentence punctuation.
  if (s.contains(',') && !RegExp(r'[.!?;:]').hasMatch(s) && !s.contains('"')) {
    final parts = _dedupe(_splitOutsideQuotes(s));
    final short = parts.every((p) => p.split(RegExp(r'\s+')).length <= 6);
    if (parts.length > 1 && short) return ThemeValue(items: parts);
  }
  return ThemeValue(text: s);
}

String _clean(String s) {
  final t = s.trim();
  return t.toUpperCase() == 'NULL' ? '' : t;
}

List<String> _dedupe(Iterable<String> items) {
  final seen = <String>{};
  final out = <String>[];
  for (final i in items) {
    final t = i.trim();
    if (t.isEmpty || t.toUpperCase() == 'NULL') continue;
    if (seen.add(t.toLowerCase())) out.add(t);
  }
  return out;
}

/// Splits on commas that are not inside double quotes. Inside quotes, \" and ""
/// are unescaped to ". Items are trimmed; empty / unquoted NULL are dropped by
/// the caller.
List<String> _splitOutsideQuotes(String s) {
  final out = <String>[];
  final cur = StringBuffer();
  var inQuotes = false;
  var wasQuoted = false;
  void flush() {
    final v = cur.toString().trim();
    out.add(!wasQuoted && v.toUpperCase() == 'NULL' ? '' : v);
    cur.clear();
    wasQuoted = false;
  }

  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inQuotes) {
      if (c == r'\' && i + 1 < s.length) {
        cur.write(s[++i]);
      } else if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cur.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
      wasQuoted = true;
    } else if (c == r'\' && i + 1 < s.length && s[i + 1] == '"') {
      cur.write('"');
      i++;
    } else if (c == ',') {
      flush();
    } else {
      cur.write(c);
    }
  }
  flush();
  return out;
}
