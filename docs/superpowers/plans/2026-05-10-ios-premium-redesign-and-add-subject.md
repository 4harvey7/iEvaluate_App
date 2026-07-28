# iOS-Premium Redesign + Instructor Add Subject Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repalette and retypography the iEvaluate Flutter app with a Vanilla Custard / Vivid Orange / Midnight Espresso system in Inter, and add a SharedPreferences-backed `Add Subject` flow to the Instructor role.

**Architecture:** Centralize visual system in `lib/theme/{app_colors,app_text_styles,app_theme}.dart`, wire `AppTheme.light` through `MaterialApp` to upgrade all four roles globally. Add a `SubjectsProvider` (ChangeNotifier + SharedPreferences) plumbed via `MultiProvider` at app root. Introduce `MySubjectsScreen` and `AddSubjectScreen` in the Instructor role and replace the dashboard's hardcoded `_mySubjects` with a live read of the provider.

**Tech Stack:** Flutter 3.11.4+, Dart, `provider`, `shared_preferences`, `google_fonts`. Existing `camera`, `path_provider`, `url_launcher`, `flutter_launcher_icons` retained.

**Spec:** `docs/superpowers/specs/2026-05-10-ios-premium-redesign-and-add-subject-design.md`

**Branch:** `redesign/ios-premium-and-add-subject` (already created)

---

## Reference: Color & token mapping (used by repalette tasks)

| Old token | Old hex | New token | Use this in code as |
|---|---|---|---|
| `AppColors.deepBlue` | `#003A8F` | Espresso (`textPrimary`) | `AppColors.textPrimary` (most contexts), or `AppColors.surface` when the old code used it as a nav surface |
| `AppColors.royalBlue` | `#1E5BB8` | Vivid Orange (`primary`) | `AppColors.primary` |
| `AppColors.gold` | `#FFC72C` | Vivid Orange (`primary`) | `AppColors.primary` |
| `AppColors.lightGold` | `#FFE08A` | Tinted orange (`primaryTint`) | `AppColors.primaryTint` |
| `AppColors.lightGray` | `#F5F7FA` | Vanilla Custard (`background`) | `AppColors.background` |
| `AppColors.darkGray` | `#333333` | Espresso (`textPrimary`) | `AppColors.textPrimary` |
| `AppColors.white` | `#FFFFFF` | White (`surface`) | `AppColors.surface` |

Plus, ad-hoc color literals get replaced as follows:

| Pattern in old code | New token |
|---|---|
| `Colors.grey.shade300` / `Colors.grey.shade200` | `AppColors.borderHairline` |
| `Colors.grey.shade400` / `Colors.grey.shade500` | `AppColors.textTertiary` |
| `Colors.grey.shade600` / `Colors.grey` | `AppColors.textSecondary` |
| `Colors.red` / `Colors.redAccent` for status | `AppColors.error` |
| `Colors.green` for status | `AppColors.success` |
| `Colors.orange` for status | `AppColors.warning` |
| `Colors.black.withOpacity(...)` for shadows | `AppColors.textPrimary.withOpacity(...)` |

Hero gradients (`[deepBlue, royalBlue]`) become `[textPrimary, textPrimary @ 85%]`.

Imports in role files migrate from `'../app_colors.dart'` to `'../theme/app_colors.dart'`.

---

## Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add three packages under `dependencies:`**

Open `pubspec.yaml`. The `dependencies:` block currently is:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_launcher_icons: ^0.13.1
  provider: ^6.1.5+1
  url_launcher: ^6.2.6
```

Replace with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_launcher_icons: ^0.13.1
  provider: ^6.1.5+1
  url_launcher: ^6.2.6
  shared_preferences: ^2.3.0
  google_fonts: ^6.2.1
```

- [ ] **Step 2: Run pub get**

Run from project root: `flutter pub get`
Expected: `Got dependencies!` with both new packages resolved. No error.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add google_fonts and shared_preferences"
```

---

## Task 2: Subject model + tests

**Files:**
- Create: `lib/instructor/models/subject.dart`
- Create: `test/instructor/models/subject_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/instructor/models/subject_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/models/subject.dart';

