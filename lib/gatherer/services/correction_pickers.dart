// lib/gatherer/services/correction_pickers.dart
//
// Instructor and subject pickers for the "Correct Failed Scan" screen.
//
// The screen used to pre-fill only the text the scan read, so unless staff
// re-picked both entries no ids were sent, n8n's strict name lookup often
// missed, and the scan landed in Import Errors where staff had to pick the
// instructor and subject AGAIN. Now the screen:
//   - loads the people a form can be credited to (approved instructors with a
//     DEPARTMENT_HEAD / FULL-TIME / PART-TIME role, plus placeholder
//     instructors -- the same rule n8n and the website use) and the subjects;
//   - pre-selects the AI's suggestion, or the entry the scan text clearly
//     names (the same token matcher n8n uses: n8n/tools/website_src/name_match.js);
//   - sends instructor_id / subject_id with the names;
//   - understands n8n's HTTP 422 answer (instructor/subject not found).
//
// Everything below except [CorrectionPickerData.load] is pure Dart so it can
// be unit-tested without a device.
import 'package:supabase_flutter/supabase_flutter.dart';

/// A person a correction can be credited to.
class PickerInstructor {
  final String id;
  final String name;
  final bool isPlaceholder;
  const PickerInstructor({required this.id, required this.name, this.isPlaceholder = false});
}

/// A subject a correction can be credited to.
class PickerSubject {
  final String id;
  final String code;
  final String name;
  const PickerSubject({required this.id, required this.code, required this.name});

  /// "IT 101 — Introduction to Computing" (or whichever part exists).
  String get display {
    if (code.isEmpty) return name;
    if (name.isEmpty) return code;
    return '$code — $name';
  }
}

/// Result of a text match against a picker list.
class PickerMatch<T> {
  /// 'found' (one clear entry), 'ambiguous' (several close ones) or 'none'.
  final String match;
  final T? pick;
  final List<T> contenders;
  const PickerMatch(this.match, this.pick, [this.contenders = const []]);
  bool get isFound => match == 'found' && pick != null;
}

/// Token fuzzy matching, a Dart port of n8n's website_src/name_match.js, so
/// the app pre-selects exactly what n8n would accept as a clear match.
class NameMatch {
  NameMatch._();

  static const double tokenMin = 0.55;
  static const double instructorMin = 0.70;
  static const double instructorMargin = 0.10;
  static const double subjectMin = 0.60;
  static const double subjectCover = 0.75;
  static const double subjectMargin = 0.10;
  static const double _eps = 1e-6;

