# iOS-Premium Redesign + Instructor Add Subject

**Date:** 2026-05-10
**Author:** Michael Gonzaga (Team ERMM)
**Status:** Approved for implementation
**Branch:** `redesign/ios-premium-and-add-subject` (to be created)

---

## 1. Context

The iEvaluate Flutter app currently uses a SAO-themed deep-blue / royal-blue / gold palette with default Roboto typography. Team feedback to Michael (Gonzaga) requests two things:

1. A new screen in the **Instructor** role for an instructor to add the subjects they teach. Inputs: **Subject Code**, **Subject Name**.
2. A repalette + retypography across the whole app to feel like a "premium iOS quality" product, using the colors Vanilla Custard `#FFF9EB`, Vivid Orange `#F77331`, and Midnight Espresso `#200F07`.

The change is to ship on a separate branch for review before merging to `main`.

## 2. Goals

- Replace the existing color palette with the Vanilla / Vivid / Espresso system across all four roles (SAO-Admin, Gatherer, Department Head, Instructor).
- Introduce an Inter / Inter Tight typography scale that reads as iOS-premium without depending on Apple-licensed fonts.
- Add a `My Subjects` drawer entry to the Instructor role with a list view + an `Add Subject` form.
- Persist the subjects list across app restarts via `SharedPreferences`.
- Make the Instructor dashboard's `Current Classes` section a live read of saved subjects.
- Keep all changes on `redesign/ios-premium-and-add-subject` until Michael reviews.

## 3. Non-goals

- Dark mode. The existing unused `theme_provider.dart` stays unused.
- Cupertino-style navigation transitions or pure Cupertino widgets.
- Edit/delete on subjects. Add-only for this iteration.
- Real authentication. Login routing stays keyword-matched.
- Supabase, n8n webhook calls, OMR/OCR, Gemini integration. Out of scope.
- Haptic feedback wiring (the gatherer settings toggle continues to be a no-op).
- Score/student-count fields on subjects. Those are evaluation-derived, not subject metadata.

## 4. Visual system

### 4.1 Color tokens (`lib/theme/app_colors.dart`)

| Token | Value | Use |
|---|---|---|
| `primary` | `#F77331` Vivid Orange | CTAs, active states, links, FABs, focus rings, accent text |
| `primaryDeep` | `#D85A1A` | Pressed state of primary |
| `primaryTint` | `#FFE4D2` | Soft orange wash for selected backgrounds, badges |
| `background` | `#FFF9EB` Vanilla Custard | App scaffold background |
| `surface` | `#FFFFFF` | Cards, sheets, inputs |
| `surfaceElevated` | `#FFFEF8` | Subtle warm white for layered surfaces |
| `textPrimary` | `#200F07` Espresso | Headings + body |
| `textSecondary` | Espresso @ 60% opacity | Subtitles, helper text |
| `textTertiary` | Espresso @ 40% opacity | Captions, disabled |
| `textInverted` | `#FFF9EB` | Text on dark surfaces (Espresso bg) |
| `borderHairline` | Espresso @ 8% opacity | Dividers, input borders |
| `borderSubtle` | Espresso @ 12% opacity | Card outlines, separators |
| `success` | `#2E7D5A` | Positive status (green-warm) |
| `warning` | `#C97419` | Warning status (deeper orange) |
| `error` | `#C2410C` | Error status (warm red-orange) |

### 4.2 Hero treatment

The current `[deepBlue, royalBlue]` linear gradient on dashboard hero cards is replaced with `[Espresso, Espresso @ 85% opacity]`. Within those hero cards, accent values (large numbers, badges) render in **Vivid Orange** instead of Gold. Vanilla Custard is reserved for the app background; it never appears as a card surface.

### 4.3 Typography (`lib/theme/app_text_styles.dart`)

Loaded via `google_fonts` package, family `Inter` and `Inter Tight`.

| Style | Size | Family | Weight | Tracking |
|---|---|---|---|---|
| `displayLarge` | 32 | Inter Tight | 800 | -1.0 |
| `displayMedium` | 28 | Inter Tight | 800 | -0.8 |
| `displaySmall` | 24 | Inter Tight | 700 | -0.6 |
| `titleLarge` | 20 | Inter | 700 | -0.3 |
| `titleMedium` | 17 | Inter | 600 | -0.2 |
| `titleSmall` | 15 | Inter | 600 | 0 |
| `bodyLarge` | 17 | Inter | 400 | -0.1 |
| `bodyMedium` | 15 | Inter | 400 | 0 |
| `bodySmall` | 13 | Inter | 400 | 0 |
| `labelLarge` | 15 | Inter | 600 | 0 |
| `labelMedium` | 13 | Inter | 600 | 0 |
| `labelSmall` | 11 | Inter | 700 | +0.5 (uppercase metadata) |

### 4.4 Spacing / radius / shadow

- **Spacing scale:** 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48 (px)
- **Radius scale:** 12 (inputs), 16 (cards), 20 (sheets/modals), 24 (hero cards)
- **Shadow:** soft layered, `12px blur, 8% Espresso, offset (0, 4)`. Avoid Material elevation lines.

