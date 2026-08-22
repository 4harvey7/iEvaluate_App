# ievaluateapp_final

A cross-platform Flutter application for educational evaluation and performance tracking, empowering Instructors, Data Gatherers, Department Heads, and SAO Admins with real-time analytics, automated performance alerts, and intelligent workflows.

## Table of Contents
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running Locally](#running-locally)
- [Architecture Overview](#architecture-overview)
- [Key Modules & File Locations](#key-modules--file-locations)
- [External Resources & Services](#external-resources--services)
- [Error Handling & Troubleshooting](#error-handling--troubleshooting)
- [Screens & Features](#screens--features)
- [Testing](#testing)
- [Deployment](#deployment)
- [Common Pitfalls](#common-pitfalls)
- [Support](#support)

---

## Tech Stack
| Layer | Technology | Version |
|---|---|---|
| App framework | Flutter | `^3.11.4` |
| Language | Dart | `^3.11.4` |
| Backend | Supabase | `supabase_flutter: ^2.12.4` |
| Push notifications | Firebase Cloud Messaging | `firebase_core: ^4.13.0`, `firebase_messaging: ^16.5.0` |
| Email | Supabase Auth & Edge Functions | Configured via Supabase |
| Platforms supported | Android, iOS, macOS, Windows, Linux, Web | — |

## Prerequisites
- Flutter SDK — `^3.11.4` (from `pubspec.yaml`)
- Dart SDK (bundled with Flutter)
- A Supabase project (URL + anon key)
- Platform toolchains as needed: Android Studio/SDK (android), Xcode (ios/macos), Visual Studio (windows)
- Access to: Firebase Console (for FCM Push Notifications)

## Installation
```bash
git clone <repo-url>
cd ievaluateapp_final
flutter pub get
```

## Configuration

Config values live in `.env` and `.env.json` at the project root. **Never commit real values** — keep an `.env.example` / `.env.json.example` with placeholder keys only, and make sure `.env`/`.env.json` are in `.gitignore`. All variables are injected at build time via `--dart-define-from-file=.env.json` and mapped in `lib/core/config/env.dart`.

| Variable | Purpose | Used in (file) | Required? | Example |
|---|---|---|---|---|
| `SUPABASE_URL` | Supabase project URL | `lib/core/config/env.dart` | Yes | `https://xxxx.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase public anon key | `lib/core/config/env.dart` | Yes | `xxxx` |
| `N8N_BASE_URL` | Base webhook URL for n8n | `lib/core/config/env.dart` | Yes | `https://n8n...` |
| `USE_N8N_TEST` | Flag for test webhooks | `lib/core/config/env.dart` | No | `true` |
| `N8N_WEBHOOK_*` | Various n8n workflow triggers | `lib/core/config/env.dart` | Yes | `...` |
| `PYTHON_PROCESS_CROP` | Python processing endpoint | `lib/core/config/env.dart` | Yes | `...` |

## Running Locally
```bash
flutter run --dart-define-from-file=.env.json
```

## Architecture Overview
The application uses a Flutter client communicating directly with a Supabase backend (handling Authentication, Database, Storage, and Edge Functions). External services include Firebase Cloud Messaging (FCM) for push notifications (e.g. sentiment alerts to Department Heads) and n8n webhooks for data ingestion/processing pipelines.

## Key Modules & File Locations
| Module | Responsibility | Location |
|---|---|---|
| App entry point | Bootstraps app, initializes Supabase | `lib/main.dart` |
| Supabase client setup | Exposes the Supabase client wrapper | `lib/core/config/env.dart` |
| Auth | Sign up / sign in / session handling | `lib/core/services/auth_service.dart` |
| Push notifications | Registers FCM token, saves to Supabase | `lib/core/services/push_notification_service.dart` |
| AI / Data Evaluation | Handles n8n API logic for scanning | `lib/core/services/evaluation_service.dart` |
| Supabase migrations | DB schema history & RLS | `supabase/migrations/` |
| Supabase edge functions | Server-side logic (e.g. `send-intervention-email`) | `supabase/functions/` |

## External Resources & Services

### Push Notifications
- **Provider:** Firebase Cloud Messaging (`firebase_messaging`)
- **Platform config:** `android/app/google-services.json` (Android), `ios/Runner/Info.plist` (iOS)
- **Config location:** `lib/core/services/push_notification_service.dart`
- **Triggered by:** Initialized globally in `lib/core/navigation/main_scaffold.dart` and `lib/gatherer/data_gatherer_screen.dart` via `init()`.
- **Failure behavior:** Caught and logged via `debugPrint` silently so it does not block the UI. Tokens update automatically via `_fcm.onTokenRefresh.listen`.

### Email
- **Provider:** Supabase Auth (built-in) & Edge Functions
- **Config location:** `supabase/functions/send-intervention-email/`
- **Triggered by:** Password resets handled directly in `auth_service.dart` via `resetPasswordForEmail`.

### Supabase (Database / Auth / Storage)
- **Project config:** `.env.json` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`)
- **Migrations:** 6 SQL files in `supabase/migrations/` defining schema, Row Level Security (RLS), and queues.
- **Client init:** `Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey)` in `lib/main.dart`.

## Error Handling & Troubleshooting

| Symptom | Likely Cause | Where to Look | Fix |
|---|---|---|---|
| Push notifications not arriving | Missing `google-services.json` or n8n webhook misconfiguration | `push_notification_service.dart`, n8n workflow | Verify Firebase config is in `android/app/` and n8n uses the correct service account. |
| Auth fails with no explicit error | SocketException or network block | `auth_service.dart` | Check device connectivity; `auth_service.dart` traps `AuthException` and `SocketException` into structured `AuthResult`. |
| App fails to start / white screen | Missing `.env.json` values or Supabase init failing | `lib/main.dart` | Run app specifically with `--dart-define-from-file=.env.json`. |
| Scanner Data not uploading | n8n webhook returns non-200 or timeout | `gatherer_scanner_view.dart`, `data_validation_screen.dart` | Check n8n webhook status and `N8N_WEBHOOK_SCAN_UPLOAD` variable. |

## Screens & Features

### Core & Navigation
- **LoginScreen** (`lib/login_screen.dart`): Authentication entry.
  - Allows login via email/password.
  - Triggers forgot password flow via Dialog.
- **SignUpScreen** (`lib/signup_screen.dart`): User registration.
  - Registers user and maps to department/roles.
  - Navigates back to Login.
- **MainScaffold** (`lib/core/navigation/main_scaffold.dart`): Global app wrapper.
  - Initializes Push Notifications.
  - Provides role-based drawer navigation (`screenForRole`).

### Gatherer Role
- **DataGathererScreen** (`lib/gatherer/data_gatherer_screen.dart`): Primary gathering interface.
  - Refreshes dashboard.
- **GathererScannerView** (`lib/gatherer/gatherer_scanner_view.dart`): Scanner interface.
  - Uses camera to scan documents and triggers `_acceptImage`.
- **DataValidationScreen** (`lib/gatherer/data_validation_screen.dart`): Validates OCR data.
  - Submits valid data or discards records.
- **FailedScansScreen & Detail** (`lib/gatherer/failed_scans_screen.dart`, `failed_scan_detail_screen.dart`):
  - Displays queued failed scans.
  - Allows manual correction, resubmission, or discarding of failed OCR scans.
- **GoogleSheetImportScreen** (`lib/gatherer/google_sheet_import_screen.dart`):
  - Handles bulk data import workflows.

### Instructor Role
- **InstructorDashboardScreen** (`lib/instructor/instructor_dashboard.dart`): Landing page.
  - Triggers manual sync.
  - Navigates to DetailedReportScreen and SubjectDetailScreen.
- **StudentFeedbackScreen** (`lib/instructor/student_feedback_screen.dart`): 
  - Fetches and displays qualitative feedback data.
- **DetailedReportScreen** (`lib/instructor/detailed_report_screen.dart`): 
  - Displays total evaluations (`_totalEvals`).
  - Generates PDF reports of evaluation data.
- **PastSemestersScreen** (`lib/instructor/past_semesters_screen.dart`): 
  - Allows term selection.
  - Fetches term history and navigates to past subject reports.

### Department Head Role
- **DepartmentDashboardScreen** (`lib/dept_head/department_dashboard_screen.dart`): High-level overview.
  - Navigates to InterventionReports and SubjectAnalytics.
- **FacultyRosterScreen** (`lib/dept_head/faculty_roster_screen.dart`):
  - Lists all instructors and navigates to their specific details.
- **InstructorDetailPage** (`lib/dept_head/instructor_detail_page.dart`):
  - Allows Deactivation of instructor accounts.
  - Navigates to Detailed Reports and Subject details.
- **InterventionReportsScreen** (`lib/dept_head/intervention_reports_screen.dart`):
  - Displays automated alerts for performance drops and critical sentiment.
- **DeptHeadSettingsScreen** (`lib/dept_head/dept_head_settings_screen.dart`):
  - Handles Executive Intelligence toggles (Performance, Sentiment, Digest).
  - Updates profile data and passwords.

### SAO Admin Role
- **AdminDashboardScreen** (`lib/sao_admin/admin_dashboard.dart`): Main SAO overview.
- **UserManagementScreen** (`lib/sao_admin/user_management_screen.dart`):
  - Approves, adds, and manages system users.
- **ManageDepartmentsScreen** (`lib/sao_admin/manage_departments_screen.dart`):
  - Adds, edits, and deletes department entities.
- **ManageSubjectsScreen** (`lib/sao_admin/manage_subjects_screen.dart`):
  - Maps subjects, bulk imports subjects, and manages assignments.
- **PersonnelManagementScreen** (`lib/sao_admin/personnel_management_screen.dart`):
  - Broad personnel overview and CRUD operations.
- **ImportErrorsScreen & Detail** (`lib/sao_admin/import_errors_screen.dart`, `import_error_detail_screen.dart`):
  - Fetches system bulk import errors.
  - Allows manual correction or discarding of errored rows.
- **SystemAuditScreen** (`lib/sao_admin/system_audit_screen.dart`):
  - Displays system logs with sorting capabilities.
- **LiveSystemMetricsScreen** (`lib/sao_admin/live_system_metrics_screen.dart`):
  - Loads all high-level system metrics.

## Testing
Run tests using:
```bash
flutter test
```
*(Check `test/` directory for exact coverage; ensure mock `.env` variables are provided for unit tests targeting Supabase).*

## Deployment
- **Android:** `flutter build apk` or `flutter build appbundle`. (Requires setting up keystore in `android/key.properties`).
- **iOS:** `flutter build ipa`. (Requires macOS, Xcode, and Apple Developer account).
- **Supabase Backend:** Deploy migrations via `supabase db push` and edge functions via `supabase functions deploy`.

## Common Pitfalls
- **Missing Environment Variables:** Forgetting to pass `--dart-define-from-file=.env.json` during build will cause the app to hang on a white screen at startup since Supabase will fail to initialize.
- **Token Overwrites:** If multiple users log into the same device, the FCM token in `user_info` updates to the newest user. Ensure users log out properly.

## Support
For system issues, contact the SAO Admin team or your designated system architect.
