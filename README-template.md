# ievaluateapp_final

[One or two sentences: what this app does and who it's for.]

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
- [Testing](#testing)
- [Deployment](#deployment)
- [Common Pitfalls](#common-pitfalls)
- [Support](#support)

---

## Tech Stack
| Layer | Technology | Version |
|---|---|---|
| App framework | Flutter | [from `pubspec.yaml` `environment:`] |
| Language | Dart | [ ] |
| Backend | Supabase | [ ] |
| Push notifications | [confirm from `pubspec.yaml`] | [ ] |
| Email | [confirm — Supabase Auth / Edge Function / other] | [ ] |
| Platforms supported | Android, iOS, macOS, Windows, Linux, Web | — |

## Prerequisites
- Flutter SDK — version pinned in `pubspec.yaml` (`environment:` block)
- Dart SDK (bundled with Flutter)
- A Supabase project (URL + anon key)
- Platform toolchains as needed: Android Studio/SDK (android), Xcode (ios/macos), Visual Studio (windows)
- Access to: [ ] push notification provider account, [ ] email provider account (if separate from Supabase)

## Installation
```bash
git clone [repo url]
cd ievaluateapp_final
flutter pub get
```

## Configuration

Config values live in `.env` and `.env.json` at the project root. **Never commit real values** — keep an `.env.example` / `.env.json.example` with placeholder keys only, and make sure `.env`/`.env.json` are in `.gitignore`.

| Variable | Purpose | Used in (file) | Required? | Example |
|---|---|---|---|---|
| `SUPABASE_URL` | Supabase project URL | `[path — likely lib/main.dart or a config/service file]` | Yes | `https://xxxx.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase public anon key | `[path]` | Yes | `xxxx` |
| `[PUSH_*]` | Push notification provider key | `[path]` | Yes | `xxxx` |
| `[EMAIL_*]` | Email provider key (if not using Supabase Auth email) | `[path]` | [ ] | `xxxx` |
| `[VAR]` | [ ] | `[path]` | [ ] | [ ] |

> Fill in by having the Antigravity agent trace every place `.env`/`.env.json` values are loaded in `lib/`.

## Running Locally
```bash
flutter run -d [device id, e.g. chrome / windows / android]
```

## Architecture Overview
[High-level description: Flutter client → Supabase (auth/db/storage/edge functions) → external push/email providers. Add a diagram once module map is confirmed.]

## Key Modules & File Locations
| Module | Responsibility | Location |
|---|---|---|
| App entry point | Bootstraps app, initializes Supabase | `lib/main.dart` (confirm) |
| Supabase client setup | Creates/exposes the Supabase client | `[path]` |
| Auth | Sign up / sign in / session handling | `[path]` |
| Push notifications | Registers device, handles incoming/outgoing push | `[path]` |
| Email | Triggers transactional email (reset password, invites, etc.) | `[path]` |
| [Evaluation feature — likely the app's core domain] | [ ] | `[path]` — see also `evaluation_service_extract.txt` |
| Supabase migrations | DB schema history | `supabase/migrations/` |
| Supabase edge functions (if any) | Server-side logic | `supabase/functions/` |

## External Resources & Services

### Push Notifications
- **Provider:** [confirm from `pubspec.yaml` — e.g. Firebase Cloud Messaging via `firebase_messaging`]
- **Platform config:** `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist` (confirm presence)
- **Config location (app code):** `[path]`
- **Triggered by:** `[event/function]` in `[path]`
- **Failure behavior:** [retried? logged? silent?] — see `[path]`

### Email
- **Provider:** [confirm — Supabase built-in auth email, or a separate provider called from an edge function]
- **Config location:** `[path]` or `supabase/functions/[name]`
- **Triggered by:** `[event/function]` in `[path]`
- **Failure behavior:** [ ] — see `[path]`

### Supabase (Database / Auth / Storage)
- **Project config:** `.env` / `.env.json` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`)
- **Migrations:** `supabase/migrations/`
- **Client init:** `[path]`

## Error Handling & Troubleshooting

| Symptom | Likely Cause | Where to Look | Fix |
|---|---|---|---|
| Push notifications not arriving | Invalid/missing platform config (`google-services.json`/`GoogleService-Info.plist`) or provider key | `[path]`, provider dashboard | Verify platform config files are present and match your provider project; check provider console |
| Emails not sending | Wrong provider key, or Supabase email rate limit | `[path]`, Supabase dashboard logs | Confirm env var; check Supabase Auth > Logs |
| App fails to start / white screen | Missing `.env`/`.env.json` values, Supabase init failing | `lib/main.dart` (confirm) | Compare `.env`/`.env.json` against example file |
| Build fails on a specific platform | Missing platform toolchain or outdated pods/gradle | `ios/Podfile`, `android/build.gradle` | Run `flutter doctor`, update pods/gradle |
| [Other known failure mode] | [ ] | `[path]` | [ ] |

> Add a row here every time a real incident happens so the next dev doesn't have to re-diagnose it.

## Testing
```bash
flutter test
```
Test files live under `test/` (see `test/test_parser.dart` — confirm what it covers). [Note coverage gaps.]

## Deployment
[Steps for building release builds per platform, and how the Supabase backend (migrations/functions) gets deployed. Note where any CI config lives.]

## Common Pitfalls
- [ ] [e.g. "Forgetting to update `.env.json` after rotating Supabase keys causes silent auth failures — check `[path]`"]
- [ ] [ ]

## Support
[Who to contact / where to file issues.]
