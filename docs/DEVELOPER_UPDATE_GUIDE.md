# iEvaluate: Developer Update Guide

How to ship an update so installed phones update themselves.
All commands are for Windows PowerShell, run from the project root (`C:\Projects\ievaluateapp_final`).

---

## 1. How the update system works

```
App starts (after login)
   |
   v
Reads the newest row of table app_releases in Supabase
   |
   v
Is version_code higher than the installed build number (+N)?
   | no  -> nothing happens
   | yes
   v
Shows "Update available" -> user taps Update
   |
   v
Downloads the APK from a GitHub Release (HTTPS only)
   |
   v
Checks the SHA-256 of the file against the row.
Mismatch = file deleted, nothing installed.
   |
   v
Opens the Android installer. The user taps Install.
```

Key files:

- `pubspec.yaml`: the version. `1.0.1+2` means name `1.0.1`, build number `2`. The app compares the build number only.
- `lib/core/services/update_service.dart`: check, download, hash check, open installer.
- `lib/widgets/update_tile.dart`: the "Check for updates" button in Settings, the update dialog, and `UpdateCheckGate`.
- `lib/main.dart`: wraps the first screen after login in `UpdateCheckGate` (checks once per app start).
- `supabase/migrations/20240130000035_app_releases.sql`: creates the `app_releases` table.
- `android/app/build.gradle.kts`: signs the release APK.

The check works on Android only. A failed check never blocks the app.

---

## 2. One-time setup (do once)

1. **Run migration 035** in Supabase (SQL editor): paste the contents of `supabase/migrations/20240130000035_app_releases.sql` and run it.
2. **Back up the keystore.** The file is `android/app/keystore/release.jks`. Git ignores it on purpose.
   - Copy it to a safe private place (password manager, encrypted drive). Store its alias and passwords there too.
   - If you lose it, no installed phone can ever update again. Everyone must uninstall and reinstall.
3. **Make the GitHub repo public**: https://github.com/4harvey7/iEvaluate_App (Settings, General, Danger Zone, Change visibility).
   - Phones download without logging in. If the repo is private, every download fails.
4. **Optional: install the GitHub CLI** and log in:
   ```powershell
   winget install GitHub.cli
   gh auth login
   ```
5. **The first install is by hand.** A phone can only update itself if it already has a build that contains the update feature. Send that APK once (USB, chat, cloud link).
6. **Each phone, once:** allow "Install unknown apps" for iEvaluate in Android Settings. Android asks the first time you tap Update. Allow it.
7. **Signing key must match.** A phone with a debug-signed or differently-signed build must uninstall iEvaluate once, then install the release build. After that, updates work.

---

## 3. Release an update, step by step

### Step 1. Commit and push your code
```powershell
git add <your changed files>
git commit -m "Describe the change"
git push
```

### Step 2. Bump the version in `pubspec.yaml`
Format is `X.Y.Z+N`. The `+N` number **must go up every release**. The app ignores the name part.

```yaml
# before
version: 1.0.1+2
# after
version: 1.0.2+3
```

(The version in the repo today is `1.0.0+1`, so the first update would be `1.0.1+2`.)

### Step 3. Build the release APK
```powershell
flutter build apk --release --dart-define-from-file=.env.json
```
Output file: `build\app\outputs\flutter-apk\app-release.apk`

Notes:
- `.env.json` holds the app keys (git ignores it). Without `--dart-define-from-file` the app builds but cannot reach Supabase.
- The build is signed with `android/app/keystore/release.jks`. If the file is missing, the build fails on purpose. It never falls back to the debug key.
- To use another keystore, set these environment variables before building: `KEYSTORE_FILE`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`. If you do not set them, `build.gradle.kts` uses its built-in defaults. Read that file to see them. Never copy passwords into docs or chat.

### Step 4. Get the SHA-256
```powershell
certutil -hashfile build\app\outputs\flutter-apk\app-release.apk SHA256
```
Copy the long hex line (64 characters, no spaces). Ignore the other lines.
**Hash the exact file you will upload.** If you rebuild, hash again.

### Step 5. Create the GitHub Release and upload the APK
The tag (for example `v1.0.2`) must match the tag in the download URL used in step 6.

**Web way:**
1. Open https://github.com/4harvey7/iEvaluate_App/releases/new
2. Choose a tag: type `v1.0.2`, click "Create new tag".
3. Title: `v1.0.2`. Add short notes.
4. Drag `app-release.apk` into the files box. Wait for the upload to finish.
5. Click "Publish release" (not draft).

**CLI way:**
```powershell
gh release create v1.0.2 build\app\outputs\flutter-apk\app-release.apk --repo 4harvey7/iEvaluate_App --title "v1.0.2" --notes "What changed"
```

The file name must stay `app-release.apk`. Check that this link starts a download in your browser:
`https://github.com/4harvey7/iEvaluate_App/releases/download/v1.0.2/app-release.apk`