  static const Set<String> _titles = {
    'prof', 'professor', 'dr', 'doc', 'mr', 'mrs', 'ms', 'miss', 'madam', 'maam', 'sir', 'engr',
    'eng', 'atty', 'arch', 'rev', 'fr', 'hon', 'instr', 'instructor', 'teacher', 'phd', 'edd', 'dba', 'mba', 'mit', 'mat',
    'maed', 'lpt', 'rn', 'cpa', 'jr', 'sr', 'ii', 'iii', 'iv',
  };
  static const Set<String> _stop = {'and', 'of', 'the', 'to', 'in', 'for', 'with', 'on', 'a', 'an', 'at'};
  static const Map<String, String> _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
  };

  static String fold(String? s) {
    final lower = (s ?? '').toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      b.write(_accents[ch] ?? ch);
    }
    return b.toString();
  }

  /// Person name -> tokens, titles and degrees dropped.
  static List<String> nameTokens(String? s) {
    final t = fold(s)
        .replaceAll(RegExp(r"\bma['’‘`´]?am\b"), ' maam ')
        .replaceAll(RegExp(r'[^a-z]+'), ' ')
        .split(' ');
    return t.where((w) => w.isNotEmpty && !_titles.contains(w)).toList();
  }

  /// Subject title -> word tokens; tokens mixing letters and digits are codes.
  static List<String> subjectTokens(String? s) {
    final t = fold(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').split(' ');
    return t
        .where((w) =>
            w.isNotEmpty &&
            !_stop.contains(w) &&
            !(RegExp(r'[a-z]').hasMatch(w) && RegExp(r'[0-9]').hasMatch(w)))
        .toList();
  }

  static String alnum(String? s) => fold(s).replaceAll(RegExp(r'[^a-z0-9]'), '').toUpperCase();

  /// Code-like keys on the text (letters + digits), e.g. "PC 121" -> PC121.
  static List<String> codeKeys(String? s) {
    final up = fold(s).toUpperCase();
    final keys = <String>{};
    for (final m in RegExp(r'\b([A-Z]{2,8})[ .-]?([0-9]{1,4}[A-Z]?)\b').allMatches(up)) {
      keys.add('${m.group(1)}${m.group(2)}');
    }
    final whole = alnum(s);
    if (RegExp(r'[A-Z]').hasMatch(whole) && RegExp(r'[0-9]').hasMatch(whole) && whole.length <= 12) {
      keys.add(whole);
    }
    return keys.where((k) => k.length >= 3).toList();
  }

  static int edit(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, sub].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// want = database token, got = typed/scanned token.
  static double tokenSim(String want, String got) {
    if (want == got) return 1;
    if (want.length == 1 || got.length == 1) return want[0] == got[0] ? 0.7 : 0;
    if (got.length >= 4 && want.startsWith(got)) return 0.85;
    final longer = want.length > got.length ? want.length : got.length;
    final r = 1 - edit(want, got) / longer;
    return r >= tokenMin ? r : 0;
  }

  /// (score, cover): weighted share of matched tokens, 0.75 database side +
  /// 0.25 text side (same as nmScore).
  static ({double score, double cover}) score(List<String> want, List<String> got) {
    if (want.isEmpty || got.isEmpty) return (score: 0, cover: 0);
    double w(String t) => t.length == 1 ? 1 : t.length.toDouble();
    final pairs = <(double, int, int)>[];
    for (var i = 0; i < want.length; i++) {
      for (var j = 0; j < got.length; j++) {
        final s = tokenSim(want[i], got[j]);
        if (s > 0) pairs.add((s, i, j));
      }
    }
    pairs.sort((x, y) {
      final c = y.$1.compareTo(x.$1);
      if (c != 0) return c;
      final ci = x.$2.compareTo(y.$2);
      return ci != 0 ? ci : x.$3.compareTo(y.$3);
    });
    final usedA = <int>{};
    final usedB = <int>{};
    var hitA = 0.0;
    var hitB = 0.0;
    for (final p in pairs) {
      if (usedA.contains(p.$2) || usedB.contains(p.$3)) continue;
      usedA.add(p.$2);
      usedB.add(p.$3);
      hitA += p.$1 * w(want[p.$2]);
      hitB += p.$1 * w(got[p.$3]);
    }
    double sum(List<String> ts) => ts.fold(0.0, (t, x) => t + w(x));
    final cover = hitA / sum(want);
    final sc = 0.75 * cover + 0.25 * (hitB / sum(got));
    double r4(double v) => (v * 10000).round() / 10000;
    return (score: r4(sc), cover: r4(cover));
  }

  /// The instructor the text clearly names (nmBestInstructor: >= 0.70 and
  /// beats every other entry by 0.10; two people with the same name are
  /// always ambiguous).
  static PickerMatch<PickerInstructor> bestInstructor(String? text, List<PickerInstructor> list) {
    final got = nameTokens(text);
    if (got.isEmpty || list.isEmpty) return const PickerMatch('none', null);
    final scored = list
        .map((p) => (p: p, s: score(nameTokens(p.name), got).score))
        .where((x) => x.s >= instructorMin - _eps)
        .toList()
      ..sort((a, b) => b.s.compareTo(a.s));
    if (scored.isEmpty) return const PickerMatch('none', null);
    final close = scored.where((x) => scored.first.s - x.s < instructorMargin - _eps).map((x) => x.p).toList();
    if (close.length > 1) return PickerMatch('ambiguous', null, close);
    return PickerMatch('found', scored.first.p);
  }

  /// The subject the text clearly names: one exact code on the text, else
  /// one title that is mostly on the text and beats the others by 0.10. A
  /// course code that is no subject never picks a subject by its title.
  static PickerMatch<PickerSubject> bestSubject(String? text, List<PickerSubject> list) {
    final raw = (text ?? '').trim();
    if (raw.isEmpty || list.isEmpty) return const PickerMatch('none', null);
    final keys = codeKeys(raw);
    final rawKey = alnum(raw);
    final exact = list.where((s) {
      final k = alnum(s.code);
      return k.isNotEmpty && (keys.contains(k) || rawKey == k);
    }).toList();
    if (exact.length == 1) return PickerMatch('found', exact.first);
    if (exact.length > 1) return PickerMatch('ambiguous', null, exact);
    final unknownCode = keys.any((k) => RegExp(r'[A-Z]').hasMatch(k) && RegExp(r'[0-9]{2}').hasMatch(k));
    if (unknownCode) return const PickerMatch('none', null);
    final got = subjectTokens(raw);
    final strong = list
        .map((s) => (s: s, r: score(subjectTokens(s.name), got)))
        .where((x) => x.r.score >= subjectMin - _eps && x.r.cover >= subjectCover - _eps)
        .toList()
      ..sort((a, b) => b.r.score.compareTo(a.r.score));
    if (strong.isEmpty) return const PickerMatch('none', null);
    if (strong.length == 1 || strong[0].r.score - strong[1].r.score >= subjectMargin - _eps) {
      return PickerMatch('found', strong.first.s);
    }
    final close = strong.where((x) => strong[0].r.score - x.r.score < subjectMargin - _eps).map((x) => x.s).toList();
    return PickerMatch('ambiguous', null, close);
  }
}