void main() {
  group('Subject', () {
    test('toJson then fromJson is a round trip', () {
      final original = Subject(
        code: 'CS101',
        name: 'Intro to Programming',
        addedAt: DateTime.utc(2026, 5, 10, 12, 30),
      );

      final json = original.toJson();
      final restored = Subject.fromJson(json);

      expect(restored.code, original.code);
      expect(restored.name, original.name);
      expect(restored.addedAt, original.addedAt);
    });

    test('toJson uses ISO8601 for the addedAt timestamp', () {
      final s = Subject(
        code: 'IT305',
        name: 'Web Development',
        addedAt: DateTime.utc(2026, 5, 10, 12, 30),
      );

      expect(s.toJson()['addedAt'], '2026-05-10T12:30:00.000Z');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/instructor/models/subject_test.dart`
Expected: FAIL with "Target of URI doesn't exist: 'package:ievaluateapp_final/instructor/models/subject.dart'."

- [ ] **Step 3: Write the model**

Create `lib/instructor/models/subject.dart`:

```dart
class Subject {
  final String code;
  final String name;
  final DateTime addedAt;

  const Subject({
    required this.code,
    required this.name,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'addedAt': addedAt.toUtc().toIso8601String(),
      };

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        code: json['code'] as String,
        name: json['name'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/instructor/models/subject_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/instructor/models/subject.dart test/instructor/models/subject_test.dart
git commit -m "feat(instructor): add Subject model with JSON serialization"
```

---

## Task 3: SubjectsProvider + tests

**Files:**
- Create: `lib/instructor/providers/subjects_provider.dart`
- Create: `test/instructor/providers/subjects_provider_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/instructor/providers/subjects_provider_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/models/subject.dart';
import 'package:ievaluateapp_final/instructor/providers/subjects_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SubjectsProvider', () {
    test('starts empty when SharedPreferences has no entry', () async {
      final provider = SubjectsProvider();
      await provider.load();
      expect(provider.subjects, isEmpty);
    });

    test('hydrates persisted subjects on load', () async {
      final stored = jsonEncode([
        {
          'code': 'CS101',
          'name': 'Intro to Programming',
          'addedAt': '2026-05-01T00:00:00.000Z',
        },
      ]);
      SharedPreferences.setMockInitialValues({
        'instructor_subjects_v1': stored,
      });

      final provider = SubjectsProvider();
      await provider.load();

      expect(provider.subjects.length, 1);
      expect(provider.subjects.first.code, 'CS101');
    });

    test('add appends, persists, and notifies listeners', () async {
      final provider = SubjectsProvider();
      await provider.load();

      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.add(
        Subject(
          code: 'IT305',
          name: 'Web Development',
          addedAt: DateTime.utc(2026, 5, 10),
        ),
      );

      expect(provider.subjects.length, 1);
      expect(provider.subjects.first.code, 'IT305');
      expect(notifications, 1);

      // Re-hydrate a fresh provider to confirm persistence.
      final reloaded = SubjectsProvider();
      await reloaded.load();
      expect(reloaded.subjects.length, 1);
      expect(reloaded.subjects.first.code, 'IT305');
    });

    test('exists is case-insensitive', () async {
      final provider = SubjectsProvider();
      await provider.load();
      await provider.add(
        Subject(
          code: 'CS101',
          name: 'Intro',
          addedAt: DateTime.utc(2026, 5, 10),
        ),
      );

      expect(provider.exists('cs101'), isTrue);
      expect(provider.exists('CS101'), isTrue);
      expect(provider.exists('cs999'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/instructor/providers/subjects_provider_test.dart`
Expected: FAIL with "Target of URI doesn't exist: 'package:ievaluateapp_final/instructor/providers/subjects_provider.dart'."

- [ ] **Step 3: Write the provider**

Create `lib/instructor/providers/subjects_provider.dart`:

```dart
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/instructor/providers/subjects_provider_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/instructor/providers/subjects_provider.dart test/instructor/providers/subjects_provider_test.dart
git commit -m "feat(instructor): SubjectsProvider with SharedPreferences persistence"
```

---

## Task 4: Theme tokens

**Files:**
- Create: `lib/theme/app_colors.dart`

Note: keep the existing `lib/app_colors.dart` in place during the migration so screens that still import the old path continue to compile. The old file is deleted in Task 16.

- [ ] **Step 1: Write the new color tokens**

Create `lib/theme/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// iEvaluate brand palette: Vanilla Custard / Vivid Orange / Midnight Espresso.
///
/// Colours are exposed as semantic tokens, not raw names, so theming and
/// repaletting can happen without touching the rest of the app.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFFF77331); // Vivid Orange
  static const Color primaryDeep = Color(0xFFD85A1A);
  static const Color primaryTint = Color(0xFFFFE4D2);

  // Surfaces
  static const Color background = Color(0xFFFFF9EB); // Vanilla Custard
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFEF8);

  // Text
  static const Color textPrimary = Color(0xFF200F07); // Midnight Espresso
  static Color get textSecondary => textPrimary.withOpacity(0.60);
  static Color get textTertiary => textPrimary.withOpacity(0.40);
  static const Color textInverted = Color(0xFFFFF9EB);

  // Borders / dividers
  static Color get borderHairline => textPrimary.withOpacity(0.08);
  static Color get borderSubtle => textPrimary.withOpacity(0.12);

  // Status (warm-paired so they sit next to the orange without clashing)
  static const Color success = Color(0xFF2E7D5A);
  static const Color warning = Color(0xFFC97419);
  static const Color error = Color(0xFFC2410C);

  // Convenience for hero gradients
  static List<Color> get heroGradient => [
        textPrimary,
        textPrimary.withOpacity(0.85),
      ];
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/app_colors.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_colors.dart
git commit -m "feat(theme): add Vanilla/Vivid/Espresso colour tokens"
```

---

## Task 5: Typography scale

**Files:**
- Create: `lib/theme/app_text_styles.dart`

- [ ] **Step 1: Write the typography scale**

Create `lib/theme/app_text_styles.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Inter / Inter Tight typography scale tuned to feel iOS-premium.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get displayLarge => GoogleFonts.interTight(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        color: AppColors.textPrimary,
        height: 1.1,
      );

  static TextStyle get displayMedium => GoogleFonts.interTight(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: AppColors.textPrimary,
        height: 1.15,
      );

  static TextStyle get displaySmall => GoogleFonts.interTight(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle get titleLarge => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
        height: 1.25,
      );

  static TextStyle get titleMedium => GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get titleSmall => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.35,
      );

  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.45,
      );

  static TextStyle get bodySmall => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.45,
      );

  static TextStyle get labelLarge => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get labelMedium => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  /// Small uppercase metadata, iOS-style ALL-CAPS captions.
  static TextStyle get labelSmall => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: AppColors.textSecondary,
      );
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/app_text_styles.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_text_styles.dart
git commit -m "feat(theme): add Inter/Inter Tight typography scale"
```

---

## Task 6: ThemeData

**Files:**
- Create: `lib/theme/app_theme.dart`

- [ ] **Step 1: Write the ThemeData**

Create `lib/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Builds the light ThemeData for iEvaluate. Dark mode is intentionally not
/// implemented in this iteration.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.textInverted,
      secondary: AppColors.primaryDeep,
      onSecondary: AppColors.textInverted,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: AppColors.textInverted,
    );

    final textTheme = TextTheme(
      displayLarge: AppTextStyles.displayLarge,
      displayMedium: AppTextStyles.displayMedium,
      displaySmall: AppTextStyles.displaySmall,
      headlineMedium: AppTextStyles.displaySmall,
      headlineSmall: AppTextStyles.titleLarge,
      titleLarge: AppTextStyles.titleLarge,
      titleMedium: AppTextStyles.titleMedium,
      titleSmall: AppTextStyles.titleSmall,
      bodyLarge: AppTextStyles.bodyLarge,
      bodyMedium: AppTextStyles.bodyMedium,
      bodySmall: AppTextStyles.bodySmall,
      labelLarge: AppTextStyles.labelLarge,
      labelMedium: AppTextStyles.labelMedium,
      labelSmall: AppTextStyles.labelSmall,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.titleLarge,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        shape: Border(
          bottom: BorderSide(color: AppColors.borderHairline, width: 1),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.borderHairline, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.borderHairline,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textInverted,
          disabledBackgroundColor: AppColors.borderSubtle,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          side: BorderSide(color: AppColors.borderSubtle, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTextStyles.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textTertiary,
        ),
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        helperStyle: AppTextStyles.bodySmall,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderHairline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderHairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.surface
              : AppColors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.borderSubtle,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textInverted,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: AppTextStyles.titleLarge,
        contentTextStyle: AppTextStyles.bodyMedium,
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/theme/app_theme.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/theme/app_theme.dart
git commit -m "feat(theme): add AppTheme.light wiring tokens into ThemeData"
```

---

## Task 7: Wire AppTheme + MultiProvider into main.dart

**Files:**
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Replace `lib/main.dart` with the wired-up version**

Overwrite `lib/main.dart` with:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'instructor/providers/subjects_provider.dart';
import 'login_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final subjectsProvider = SubjectsProvider();
  await subjectsProvider.load();

  runApp(MyApp(subjectsProvider: subjectsProvider));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.subjectsProvider});

  final SubjectsProvider subjectsProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SubjectsProvider>.value(
          value: subjectsProvider,
        ),
      ],
      child: MaterialApp(
        title: 'iEvaluate',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const LoginScreen(),
      ),
    );
  }
}
```

- [ ] **Step 2: Replace the broken default widget test**

Overwrite `test/widget_test.dart` with a smoke test that matches the real app:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/providers/subjects_provider.dart';
import 'package:ievaluateapp_final/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App launches and renders the login portal title',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = SubjectsProvider();
    await provider.load();

    await tester.pumpWidget(MyApp(subjectsProvider: provider));
    await tester.pumpAndSettle();

    expect(find.text('iEvaluate Portal'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run all tests**

Run: `flutter test`
Expected: PASS for all tests so far (Subject, SubjectsProvider, smoke test).

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!` for new files. Existing role files may still produce no errors because they import the old `lib/app_colors.dart` which still exists.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart test/widget_test.dart
git commit -m "feat: wire AppTheme.light and SubjectsProvider via MultiProvider"
```

---

## Task 8: Repalette common screens (login, signup, agreement)

**Files:**
- Modify: `lib/login_screen.dart`
- Modify: `lib/signup_screen.dart`
- Modify: `lib/agreement_screen.dart`

For each file: change the import from `'app_colors.dart'` to `'theme/app_colors.dart'` and replace token references using the mapping table at the top of this plan.

- [ ] **Step 1: Update `lib/login_screen.dart`**

Change line 3:

```dart
import 'app_colors.dart';
```

to:

```dart
import 'theme/app_colors.dart';
```

Replace token references in this file:
- `AppColors.white` → `AppColors.surface` (background, avatar circle background, logo circle)
- `AppColors.deepBlue` → `AppColors.textPrimary` (AppBar background, page title, footer text accents)
- `AppColors.gold` → `AppColors.primary` (Sign In button background)
- `AppColors.royalBlue` → `AppColors.primary` (Forgot Password / Register Here / focused border)
- `Colors.grey.shade400` → `AppColors.textTertiary` (input hint and trailing eye icon)
- `Colors.grey.shade600` → `AppColors.textSecondary` (subtitle, "Need an account?")
- `Colors.grey.shade50` → `AppColors.surface` (input fill)
- `Colors.grey.shade200` → `AppColors.borderHairline` (input border)
- The Sign In button's `foregroundColor: AppColors.deepBlue` → `AppColors.textInverted`

After the changes the AppBar will be light (Vanilla Custard) instead of deep blue, with Espresso text and an orange CTA. That's the iOS-premium look.

- [ ] **Step 2: Update `lib/signup_screen.dart`**

Change the import line 3 from `'app_colors.dart'` to `'theme/app_colors.dart'`.

Apply token replacements throughout the file:
- `AppColors.white` → `AppColors.surface`
- `AppColors.deepBlue` → `AppColors.textPrimary`
- `AppColors.gold` → `AppColors.primary`
- `AppColors.royalBlue` → `AppColors.primary`
- `AppColors.darkGray` → `AppColors.textPrimary`
- `Colors.grey.shade300` → `AppColors.borderHairline`
- `Colors.grey.shade50` → `AppColors.surface`
- `Colors.grey.shade200` → `AppColors.borderHairline`
- The progress bar inactive segment `Colors.grey.shade300` → `AppColors.borderSubtle`
- `Colors.green` (requirement met) → `AppColors.success`
- `Colors.grey` (requirement not met) → `AppColors.textTertiary`
- `Colors.redAccent` (validation errors) → `AppColors.error`
- The "Continue" button `foregroundColor: AppColors.deepBlue` → `AppColors.textInverted`
- The dialog buttons inherit ThemeData; ensure no inline `backgroundColor` overrides remain.

- [ ] **Step 3: Update `lib/agreement_screen.dart`**

Change the import from `'app_colors.dart'` to `'theme/app_colors.dart'`.

Apply token replacements:
- `AppColors.white` → `AppColors.surface`
- `AppColors.deepBlue` → `AppColors.textPrimary`
- `AppColors.gold` → `AppColors.primary`
- The "Accept" button's `foregroundColor: AppColors.deepBlue` → `AppColors.textInverted`

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/login_screen.dart lib/signup_screen.dart lib/agreement_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Run tests**

Run: `flutter test`
Expected: PASS for all tests.

- [ ] **Step 6: Smoke run (manual)**

Run: `flutter run` (on a connected device or emulator).
Verify: Login screen background is Vanilla Custard, AppBar reads "iEvaluate" in Espresso, Sign In button is Vivid Orange. Tap "Register Here" → registration screen wizard works through 4 steps with new theme. Cancel back to login.

If `flutter run` is not available in this environment, run `flutter analyze && flutter test` instead and skip the visual check until the next manual session.

- [ ] **Step 7: Commit**

```bash
git add lib/login_screen.dart lib/signup_screen.dart lib/agreement_screen.dart
git commit -m "refactor(ui): repalette login, signup, and agreement screens"
```

---

## Task 9: Repalette SAO Admin role

**Files:**
- Modify: `lib/sao_admin/admin_dashboard.dart`
- Modify: `lib/sao_admin/user_management_screen.dart`
- Modify: `lib/sao_admin/personnel_management_screen.dart`
- Modify: `lib/sao_admin/performance_analysis_screen.dart`
- Modify: `lib/sao_admin/live_system_metrics_screen.dart`
- Modify: `lib/sao_admin/system_audit_screen.dart`
- Modify: `lib/sao_admin/sao_admin_settings.dart`

- [ ] **Step 1: Update imports in all 7 files**

In each of the 7 files above, change the import from `'../app_colors.dart'` to `'../theme/app_colors.dart'`.

- [ ] **Step 2: Apply token replacements in each file using the mapping table**

For each file, do the following replacements (most are search-and-replace, none change behavior):

| Find | Replace |
|---|---|
| `AppColors.deepBlue` | `AppColors.textPrimary` |
| `AppColors.royalBlue` | `AppColors.primary` |
| `AppColors.gold` | `AppColors.primary` |
| `AppColors.lightGold` | `AppColors.primaryTint` |
| `AppColors.white` | `AppColors.surface` |
| `AppColors.lightGray` | `AppColors.background` |
| `AppColors.darkGray` | `AppColors.textPrimary` |
| `Colors.grey.shade300` | `AppColors.borderHairline` |
| `Colors.grey.shade200` | `AppColors.borderHairline` |
| `Colors.grey.shade400` | `AppColors.textTertiary` |
| `Colors.grey.shade500` | `AppColors.textTertiary` |
| `Colors.grey.shade600` | `AppColors.textSecondary` |
| `Colors.grey.shade100` | `AppColors.background` |
| `Colors.grey.shade50` | `AppColors.surface` |
| `Colors.grey` (when used as a color value) | `AppColors.textSecondary` |
| `Colors.red` / `Colors.redAccent` (status) | `AppColors.error` |
| `Colors.green` / `Colors.greenAccent` (status) | `AppColors.success` |
| `Colors.orange` / `Colors.orangeAccent` (status) | `AppColors.warning` |
| `Colors.black.withOpacity(0.05)` (shadow) | `AppColors.textPrimary.withOpacity(0.05)` |

For hero gradient blocks of the form:
```dart
gradient: const LinearGradient(colors: [AppColors.deepBlue, AppColors.royalBlue]),
```
Replace with:
```dart
gradient: LinearGradient(colors: AppColors.heroGradient),
```
(Drop the `const` because `heroGradient` is computed.)

For the avatar in the drawer header (was a gold-circle on deep-blue background):
- Background of `DrawerHeader` becomes `AppColors.textPrimary`
- The circle avatar's child icon stays `AppColors.primary` (orange) — this is the orange-on-espresso look

For inline `Color(0xFF...)` literals (rare; in `performance_analysis_screen.dart` the department averages list uses `AppColors.royalBlue`, `AppColors.gold`, `Colors.green`, `Colors.orange`, `Colors.purple`):
- Replace with: `AppColors.primary`, `AppColors.primaryDeep`, `AppColors.success`, `AppColors.warning`, `AppColors.textSecondary` respectively.

- [ ] **Step 3: Run analyzer for the role**

Run: `flutter analyze lib/sao_admin/`
Expected: `No issues found!`

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: PASS for all tests.

- [ ] **Step 5: Commit**

```bash
git add lib/sao_admin/
git commit -m "refactor(ui): apply new theme to SAO Admin screens"
```

---

## Task 10: Repalette Department Head role

**Files:**
- Modify: `lib/dept_head/department_dashboard_screen.dart`
- Modify: `lib/dept_head/faculty_roster_screen.dart`
- Modify: `lib/dept_head/subject_analytics_screen.dart`
- Modify: `lib/dept_head/intervention_reports_screen.dart`
- Modify: `lib/dept_head/dept_head_settings_screen.dart`

- [ ] **Step 1: Update imports in all 5 files**

Change `'../app_colors.dart'` → `'../theme/app_colors.dart'` in each file.

- [ ] **Step 2: Apply token replacements per the mapping table from Task 9 Step 2**

Notable file-specific touches:
- `department_dashboard_screen.dart` has a `_deptWordCloud` list with hardcoded `Colors.green`, `Colors.orange`, `Colors.redAccent`, `AppColors.royalBlue`, `AppColors.deepBlue`. Map to `AppColors.success`, `AppColors.warning`, `AppColors.error`, `AppColors.primary`, `AppColors.textPrimary`.
- `_actionAlerts` colors `Colors.red` / `Colors.orange` → `AppColors.error` / `AppColors.warning`.
- The hero card gradient (`[deepBlue, royalBlue]`) → `AppColors.heroGradient`.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/dept_head/`
Expected: `No issues found!`

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/dept_head/
git commit -m "refactor(ui): apply new theme to Department Head screens"
```

---

## Task 11: Repalette Gatherer role

**Files:**
- Modify: `lib/gatherer/data_gatherer_screen.dart`
- Modify: `lib/gatherer/data_validation_screen.dart`
- Modify: `lib/gatherer/gatherer_dashboard_view.dart`
- Modify: `lib/gatherer/gatherer_drawer.dart`
- Modify: `lib/gatherer/gatherer_scanner_view.dart`
- Modify: `lib/gatherer/gatherer_sync_view.dart`
- Modify: `lib/gatherer/gatherer_settings_view.dart`

- [ ] **Step 1: Update imports in all 7 files**

Change `'../app_colors.dart'` → `'../theme/app_colors.dart'`.

- [ ] **Step 2: Apply token replacements per the mapping table from Task 9 Step 2**

Specific cases to watch:
- `gatherer_scanner_view.dart` overlay: the `Colors.black.withOpacity(0.7)` mask should stay as `Colors.black.withOpacity(0.7)` — the camera preview must remain dim regardless of theme. The corner-bracket `AppColors.gold` borders → `AppColors.primary`. The animated laser `AppColors.gold` → `AppColors.primary`.
- The bottom-sheet "Send Form Link" modal (lines ~93-287): change `Colors.black.withOpacity(0.85)` background to keep dark glass — leave it as-is since this is intentional camera-overlay glass. Just update `AppColors.gold` → `AppColors.primary` and helper text colors.
- `gatherer_dashboard_view.dart`: the "ENTRIES TODAY" / "PENDING SYNCS" cards use `AppColors.royalBlue` and `Colors.orange` — map to `AppColors.primary` and `AppColors.warning`.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/gatherer/`
Expected: `No issues found!`

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/gatherer/
git commit -m "refactor(ui): apply new theme to Gatherer screens"
```

---

## Task 12: Repalette non-dashboard Instructor screens

**Files:**
- Modify: `lib/instructor/past_semesters_screen.dart`
- Modify: `lib/instructor/student_feedback_screen.dart`
- Modify: `lib/instructor/instructor_settings_screen.dart`

(The dashboard is updated in Task 13 because that change involves provider wiring and structural edits.)

- [ ] **Step 1: Update imports in all 3 files**

Change `'../app_colors.dart'` → `'../theme/app_colors.dart'`.

- [ ] **Step 2: Apply token replacements per the mapping table from Task 9 Step 2**

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/instructor/past_semesters_screen.dart lib/instructor/student_feedback_screen.dart lib/instructor/instructor_settings_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/instructor/past_semesters_screen.dart lib/instructor/student_feedback_screen.dart lib/instructor/instructor_settings_screen.dart
git commit -m "refactor(ui): apply new theme to Instructor secondary screens"
```

---

## Task 13: Wire Instructor dashboard to SubjectsProvider + add drawer entry

**Files:**
- Modify: `lib/instructor/instructor_dashboard.dart`

- [ ] **Step 1: Update imports**

Replace these lines at the top of the file:
```dart
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../login_screen.dart';
import 'past_semesters_screen.dart';
import 'student_feedback_screen.dart';
import 'instructor_settings_screen.dart';
//import 'ai_sentiment_analysis.dark';
```

with:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../login_screen.dart';
import '../theme/app_colors.dart';
import 'instructor_settings_screen.dart';
import 'models/subject.dart';
import 'my_subjects_screen.dart';
import 'past_semesters_screen.dart';
import 'providers/subjects_provider.dart';
import 'student_feedback_screen.dart';
```

(`my_subjects_screen.dart` is created in Task 14; the import is forward-looking. A second commit chain in Task 14 will land that file. To keep this task self-contained, we add the import here and the file in Task 14 — `flutter analyze` will warn at the end of this task and clear once Task 14 lands. To avoid that, run Task 13 and Task 14 back-to-back without `flutter analyze` between them, then analyze once at the end of Task 14.)

- [ ] **Step 2: Remove the hardcoded `_mySubjects` list**

Delete this block (lines 38-42 originally):

```dart
final List<Map<String, dynamic>> _mySubjects = [
  {'code': 'CS101', 'name': 'Intro to Programming', 'score': 4.90, 'students': 45},
  {'code': 'CS202', 'name': 'Data Structures & Algorithms', 'score': 4.80, 'students': 38},
  {'code': 'IT305', 'name': 'Web Development', 'score': 4.85, 'students': 59},
];
```

- [ ] **Step 3: Replace the "Current Classes" section in the build method**

Find this section (around lines 251-293):

```dart
const Text('Current Classes', style: TextStyle(color: AppColors.deepBlue, fontSize: 18, fontWeight: FontWeight.bold)),
const SizedBox(height: 12),
Column(
  children: _mySubjects.map((subject) {
    return Card(
      // ... full subject card
    );
  }).toList(),
),
```

Replace with:

```dart
const Text(
  'Current Classes',
  style: TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.bold,
  ),
),
const SizedBox(height: 12),
Consumer<SubjectsProvider>(
  builder: (context, provider, _) {
    final subjects = provider.subjects;
    if (subjects.isEmpty) {
      return _buildEmptySubjectsCard(context);
    }
    return Column(
      children: subjects
          .map((subject) => _buildSubjectCard(subject))
          .toList(),
    );
  },
),
```

- [ ] **Step 4: Add the empty-state and subject-card helper methods to `_InstructorDashboardScreenState`**

Add these methods inside `_InstructorDashboardScreenState`:

```dart
Widget _buildEmptySubjectsCard(BuildContext context) {
  return InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MySubjectsScreen()),
    ),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderHairline, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.menu_book_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No subjects yet',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Add your subjects to see them here.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    ),
  );
}

Widget _buildSubjectCard(Subject subject) {
  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.class_, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.code,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  subject.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 5: Add the drawer entry for `My Subjects`**

In the drawer build, find the existing entries:

```dart
_buildDrawerItem(context, Icons.dashboard, 'Dashboard', true),
_buildDrawerItem(context, Icons.history, 'Past Semesters', false, onTap: () {
  Navigator.pop(context);
  Navigator.push(context, MaterialPageRoute(builder: (context) => const PastSemestersScreen()));
}),
_buildDrawerItem(context, Icons.forum, 'Student Feedback', false, onTap: () {
```

Insert a new item between `Past Semesters` and `Student Feedback`:

```dart
_buildDrawerItem(context, Icons.menu_book_rounded, 'My Subjects', false, onTap: () {
  Navigator.pop(context);
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const MySubjectsScreen()),
  );
}),
```

- [ ] **Step 6: Apply remaining token replacements**

Apply the mapping table from Task 9 Step 2 to the rest of `instructor_dashboard.dart`. Notable spots:
- Welcome card gradient `[deepBlue, royalBlue]` → `AppColors.heroGradient`
- All `AppColors.deepBlue` text references → `AppColors.textPrimary`
- All `AppColors.royalBlue` references → `AppColors.primary`
- `AppColors.gold` (overall rating number, format quote) → `AppColors.primary`
- The notice banner red colors stay status-red but route through `AppColors.error`
- `Colors.greenAccent` (trend up) → `AppColors.success`
- `Colors.orangeAccent` (trend flat) → `AppColors.warning`

- [ ] **Step 7: Do not run analyzer or commit yet — Task 14 finishes the screen wiring**

This task is intentionally not committed yet because it depends on `MySubjectsScreen` (Task 14). Proceed directly to Task 14.

---

## Task 14: MySubjectsScreen

**Files:**
- Create: `lib/instructor/my_subjects_screen.dart`

- [ ] **Step 1: Write the screen**

Create `lib/instructor/my_subjects_screen.dart`:

```dart
// lib/instructor/my_subjects_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import 'add_subject_screen.dart';
import 'models/subject.dart';
import 'providers/subjects_provider.dart';

class MySubjectsScreen extends StatelessWidget {
  const MySubjectsScreen({super.key});

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatAddedAt(DateTime when) {
    final local = when.toLocal();
    return 'Added ${_monthNames[local.month - 1]} ${local.day}';
  }

  void _openAddSubject(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddSubjectScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Subjects'),
        actions: [
          IconButton(
            tooltip: 'Add Subject',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _openAddSubject(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<SubjectsProvider>(
          builder: (context, provider, _) {
            final subjects = provider.subjects;
            if (subjects.isEmpty) {
              return _buildEmpty(context);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: subjects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _buildRow(subjects[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No subjects yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add your first subject.',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openAddSubject(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Subject'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(Subject subject) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  subject.code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatAddedAt(subject.addedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Continue to Task 15 before analyzing**

Don't analyze or commit yet — `add_subject_screen.dart` is referenced and lands in Task 15.

---

## Task 15: AddSubjectScreen + tests

**Files:**
- Create: `lib/instructor/add_subject_screen.dart`
- Create: `test/instructor/add_subject_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/instructor/add_subject_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/instructor/add_subject_screen.dart';
import 'package:ievaluateapp_final/instructor/providers/subjects_provider.dart';
import 'package:ievaluateapp_final/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpScreen(WidgetTester tester, SubjectsProvider provider) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SubjectsProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const AddSubjectScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Save button is disabled until both fields are filled',
      (WidgetTester tester) async {
    final provider = SubjectsProvider();
    await provider.load();
    await _pumpScreen(tester, provider);

    final saveFinder = find.widgetWithText(TextButton, 'Save');
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('codeField')), 'cs101');
    await tester.pump();
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('nameField')),
      'Intro to Programming',
    );
    await tester.pump();

    expect(tester.widget<TextButton>(saveFinder).onPressed, isNotNull);
  });

  testWidgets('Code field auto-uppercases input',
      (WidgetTester tester) async {
    final provider = SubjectsProvider();
    await provider.load();
    await _pumpScreen(tester, provider);

    await tester.enterText(find.byKey(const ValueKey('codeField')), 'cs101');
    await tester.pump();

    final field = tester.widget<TextField>(find.byKey(const ValueKey('codeField')));
    expect(field.controller!.text, 'CS101');
  });

  testWidgets('Save persists to provider and pops the route',
      (WidgetTester tester) async {
    final provider = SubjectsProvider();
    await provider.load();
    await _pumpScreen(tester, provider);

    await tester.enterText(find.byKey(const ValueKey('codeField')), 'IT305');
    await tester.enterText(
      find.byKey(const ValueKey('nameField')),
      'Web Development',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(provider.subjects.length, 1);
    expect(provider.subjects.first.code, 'IT305');
    expect(provider.subjects.first.name, 'Web Development');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/instructor/add_subject_screen_test.dart`
Expected: FAIL — "Target of URI doesn't exist".

- [ ] **Step 3: Write the screen**

Create `lib/instructor/add_subject_screen.dart`:

```dart
// lib/instructor/add_subject_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import 'models/subject.dart';
import 'providers/subjects_provider.dart';

class AddSubjectScreen extends StatefulWidget {
  const AddSubjectScreen({super.key});

  @override
  State<AddSubjectScreen> createState() => _AddSubjectScreenState();
}

class _AddSubjectScreenState extends State<AddSubjectScreen> {
  static final _recommendedCodePattern = RegExp(r'^[A-Z]{2,5}\d{2,4}$');

  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onChange);
    _nameController.addListener(_onChange);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});

  bool get _isFormValid =>
      _codeController.text.trim().isNotEmpty &&
      _nameController.text.trim().isNotEmpty;

  Future<void> _save() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final provider = context.read<SubjectsProvider>();

    if (provider.exists(code)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Already in your list'),
          content: Text('"$code" is already in your subjects. Save anyway?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await provider.add(
      Subject(
        code: code,
        name: name,
        addedAt: DateTime.now(),
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Subject added')),
    );
  }

  String? get _codeHelperText {
    final code = _codeController.text.trim();
    if (code.isEmpty) return null;
    if (!_recommendedCodePattern.hasMatch(code)) {
      return 'Heads up: codes usually look like CS101 or IT305.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 88,
        title: const Text('Add Subject'),
        actions: [
          TextButton(
            onPressed: _isFormValid ? _save : null,
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('codeField'),
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(8),
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    return newValue.copyWith(text: newValue.text.toUpperCase());
                  }),
                ],
                decoration: InputDecoration(
                  labelText: 'Subject Code',
                  hintText: 'e.g. CS101',
                  helperText: _codeHelperText,
                  helperStyle: TextStyle(color: AppColors.warning),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('nameField'),
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(60),
                ],
                decoration: const InputDecoration(
                  labelText: 'Subject Name',
                  hintText: 'e.g. Intro to Programming',
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Subject codes auto-capitalize. You can edit and delete subjects in a later update.',
                        style: TextStyle(
                          color: AppColors.textPrimary.withOpacity(0.8),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/instructor/add_subject_screen_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Run all tests**

Run: `flutter test`
Expected: PASS for all tests (Subject, SubjectsProvider, AddSubjectScreen, smoke).

- [ ] **Step 6: Run analyzer across the whole project**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit Tasks 13 + 14 + 15 together**

```bash
git add lib/instructor/instructor_dashboard.dart lib/instructor/my_subjects_screen.dart lib/instructor/add_subject_screen.dart test/instructor/add_subject_screen_test.dart
git commit -m "feat(instructor): MySubjectsScreen + AddSubjectScreen + dashboard wiring"
```

---

## Task 16: Retire the legacy `lib/app_colors.dart`

**Files:**
- Delete: `lib/app_colors.dart`

- [ ] **Step 1: Confirm nothing imports the old path**

Run: `git grep -n "import 'app_colors.dart'" lib/ ; git grep -n "import '../app_colors.dart'" lib/`
Expected: no results.

If anything is left (a missed file from Tasks 8-13), update it to `'../theme/app_colors.dart'` (or `'theme/app_colors.dart'` if it's at the lib root) and apply the token mapping table from Task 9 Step 2.

- [ ] **Step 2: Delete the file**

Run: `git rm lib/app_colors.dart`

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Run all tests**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "chore: retire legacy lib/app_colors.dart in favor of lib/theme/app_colors.dart"
```

---

## Task 17: End-to-end verification

**Files:** none

- [ ] **Step 1: Run analyzer on the whole project**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: PASS for all 4 test files (Subject, SubjectsProvider, AddSubjectScreen, smoke).

- [ ] **Step 3: Manual smoke verification (if a device/emulator is available)**

Run: `flutter run`

Walk through each acceptance criterion from the spec §8:

1. Cold start renders Vanilla Custard background, Espresso text, orange CTA on login.
2. Sign in with `instructor` → dashboard shows new theme; `Current Classes` shows the empty-state card.
3. Open drawer → `My Subjects` entry between Past Semesters and Student Feedback → tap → empty state.
4. Tap `+` in `My Subjects` AppBar → `Add Subject` opens. Save is disabled.
5. Type `cs101` → auto-uppercases. Type `Intro to Programming`. Save activates. Tap → returns to list with one entry.
6. Tap `+` again, enter `CS101` again, tap Save → duplicate dialog appears. Confirm cancels return.
7. Force-close the app, relaunch, sign in as instructor → `My Subjects` retains entries.
8. Dashboard `Current Classes` reflects saved subjects. No score / student-count.
9. Sign out, log in as `sao`, `staff`, `dean` in turn — confirm each role's dashboard renders with the new theme and no leftover blue/gold.
10. Final `flutter analyze` is clean.

- [ ] **Step 4: Final commit if any tweaks were needed**

If Step 3 surfaced minor visual tweaks, fix them, run analyzer + tests, and commit:

```bash
git add lib/
git commit -m "refactor(ui): tweaks from end-to-end verification pass"
```

If everything is already clean, no commit is needed for this task.

- [ ] **Step 5: Branch is ready for review**

Tell Michael: "Branch `redesign/ios-premium-and-add-subject` is ready for your review."

Do NOT push, do NOT merge. Local-only until Michael says otherwise.

---

## Out of scope (deferred backlog)

These are intentionally not implemented in this plan:

- Edit and delete subjects in the Instructor module
- Section / semester / year fields per subject
- Real authentication; login routing remains keyword-matched
- Supabase / n8n / OMR / OCR / Gemini integration
- Dark mode
- Cupertino-style navigation transitions
- Haptic feedback wiring on the gatherer settings toggle
- Push notifications for the dean's "Mandated Action" notice
- A real CTU watermark or logo update

Each is a follow-up plan after this branch is merged.