### 4.5 ThemeData wiring (`lib/theme/app_theme.dart`)

A single `AppTheme.light` returns a `ThemeData` configured against the tokens above:

- `colorScheme` derived from `primary`, `surface`, `background`, `error`
- `textTheme` populated from the typography table, with `Inter` as the default font and `Inter Tight` overriding only the `display*` slots
- `appBarTheme`: `surface` background, `textPrimary` foreground, no elevation, hairline bottom border
- `cardTheme`: `surface`, 16 radius, soft shadow, no border by default
- `elevatedButtonTheme`: `primary` background, `textInverted` foreground, 12 radius, 56 minimum height
- `outlinedButtonTheme`: `borderSubtle` border, `textPrimary` foreground, 12 radius
- `inputDecorationTheme`: `surface` fill, `borderHairline` enabled border, `primary` focused border, 12 radius
- `dividerTheme`: `borderHairline`, 1px
- `drawerTheme`: `surface` background

`main.dart` imports `AppTheme.light` and replaces the inline `ColorScheme.fromSeed` block.

## 5. Add Subject feature

### 5.1 Data model (`lib/instructor/models/subject.dart`)

```dart
class Subject {
  final String code;
  final String name;
  final DateTime addedAt;

  const Subject({required this.code, required this.name, required this.addedAt});

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'addedAt': addedAt.toIso8601String(),
  };

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
    code: json['code'] as String,
    name: json['name'] as String,
    addedAt: DateTime.parse(json['addedAt'] as String),
  );
}
```

### 5.2 State management (`lib/instructor/providers/subjects_provider.dart`)

- `class SubjectsProvider extends ChangeNotifier`
- Persistence key: `instructor_subjects_v1`
- API:
  - `List<Subject> get subjects` — returns `UnmodifiableListView`
  - `Future<void> load()` — called once on app boot, hydrates from `SharedPreferences`
  - `Future<void> add(Subject s)` — appends, persists, `notifyListeners()`
  - `bool exists(String code)` — case-insensitive lookup, used by the form to soft-warn on duplicates
- Wired into the app via `MultiProvider` in `main.dart`. `load()` is called once at app start.

### 5.3 New screens

**`lib/instructor/my_subjects_screen.dart`**
- AppBar: "My Subjects" + trailing `+` icon button → pushes `AddSubjectScreen`
- Body listens to `SubjectsProvider`:
  - **Empty state:** centered icon, "No subjects yet", "Tap + to add your first subject", a primary button that mirrors the `+` action
  - **Populated:** list of cards, each row shows `code` (Inter Tight, large) + `name` (Inter, medium) + caption "Added {Mon DD}"

**`lib/instructor/add_subject_screen.dart`**
- AppBar: "Add Subject" + leading `Cancel` (text button) + trailing `Save` (primary button, disabled until valid)
- Body: two `TextField`s using the new theme:
  - Subject Code — auto-uppercase, 8 char max, recommended pattern `^[A-Z]{2,5}\d{2,4}$` (e.g. `CS101`, `IT305`)
  - Subject Name — 60 char max
- Validation:
  - Both fields required
  - Code that doesn't match the recommended pattern → soft warn (helper text), does **not** block
  - Duplicate code (already in the saved list) → confirmation dialog "{code} is already in your list — save anyway?", lets user proceed or cancel
- On Save: `provider.add(...)` → `Navigator.pop()` → list rebuilds → `SnackBar` "Subject added"

### 5.4 Drawer integration

In `instructor_dashboard.dart`, a new drawer entry between "Past Semesters" and "Student Feedback":

```
icon: Icons.menu_book_rounded
label: 'My Subjects'
target: MySubjectsScreen
```

### 5.5 Dashboard integration

The hardcoded `_mySubjects` list in `instructor_dashboard.dart` is removed. The `Current Classes` section reads `context.watch<SubjectsProvider>().subjects` instead.

- If `subjects.isEmpty`: a soft empty card with "Add your subjects to see them here →", tap action navigates to `MySubjectsScreen`
- If `subjects.isNotEmpty`: each row shows `code` + `name` only. The hardcoded `score` and `students` count are dropped (those are evaluation-time data, not subject metadata)

The hero welcome card, growth chart, recent feedback, and official notices banner remain — restyled by the new theme but otherwise structurally untouched.

## 6. Repalette rollout

### 6.1 Global

- New files:
  - `lib/theme/app_colors.dart` (replaces existing top-level `lib/app_colors.dart`)
  - `lib/theme/app_text_styles.dart`
  - `lib/theme/app_theme.dart`
- Existing top-level `lib/app_colors.dart` is removed; all imports are repointed to `lib/theme/app_colors.dart`. Old token names (`deepBlue`, `royalBlue`, `gold`, `lightGold`, `lightGray`, `darkGray`, `white`) are retired in favor of the semantic tokens defined in §4.1.
- `pubspec.yaml`: add `google_fonts: ^6.2.1` and `shared_preferences: ^2.3.0`
- `main.dart`: replace inline `ThemeData` with `AppTheme.light` and add `MultiProvider` wrapping the app with `SubjectsProvider`.