/// Searchable list filtering for the pickers (local, no query per keystroke).
class PickerSearch {
  PickerSearch._();

  static List<PickerInstructor> instructors(String query, List<PickerInstructor> list, {int limit = 8}) {
    final q = NameMatch.fold(query).trim();
    if (q.isEmpty) return list.take(limit).toList();
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final hits = list.where((p) {
      final n = NameMatch.fold(p.name);
      return words.every(n.contains);
    }).toList();
    if (hits.isNotEmpty) {
      hits.sort((a, b) {
        final sa = NameMatch.fold(a.name).startsWith(q) ? 0 : 1;
        final sb = NameMatch.fold(b.name).startsWith(q) ? 0 : 1;
        return sa != sb ? sa - sb : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return hits.take(limit).toList();
    }
    // nothing contains the text (e.g. a misread name): closest by token score
    final got = NameMatch.nameTokens(query);
    final scored = list
        .map((p) => (p: p, s: NameMatch.score(NameMatch.nameTokens(p.name), got).score))
        .where((x) => x.s >= 0.3)
        .toList()
      ..sort((a, b) => b.s.compareTo(a.s));
    return scored.take(limit).map((x) => x.p).toList();
  }

  static List<PickerSubject> subjects(String query, List<PickerSubject> list, {int limit = 8}) {
    final q = NameMatch.fold(query).trim();
    if (q.isEmpty) return list.take(limit).toList();
    final qKey = NameMatch.alnum(query);
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final hits = list.where((s) {
      final code = NameMatch.alnum(s.code);
      if (qKey.isNotEmpty && code.contains(qKey)) return true;
      final hay = NameMatch.fold('${s.code} ${s.name}');
      return words.every(hay.contains);
    }).toList();
    if (hits.isNotEmpty) {
      hits.sort((a, b) {
        final sa = NameMatch.alnum(a.code).startsWith(qKey) && qKey.isNotEmpty ? 0 : 1;
        final sb = NameMatch.alnum(b.code).startsWith(qKey) && qKey.isNotEmpty ? 0 : 1;
        return sa != sb ? sa - sb : a.code.compareTo(b.code);
      });
      return hits.take(limit).toList();
    }
    final got = NameMatch.subjectTokens(query);
    final scored = list
        .map((s) => (s: s, r: NameMatch.score(NameMatch.subjectTokens(s.name), got).score))
        .where((x) => x.r >= 0.3)
        .toList()
      ..sort((a, b) => b.r.compareTo(a.r));
    return scored.take(limit).map((x) => x.s).toList();
  }
}

/// What the scan / AI said about the instructor and subject, read from
/// failed_scan_queue.partial_data (phone and website rows).
class ScanIdentity {
  final String? suggestedInstructorId;
  final String? suggestedSubjectId;
  /// Texts to try, best first (suggested name, resolved/read text, raw OCR).
  final List<String> instructorTexts;
  final List<String> subjectTexts;
  /// What the scan itself read, shown as "Scan read: …".
  final String instructorRead;
  final String subjectRead;

  const ScanIdentity({
    this.suggestedInstructorId,
    this.suggestedSubjectId,
    this.instructorTexts = const [],
    this.subjectTexts = const [],
    this.instructorRead = '',
    this.subjectRead = '',
  });

  static final RegExp _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  static String _s(Object? v) {
    if (v == null || v is Map || v is List) return '';
    final s = v.toString().trim();
    return s == 'null' ? '' : s;
  }

  static String? _id(Object? v) {
    final s = _s(v).toLowerCase();
    return _uuid.hasMatch(s) ? s : null;
  }

  factory ScanIdentity.fromPartial(Map<String, dynamic> p) {
    final im = p['instructor_match'];
    final matchRaw = im is Map ? _s(im['raw']) : '';
    List<String> uniq(List<String> xs) {
      final seen = <String>{};
      return xs.where((x) => x.isNotEmpty && seen.add(x.toLowerCase())).toList();
    }

    final ocrI = _s(p['ocr_instructor']);
    final ocrS = _s(p['ocr_subject']);
    return ScanIdentity(
      suggestedInstructorId: _id(p['suggested_instructor_id']),
      suggestedSubjectId: _id(p['suggested_subject_id']),
      instructorTexts: uniq([_s(p['suggested_instructor_name']), _s(p['instructor']), ocrI, matchRaw]),
      subjectTexts: uniq([_s(p['suggested_subject_code']), _s(p['subject']), ocrS, _s(p['suggested_subject_name'])]),
      instructorRead: ocrI.isNotEmpty ? ocrI : (matchRaw.isNotEmpty ? matchRaw : _s(p['instructor'])),
      subjectRead: ocrS.isNotEmpty ? ocrS : _s(p['subject']),
    );
  }

  /// The instructor to pre-select: the AI's suggestion when it is on the
  /// list, else the first text that clearly names one entry.
  PickerInstructor? pickInstructor(List<PickerInstructor> list) {
    if (suggestedInstructorId != null) {
      for (final p in list) {
        if (p.id == suggestedInstructorId) return p;
      }
    }
    for (final t in instructorTexts) {
      final m = NameMatch.bestInstructor(t, list);
      if (m.isFound) return m.pick;
    }
    return null;
  }

  PickerSubject? pickSubject(List<PickerSubject> list) {
    if (suggestedSubjectId != null) {
      for (final s in list) {
        if (s.id == suggestedSubjectId) return s;
      }
    }
    for (final t in subjectTexts) {
      final m = NameMatch.bestSubject(t, list);
      if (m.isFound) return m.pick;
    }
    return null;
  }
}

/// n8n's HTTP 422 answer to a correction whose instructor or subject did not
/// resolve: {success:false, code, message, candidates:{instructors, subjects}}.
/// Nothing was saved; the scan stays pending.
class CorrectionNotFoundAnswer {
  static const String instructorNotFound = 'instructor_not_found';
  static const String subjectNotFound = 'subject_not_found';
  static const String bothNotFound = 'instructor_and_subject_not_found';
  static const Set<String> codes = {instructorNotFound, subjectNotFound, bothNotFound};

  final String code;
  final String message;
  final List<PickerInstructor> instructorCandidates;
  final List<PickerSubject> subjectCandidates;

  const CorrectionNotFoundAnswer({
    required this.code,
    required this.message,
    this.instructorCandidates = const [],
    this.subjectCandidates = const [],
  });

  bool get instructorMissing => code == instructorNotFound || code == bothNotFound;
  bool get subjectMissing => code == subjectNotFound || code == bothNotFound;

  /// Null unless [data] (Map, or a List whose first item is a Map) carries one
  /// of the not-found codes. The body decides, not the status code.
  static CorrectionNotFoundAnswer? tryParse(int statusCode, dynamic data) {
    Map<String, dynamic>? m;
    if (data is Map) {
      m = Map<String, dynamic>.from(data);
    } else if (data is List && data.isNotEmpty && data.first is Map) {
      m = Map<String, dynamic>.from(data.first as Map);
    }
    if (m == null) return null;
    final code = (m['code'] ?? '').toString().trim().toLowerCase();
    if (!codes.contains(code)) return null;
    final c = m['candidates'] is Map ? Map<String, dynamic>.from(m['candidates'] as Map) : const <String, dynamic>{};
    List<Map> list(Object? v) => v is List ? v.whereType<Map>().toList() : const [];
    final msg = (m['message'] ?? '').toString().trim();
    return CorrectionNotFoundAnswer(
      code: code,
      message: msg.isNotEmpty ? msg : 'Not saved: pick the instructor and subject from the list and submit again.',
      instructorCandidates: list(c['instructors'])
          .where((x) => (x['id'] ?? '').toString().isNotEmpty)
          .map((x) => PickerInstructor(id: x['id'].toString().toLowerCase(), name: (x['name'] ?? '').toString()))
          .toList(),
      subjectCandidates: list(c['subjects'])
          .where((x) => (x['id'] ?? '').toString().isNotEmpty)
          .map((x) => PickerSubject(
              id: x['id'].toString().toLowerCase(),
              code: (x['code'] ?? '').toString(),
              name: (x['name'] ?? '').toString()))
          .toList(),
    );
  }
}

/// The two lists behind the pickers.
class CorrectionPickerData {
  final List<PickerInstructor> instructors;
  final List<PickerSubject> subjects;
  const CorrectionPickerData(this.instructors, this.subjects);

  static const Set<String> instructorRoles = {'DEPARTMENT_HEAD', 'FULL-TIME', 'PART-TIME'};

  static bool _truthy(Object? v) =>
      v == true || const {'true', 't', '1', 'yes'}.contains(v?.toString().trim().toLowerCase());

  /// Builds the instructor list from department_table rows joined with
  /// roles + user_info, plus placeholder user_info rows (one entry per id,
  /// sorted by name). Pure, for tests.
  static List<PickerInstructor> instructorsFrom(List<dynamic> deptRows, List<dynamic> placeholderRows) {
    final byId = <String, PickerInstructor>{};
    String nameOf(Map ui) =>
        '${ui['first_name'] ?? ''} ${ui['last_name'] ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
    for (final r in deptRows.whereType<Map>()) {
      final ui = r['user_info'];
      final roles = r['roles'];
      if (ui is! Map) continue;
      final role = roles is Map ? (roles['Roles'] ?? '').toString().trim().toUpperCase() : '';
      final approved = (ui['account_status'] ?? '').toString().trim().toLowerCase() == 'approved';
      final placeholder = _truthy(ui['is_placeholder']);
      if (!((approved && instructorRoles.contains(role)) || placeholder)) continue;
      final id = (ui['id'] ?? r['user_id'] ?? '').toString().toLowerCase();
      final name = nameOf(ui);
      if (id.isEmpty || name.isEmpty) continue;
      byId[id] = PickerInstructor(id: id, name: name, isPlaceholder: placeholder);
    }
    for (final ui in placeholderRows.whereType<Map>()) {
      final id = (ui['id'] ?? '').toString().toLowerCase();
      final name = nameOf(ui);
      if (id.isEmpty || name.isEmpty || byId.containsKey(id)) continue;
      byId[id] = PickerInstructor(id: id, name: name, isPlaceholder: true);
    }
    final out = byId.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static List<PickerSubject> subjectsFrom(List<dynamic> rows) {
    final out = rows
        .whereType<Map>()
        .where((r) => (r['id'] ?? '').toString().isNotEmpty)
        .map((r) => PickerSubject(
              id: r['id'].toString().toLowerCase(),
              code: (r['subject_code'] ?? '').toString().trim(),
              name: (r['subject_name'] ?? '').toString().trim(),
            ))
        .where((s) => s.code.isNotEmpty || s.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    return out;
  }

  /// Loads both lists. A failed part comes back empty (the screen then lets
  /// staff send the typed text, and n8n matches it).
  static Future<CorrectionPickerData> load(SupabaseClient sb) async {
    List<dynamic> dept = const [];
    try {
      dept = await sb
          .from('department_table')
          .select('user_id, roles:roles(Roles), user_info!user_id(id, first_name, last_name, account_status, is_placeholder)');
    } catch (_) {
      try {
        dept = await sb
            .from('department_table')
            .select('user_id, roles:roles(Roles), user_info!user_id(id, first_name, last_name, account_status)');
      } catch (_) {}
    }
    List<dynamic> placeholders = const [];
    try {
      placeholders = await sb.from('user_info').select('id, first_name, last_name').eq('is_placeholder', true);
    } catch (_) {}
    List<dynamic> subjects = const [];
    try {
      subjects = await sb.from('subjects').select('id, subject_code, subject_name');
    } catch (_) {}
    return CorrectionPickerData(instructorsFrom(dept, placeholders), subjectsFrom(subjects));
  }
}
