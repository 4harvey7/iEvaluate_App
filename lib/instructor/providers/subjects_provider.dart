import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/subject.dart';

class SubjectsProvider extends ChangeNotifier {
  static const String _storageKey = 'instructor_subjects_v1';

  final List<Subject> _subjects = [];

  UnmodifiableListView<Subject> get subjects =>
      UnmodifiableListView(_subjects);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _subjects.clear();
      return;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    _subjects
      ..clear()
      ..addAll(decoded
          .cast<Map<String, dynamic>>()
          .map(Subject.fromJson));
    notifyListeners();
  }

  Future<void> add(Subject subject) async {
    _subjects.add(subject);
    await _persist();
    notifyListeners();
  }

  bool exists(String code) {
    final needle = code.trim().toLowerCase();
    return _subjects.any((s) => s.code.toLowerCase() == needle);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_subjects.map((s) => s.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}
