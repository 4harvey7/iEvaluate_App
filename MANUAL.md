# Developer Manual: iEvaluate App

Welcome to the iEvaluate project! This manual is designed for new developers, teammates, or anyone stepping into the codebase for the first time. It covers everything from what the app does to how to get it running on your machine.

---

## 1. PROJECT OVERVIEW
iEvaluate is a cross-platform educational evaluation and performance tracking application. In simple terms, it helps educational institutions gather, digitize, and analyze student evaluations of instructors. It provides tailored dashboards for different roles—Instructors, Data Gatherers, Department Heads, and SAO (Student Affairs Office) Admins—to view real-time analytics, automated performance alerts, and manage the system.

---

## 2. TECH STACK
Here are the core technologies powering the app and why they are used:

- **Flutter & Dart**: The primary frontend framework and language. Flutter allows us to write one codebase and deploy it to Android, iOS, Web, and Desktop.
- **Supabase**: Our Backend-as-a-Service (BaaS). It provides the PostgreSQL database, user authentication, file storage, and serverless Edge Functions.
- **n8n**: A workflow automation tool. We send requests to n8n webhooks to handle complex data ingestion pipelines (like processing scanned evaluation documents and OCR data).
- **Firebase Cloud Messaging (FCM)**: Used for delivering push notifications (like alerting a Department Head of a drop in instructor performance) across mobile devices.
- **Brevo**: Used behind-the-scenes by our Supabase Edge Functions to send transactional emails (like password resets or account invites).
- **Python**: Used for various ad-hoc maintenance and data manipulation scripts found in the root directory (e.g., database checks and data deduplication).

---

## 3. FOLDER & FILE STRUCTURE
Here is a high-level map of the codebase to help you find your way around:

```text
ievaluateapp_final/
├── android/                   # Android-specific native code and configurations
├── ios/                       # iOS-specific native code and configurations
├── assets/                    # Static files like images and fonts (e.g., CTU_logo.png)
├── lib/                       # The main Dart/Flutter codebase (Where you'll spend most of your time)
│   ├── core/                  # Shared utilities, configs, navigation logic, and API services
│   ├── dept_head/             # UI screens specific to the Department Head role
│   ├── gatherer/              # UI screens for Data Gatherers (e.g., document scanning)
│   ├── instructor/            # UI screens for Instructors (e.g., feedback and performance reports)
│   ├── sao_admin/             # UI screens for SAO Admins (e.g., user and system management)
│   ├── theme/                 # App-wide visual styles, colors, and themes
│   ├── widgets/               # Reusable UI components (buttons, dialogs, cards)
│   └── main.dart              # The entry point of the app (App starts here!)
├── supabase/                  # Backend configurations
│   ├── functions/             # Deno (TypeScript) serverless functions for secure/admin operations
│   └── migrations/            # SQL scripts that define database tables and security rules (RLS)
├── .env.json                  # Environment variables file (API keys, URLs). *Do not commit this!*
├── pubspec.yaml               # Package manager file: lists app dependencies, fonts, and assets
└── README.md                  # Project overview and architecture documentation
```

---

## 4. PREREQUISITES
Before you start coding, you must have the following installed on your machine:

1. **Flutter SDK (`^3.11.4`)**
   - Download and install from: https://docs.flutter.dev/get-started/install
   - Verify installation in your terminal: `flutter --version`
2. **Dart SDK**
   - This comes bundled automatically when you install Flutter.
3. **Android Studio (for Android) or Xcode (for macOS/iOS)**
   - To compile and run the app on mobile emulators/devices.
4. **Git**
   - For version control.
5. **Supabase CLI (Optional but recommended)**
   - If you need to manage the backend, write database migrations, or test edge functions locally.
   - Install via NPM: `npm install -g supabase`
   - Or via Homebrew (Mac): `brew install supabase/tap/supabase`

---

## 5. SETUP INSTRUCTIONS
Follow these exact steps to get the app running locally on your machine.

**Step 1: Clone the repository**
```bash
git clone <repository-url>
cd ievaluateapp_final
```

**Step 2: Fetch Flutter dependencies**
Download all the third-party packages listed in `pubspec.yaml`.
```bash
flutter pub get
```

**Step 3: Set up your environment variables**
The app needs API keys to talk to the backend. We have created a template file for you.
Copy the template to create your actual `.env.json` file.
```bash
# On Mac/Linux:
cp .env.json.example .env.json

# On Windows (PowerShell):
Copy-Item .env.json.example .env.json
```
*Note: Open `.env.json` and replace the placeholder values with the real API keys provided by your team lead.*

**Step 4: Run the app**
Launch an emulator (via Android Studio / Xcode) or connect a physical device, then run:
```bash
flutter run --dart-define-from-file=.env.json
```

---

## 6. ENVIRONMENT VARIABLES / CONFIG
The app uses `.env.json` to securely load configuration values at build time. 

Here is what every variable means:

- `SUPABASE_URL`: The web address of the Supabase project database. (Get from Supabase Dashboard).
- `SUPABASE_ANON_KEY`: The public, anonymous key to access Supabase securely. (Get from Supabase Dashboard).
- `N8N_BASE_URL`: The web address of the n8n automation server.
- `USE_N8N_TEST`: Set to `"true"` or `"false"` to toggle between test/production webhooks.
- `N8N_WEBHOOK_HEALTH`: Endpoint to check if n8n is online.
- `N8N_WEBHOOK_SCAN_UPLOAD`: Endpoint for uploading scanned evaluation images.
- `N8N_WEBHOOK_LINK_UPLOAD`: Endpoint for uploading document links.
- `N8N_WEBHOOK_CROP_OCR`: Endpoint for Optical Character Recognition (reading text from images).
- `N8N_WEBHOOK_MANUAL_CORRECTION`: Endpoint for handling human corrections on failed scans.
- `N8N_WEBHOOK_SUBJECT_BULK_IMPORT`: Endpoint for bulk importing school subjects.
- `N8N_WEBHOOK_IMPORT_ERROR_CORRECTION`: Endpoint for fixing errors in bulk imports.
- `PYTHON_PROCESS_CROP`: The endpoint path for a Python-based image processing service.

*(In the Supabase Dashboard itself, the Edge Functions also use `BREVO_API_KEY` and `BREVO_SENDER_EMAIL` for sending automated emails. You don't need these in your local Flutter app).*

---

## 7. HOW TO RUN THE APP

**To run in Development Mode (with hot-reload):**
```bash
flutter run --dart-define-from-file=.env.json
```

**To build a Production Android App (APK):**
```bash
flutter build apk --dart-define-from-file=.env.json
```

**To run Automated Tests:**
```bash
flutter test
```

---

## 8. HOW THE APP WORKS (Architecture)

1. **Entry Point**: The app launches from `lib/main.dart`. It initializes Supabase and Firebase.
2. **Authentication**: Users log in via email/password. `lib/core/services/auth_service.dart` handles this.
3. **Role-Based Routing**: Once logged in, the app checks the user's role (Instructor, Gatherer, Admin, etc.) and routes them to their specific dashboard using `screenForRole()` in `lib/main.dart`.
4. **Data Fetching**: The Flutter UI talks directly to Supabase via the `supabase_flutter` package. Security is maintained by Row Level Security (RLS) policies in the database, meaning users can only fetch data they are allowed to see.
5. **Complex Logic**: For heavy lifting (like processing a scanned exam paper), the app sends the image to an **n8n webhook**. n8n processes the data and saves it to the database.
6. **Admin Actions**: For secure admin actions (like deleting users or promoting roles), the app calls **Supabase Edge Functions** (written in TypeScript). These functions bypass standard security to perform the action safely on the server side and use Brevo to send notification emails.

---

## 9. COMMON TASKS

**How to add a new package/dependency:**
If you need a new tool (like a new chart library):
```bash
flutter pub add <package_name>
```

**How to add a new screen:**
1. Create a new Dart file in the appropriate role folder (e.g., `lib/instructor/new_report_screen.dart`).
2. Build your Flutter UI (usually extending `StatelessWidget` or `StatefulWidget`).
3. If it needs to show up in the side menu, add the route to `lib/core/navigation/role_nav_config.dart`.

**How to run a database migration:**
If you need to add a new table to the backend:
1. Generate a new SQL file: `supabase migration new create_new_table`
2. Write your SQL in the generated file located in `supabase/migrations/`.
3. Apply the changes to the live database: `supabase db push`

---

## 10. TROUBLESHOOTING

- **Error: App boots to a white screen and hangs.**
  - **Cause:** You forgot to pass the environment variables when running the app, so Supabase cannot connect.
  - **Fix:** Always run the app using `flutter run --dart-define-from-file=.env.json`.

- **Error: Push notifications are not arriving.**
  - **Cause:** Missing Firebase configuration files.
  - **Fix:** Ensure you have placed `google-services.json` in the `android/app/` folder (for Android) or the appropriate `Info.plist` setup for iOS.

- **Error: Scanner data is not uploading.**
  - **Cause:** The n8n server is unreachable or the webhook URL is incorrect.
  - **Fix:** Verify your local network connection, ensure `N8N_BASE_URL` in `.env.json` is correct, and check if the n8n instance is online.

- **Error: Unrecognized role / kicked back to login screen.**
  - **Cause:** A new role was added to the database but not mapped in the app.
  - **Fix:** Update `UserRole` and `roleFromString()` inside `lib/core/navigation/role_nav_config.dart`.

---

## 11. WHERE TO GO FOR HELP

- **Start Here**: Read `README.md` for a deeper dive into the system's external services.
- **Navigation Logic**: Check `lib/core/navigation/role_nav_config.dart` if you are confused about how users are moving between screens.
- **Flutter Framework Docs**: https://docs.flutter.dev/ (Great for UI, layouts, and state management).
- **Supabase Docs**: https://supabase.com/docs (Great for Database queries, Row Level Security, and Edge Functions).
- **Who owns what**: For deep backend configuration issues, consult the SAO Admin team or the system architect mentioned in the repository commit history.