### 6.2 Targeted sweep

Files that reference the old palette directly and need their token references updated:

- `lib/login_screen.dart`
- `lib/signup_screen.dart`
- `lib/agreement_screen.dart`
- `lib/sao_admin/admin_dashboard.dart`
- `lib/sao_admin/user_management_screen.dart`
- `lib/sao_admin/personnel_management_screen.dart`
- `lib/sao_admin/performance_analysis_screen.dart`
- `lib/sao_admin/live_system_metrics_screen.dart`
- `lib/sao_admin/system_audit_screen.dart`
- `lib/sao_admin/sao_admin_settings.dart`
- `lib/dept_head/department_dashboard_screen.dart`
- `lib/dept_head/faculty_roster_screen.dart`
- `lib/dept_head/subject_analytics_screen.dart`
- `lib/dept_head/intervention_reports_screen.dart`
- `lib/dept_head/dept_head_settings_screen.dart`
- `lib/instructor/instructor_dashboard.dart`
- `lib/instructor/past_semesters_screen.dart`
- `lib/instructor/student_feedback_screen.dart`
- `lib/instructor/instructor_settings_screen.dart`
- `lib/gatherer/data_gatherer_screen.dart`
- `lib/gatherer/data_validation_screen.dart`
- `lib/gatherer/gatherer_dashboard_view.dart`
- `lib/gatherer/gatherer_drawer.dart`
- `lib/gatherer/gatherer_scanner_view.dart`
- `lib/gatherer/gatherer_sync_view.dart`
- `lib/gatherer/gatherer_settings_view.dart`

### 6.3 Mapping

| Old token | New token |
|---|---|
| `deepBlue` | `Espresso` (most contexts) or `surface` when used as a nav surface |
| `royalBlue` | `primary` |
| `gold` | `primary` |
| `lightGold` | `primaryTint` |
| `lightGray` | `background` |
| `darkGray` | `textPrimary` |
| `white` | `surface` |

Inline `Colors.grey.shade*` usage gets replaced with `textSecondary` / `textTertiary` / `borderHairline` to avoid the warm-vs-cool mismatch with the new palette.

Inline `Colors.red` / `Colors.green` / `Colors.orange` for status indicators get replaced with `error` / `success` / `warning` tokens to keep the warm-palette consistency.

### 6.4 Drawer headers

All four role drawers currently use a `deepBlue` header background. They migrate to a solid Espresso background with a `primaryTint`-backed avatar circle so the orange accent reads against the dark surface.

## 7. Branch and review workflow

- **Branch:** `redesign/ios-premium-and-add-subject` (off `main`)
- **Commits** (in this order, so the diff reads top-to-bottom):
  1. `chore(deps): add google_fonts and shared_preferences`
  2. `feat(theme): introduce Vanilla/Vivid/Espresso tokens, Inter typography, ThemeData`
  3. `refactor(ui): apply new theme across SAO-Admin, Dept-Head, Gatherer, Instructor`
  4. `feat(instructor): SubjectsProvider with SharedPreferences persistence`
  5. `feat(instructor): MySubjectsScreen + AddSubjectScreen, drawer + dashboard integration`
- **No push, no merge.** Local branch only until Michael says otherwise.

## 8. Verification

Manual verification against each acceptance criterion (Phase 3 of capstone testing handles real OMR/OCR; this branch only touches UI):

1. Cold start the app → background renders Vanilla Custard → login screen and AppBar reflect new theme
2. Sign in with `instructor` → instructor dashboard shows new theme, `Current Classes` shows empty state
3. Open drawer → `My Subjects` entry visible → tap navigates → empty state visible
4. Tap `+` → `Add Subject` form opens → both fields required → Save disabled until valid
5. Enter `cs101` / `Intro to Programming` → code auto-uppercases → Save enabled → tap → returns to list with new entry
6. Try saving the same `CS101` again → duplicate dialog appears → cancel works → confirm works
7. Kill the app → relaunch → sign in as instructor → `My Subjects` retains entries (SharedPreferences hydration)
8. Dashboard `Current Classes` reflects the saved subjects, no scores or student counts
9. Sign out → switch to each of SAO-Admin, Gatherer, Dept Head → confirm new theme applies (no leftover blue/gold)
10. `flutter analyze` is clean for new and touched files

## 9. Open questions resolved during brainstorming

- **Placement of Add Subject:** new drawer entry "My Subjects" with a list view (option A from brainstorming).
- **Repalette scope:** all four roles (option A).
- **iOS feel:** iOS-inspired Material — Material widgets restyled, not pure Cupertino (option B).
- **Persistence:** `SharedPreferences` (option B).
- **Edit/delete subjects:** out of scope. Add-only.
- **Score/student-count on subjects:** out of scope. Those are evaluation-derived.
- **gluestack-ui:** not portable to Flutter; used as a spec/inspiration source only.

## 10. After-this-branch backlog (for future iterations, not in this branch)

- Edit and delete subjects
- Subjects list reordering
- Section / semester / year fields per subject
- Real authentication and Supabase wiring (replaces SharedPreferences)
- Dark mode
- Edit/delete and per-instructor evaluation linking