### Step 6. Add the row in Supabase
In the Supabase SQL editor (it bypasses RLS, so the insert works):

```sql
insert into public.app_releases
  (version_code, version_name, apk_url, sha256, notes, force)
values (
  3,                      -- the +N from pubspec.yaml
  '1.0.2',                -- the X.Y.Z part
  'https://github.com/4harvey7/iEvaluate_App/releases/download/v1.0.2/app-release.apk',
  '<64-character hash from step 4>',
  'What changed, in plain words',
  false
);
```
`version_code` is unique. You cannot reuse a number.

### Step 7. Test on one phone
1. Use a phone with an older build that has the update feature.
2. Open iEvaluate, go to Settings, About, tap **Check for updates**.
3. You should see "Version 1.0.2 is available". Tap **Update to v1.0.2**.
4. Wait for the download, tap Install, open the app.
5. Settings should now show `iEvaluate Version 1.0.2 (build 3)`. "Check for updates" should say "You have the latest version."

---

## 4. Forced updates

The `force` column is `true` or `false`.

- **false (normal):** the user sees "Update available" with a **Later** button.
- **true:** the user sees "Update required". There is no Later button and the dialog cannot be dismissed. They must update to continue.

Set `force` to `true` only when the old version is broken or unsafe (data bug, security fix, server change old builds cannot handle). Test on one phone first. A bad forced release locks every user out.

To force an existing release:
```sql
update public.app_releases set force = true where version_code = 3;
```

---

## 5. Release checklist

- [ ] Code committed and pushed
- [ ] `pubspec.yaml` version bumped, `+N` is higher than the last release
- [ ] Built with `flutter build apk --release --dart-define-from-file=.env.json`
- [ ] SHA-256 taken from the exact APK being uploaded
- [ ] GitHub Release published (not draft), file named `app-release.apk`, tag matches the URL
- [ ] Download URL opens in a browser
- [ ] `app_releases` row inserted (`version_code` = `+N`, correct hash, `force` false)
- [ ] Tested on one phone: Settings, Check for updates, install works
- [ ] A copy of the APK saved somewhere safe

---

## 6. Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| App not seeing the update | `version_code` not higher than the installed `+N`; row missing; phone offline; RLS or grants changed so reads fail | Check the table. Compare with the build number in Settings. Check internet. Confirm the `app_releases_read` policy still exists. |
| "App not installed" / package conflict | Installed app was signed with a different key (debug or other keystore) | Uninstall iEvaluate once, install the release build. Always sign with `release.jks`. |
| "Checksum mismatch" | Wrong hash in the row, or the APK was rebuilt or re-uploaded after hashing | Download the file from GitHub, run `certutil` on it, fix the row: `update public.app_releases set sha256 = '...' where version_code = 3;` |
| Install blocked / "Install permission denied" | "Install unknown apps" not allowed for iEvaluate. On Android 14 the app must be in the foreground | Allow it in Android Settings. Keep iEvaluate open on screen while installing. |
| Download fails (HTTP 404, etc.) | Repo is private, wrong tag or file name, release still a draft, link not HTTPS | Open `apk_url` in a browser. Fix the row or the release. |
| Update button missing | The installed build is older than the update feature | Install the new APK by hand once (chapter 2, step 5). |

---

## 7. Safety notes

- **Never give anyone write access to `app_releases`.** Whoever can write that table can push any APK to every phone. Migration 035 allows read only. Do not add insert/update/delete policies or grants.
- HTTPS only. The app refuses any other link.
- Never commit the keystore, its passwords, or `.env.json`.
- Keep a copy of every released APK and its hash.
- Never send the keystore over chat or email.

---

## 8. Where to look in the code

- `pubspec.yaml`: app version and dependencies.
- `android/app/build.gradle.kts`: release signing and keystore variables.
- `lib/core/services/update_service.dart`: check logic, `isNewer`, download, hash check, installer.
- `lib/widgets/update_tile.dart`: Settings "About" card, update dialog, forced-update behaviour, `UpdateCheckGate`.
- `lib/main.dart`: where `UpdateCheckGate` is placed.
- `supabase/migrations/20240130000035_app_releases.sql`: table, RLS, grants.
- `.env.json` (not in git): keys passed in at build time.
