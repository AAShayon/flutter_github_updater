# flutter_github_updater

**One-command auto-setup for in-app APK updates via GitHub Releases.**

No Firebase. No Shorebird. No paid plan. Fully free.

## How it works (30 seconds)

```
You push code → GitHub Actions builds APK → publishes to PUBLIC releases repo
                                                    ↓
                              App checks GitHub API on every launch
                                                    ↓
                              Newer? → Download → Install (one tap)
```

- **Source repo** stays **private** (your code is safe).
- **Releases repo** is **public** (contains only APK binaries, no code).
- **Cost**: $0. GitHub free tier handles everything.

---

## Quick start (2 minutes)

### Step 1: Add the package

```bash
flutter pub add flutter_github_updater
```

### Step 2: Run auto-setup

```bash
dart run flutter_github_updater:setup
```

This **auto-generates** everything:

| Generated | What it does |
|---|---|
| `MainActivity.kt` | MethodChannel for APK install (correct package name) |
| `AndroidManifest.xml` | +REQUEST_INSTALL_PACKAGES permission +FileProvider |
| `res/xml/file_paths.xml` | Tells Android where downloaded APKs live |
| `build.gradle(.kts)` | Shared signing config (updates install over old app) |
| `proguard-rules.pro` | Keeps Flutter classes, suppresses R8 warnings |
| `.github/workflows/build_release.yml` | CI: quality gate + build + publish release |
| `.github/workflows/pr_check.yml` | CI: lint + test on every PR |
| `lib/update_example.dart` | Copy-paste usage reference |

### Step 3: GitHub CI/CD configuration

The auto-setup handles all code. You just need to configure GitHub. There are **two ways** to set up the release repo — pick the one that fits your situation:

---

#### Option A — Separate releases repo (RECOMMENDED, source stays private)

Use this when you want to **keep your source code private** but still let clients download updates.

```
SOURCE repo (private, your code)   →   RELEASES repo (public, APK only)
   your_app/                             your_app_releases/
   .github/workflows/build_release.yml   app-release.apk (only file)
```

The workflow (auto-generated) builds the APK in your source repo, then pushes it to the separate public releases repo so clients can download it without any login.

**Step A1. Create a PUBLIC releases repo**

1. GitHub → **New repository**
2. Name: `your_app_releases` (e.g. `mudi_dokan_releases`)
3. **Public** — critical, the client app needs unauthenticated download access
4. Add **zero code** — this repo holds only the APK binary

**Step A2. Create a Personal Access Token**

1. GitHub → **Settings** → **Developer settings** → **Personal access tokens (classic)**
2. **Generate new token (classic)**
3. Scope: tick **`repo`** (full control — lets CI write to the other repo)
4. Expiration: 90 days (renew later)
5. Copy the token

**Step A3. Add a GitHub Secret** (in your **SOURCE** repo)

1. **Settings** → **Secrets and variables** → **Actions** → **New repository secret**
2. Name: `RELEASE_REPO_TOKEN`
3. Value: the token from Step A2

**Step A4. Add a GitHub Variable** (in your **SOURCE** repo)

1. **Settings** → **Secrets and variables** → **Actions** → **Variables** tab → **New variable**
2. Name: `RELEASES_REPO`
3. Value: `YOUR_USERNAME/your_app_releases`  ← the releases repo you made in A1

---

#### Option B — One public repo (source and releases in the SAME repo)

Use this when your **source repo is already public** (or you don't mind it being public). Then you don't need a second repo or a token at all — clients download the APK from your own repo's Releases page.

```
SINGLE repo (public)
   your_app/
   lib/ ...          (your code)
   .github/workflows/build_release.yml
   Releases →  app-release.apk  (built + published by CI)
```

**Step B1. Create/have a PUBLIC source repo**

Your repo must be **public** so clients can download the APK from its Releases page without login.

**Step B2. Set the GitHub Variable** (in your repo)

1. **Settings** → **Secrets and variables** → **Actions** → **Variables** tab → **New variable**
2. Name: `RELEASES_REPO`
3. Value: `YOUR_USERNAME/your_app`  ← your **own** repo

**Step B3. (Optional) Set `RELEASE_REPO_TOKEN`**

The workflow checks the built-in `GITHUB_TOKEN` automatically for the same repo (no token needed). If you leave `RELEASE_REPO_TOKEN` unset, the workflow prints a warning and still publishes to your own repo's Releases — that's all Option B needs.

> **Why two configs?** The token `RELEASE_REPO_TOKEN` exists only so CI can write to a **different** repo than the one running the workflow. If source and releases are the same repo, the built-in token already has write access — no PAT needed.

---

### Comparison

| | Option A: separate releases repo | Option B: one public repo |
|---|---|---|
| Source code | **Private** (safe) | Public |
| Need second repo | Yes | No |
| Need Personal Access Token | Yes | No |
| Need `RELEASE_REPO_TOKEN` secret | Yes | Optional/skip |
| `RELEASES_REPO` variable | `user/app_releases` | `user/app` (same repo) |
| Client can download | Always | Always |

**Recommended:** Option A if the app is proprietary/commercial. Option B if the project is open-source and sharing code is fine.

> ⚠️ Whichever option you pick, the repo where the **APK is published must be PUBLIC**, or clients cannot download updates.


### Step 4: Add update check to your app

In your splash screen (or home screen):

```dart
import 'package:flutter_github_updater/flutter_github_updater.dart';

// After navigation, check for updates:
const config = UpdateConfig(
  owner: 'YOUR_GITHUB_USERNAME',
  repo: 'your_app_releases',   // ← where CI publishes the APK
);
await GithubUpdateService(config).promptIfUpdateAvailable(context);
```

Or use the context extension:

```dart
await context.checkForGithubUpdate(UpdateConfig(
  owner: 'YOUR_GITHUB_USERNAME',
  repo: 'your_app_releases',
));
```

> **Which `repo` goes here?** It must be the repo where the **APK is published**:
> - **Option A** (separate releases repo): `repo: 'your_app_releases'`
> - **Option B** (single public repo): `repo: 'your_app'` ← your own repo
> The owner is always your GitHub username/org.

### Step 5: Bump version and push

```yaml
# pubspec.yaml
version: 1.0.0+1  →  1.0.1+2
```

```bash
git add -A
git commit -m "v1.0.1"
git tag v1.0.1+2
git push origin main --tags
```

**Done.** CI builds the APK, publishes to releases repo, your app auto-updates on next launch.

---

## Day-to-day workflow

After initial setup, this is ALL you do:

```
1. Fix a bug / add feature
2. Bump version:  version: 1.0.1+2  →  1.0.2+3
3. git commit + git push origin main --tags
4. Done. Clients auto-update on next app open.
```

---

## What the auto-setup generates

### Kotlin `MainActivity.kt`

The auto-setup detects your `applicationId` from `build.gradle(.kts)` and generates:

```kotlin
package com.yourcompany.yourapp  // ← auto-detected

// MethodChannel name: com.yourcompany.yourapp.updater
class MainActivity : FlutterActivity() {
    // Handles: canRequestPackageInstalls, openInstallSettings, installApk
}
```

**No manual Kotlin editing needed.**

### AndroidManifest.xml

Adds these entries (if not already present):

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>

<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths"/>
</provider>
```

### `build.gradle(.kts)` signing

Adds a shared signing config using a committed `debug.keystore`:

```kotlin
signingConfigs {
    create("shared") {
        storeFile = file("debug.keystore")
        storePassword = "android"
        keyAlias = "androiddebugkey"
        keyPassword = "android"
    }
}
```

Both `debug` and `release` build types use it → **same signature on every build/machine** → Android allows updates to install over old versions.

### GitHub Actions workflows

**`build_release.yml`** — Triggered by push to tags `v*`:
1. **Quality Gate**: `flutter analyze` + `flutter test`
2. **Build**: `flutter build apk --release --obfuscate`
3. **Publish**: Creates release on source repo + pushes APK to public releases repo

**`pr_check.yml`** — Triggered on PRs to `main`:
1. `flutter analyze` + `flutter test`

---

## API reference

### `UpdateConfig`

```dart
const config = UpdateConfig(
  owner: 'github_username',       // Required: GitHub repo owner
  repo: 'app_releases',           // Required: GitHub repo name
  methodChannelName: 'com.example.app/updater',  // Auto-matched by setup
  apkFileName: 'app-release.apk', // APK asset filename to look for
  localApkName: 'update.apk',    // Local download filename
  checkTimeout: Duration(seconds: 10),   // GitHub API timeout
  downloadTimeout: Duration(minutes: 5), // APK download timeout
  labels: UpdateLabels(...),      // Localizable strings
);
```

### `GithubUpdateService`

```dart
final service = GithubUpdateService(config);

// Fetch latest release info
final latest = await service.fetchLatestRelease();

// Check if update is newer than installed
final available = await service.isUpdateAvailable(latest!);

// One-shot: fetch + compare + show dialog (safe to call on every launch)
await service.promptIfUpdateAvailable(context);
```

### `UpdateLabels` (localization)

```dart
const labels = UpdateLabels(
  updateAvailable: 'नया अपडेट उपलब्ध',
  updateDescription: 'संस्करण v%s उपलब्ध है।',
  downloading: 'डाउनलोड हो रहा है...',
  downloadComplete: 'डाउनलोड पूरा — इंस्टॉल करें।',
  installNow: 'इंस्टॉल करें',
  later: 'बाद में',
  updateButton: 'अपडेट करें',
);
```

---

## Versioning (the critical rule)

```yaml
# pubspec.yaml
version: 1.0.1+2
#            ^ buildNumber — this is what the updater compares
```

- **Must increase the `+N` number** for every release.
- `version` before `+` is the display label (`v1.0.1`).
- If you forget to bump → no update dialog (correct, not a bug).

---

## Signing / keystore

- The auto-setup generates a shared `debug.keystore` (alias: `androiddebugkey`, password: `android`).
- Both debug and release builds use it → **same signature everywhere**.
- This allows update APKs to install over the old app without uninstall.

> **WARNING**: Never rotate/delete this keystore after publishing. Clients would need to uninstall + lose data.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| No update dialog after push | Version `+N` not bumped in `pubspec.yaml` |
| CI fails at release step | `RELEASE_REPO_TOKEN` missing/expired. Regenerate PAT. |
| CI fails at build | `flutter analyze` error. Check Actions log. |
| "Install blocked" | Android blocked unknown sources. App opens Settings automatically. |
| Download fails to install | Signature mismatch. Keystore was changed. Must uninstall + reinstall. |
| `releases/latest` 404 | No release published yet, or releases repo is private. |
| Offline client | `fetchLatest()` times out silently → no dialog, app works normally. |

---

## What the auto-setup does NOT generate (manual steps)

These cannot be automated because they require GitHub web UI / API actions:

1. **Creating the PUBLIC releases repo** — do this on GitHub
2. **Creating a Personal Access Token** — do this in GitHub Settings
3. **Adding the GitHub Secret** `RELEASE_REPO_TOKEN` — do this in repo Settings
4. **Adding the GitHub Variable** `RELEASES_REPO` — do this in repo Settings
5. **Calling `promptIfUpdateAvailable()`** in your app — one line of Dart code

Everything else is auto-generated.

---

## Requirements

- Flutter >= 3.24.0
- Dart SDK ^3.5.0
- Android only (iOS not supported — Apple has its own update system)
- A GitHub account (free tier is enough)
- `keytool` in PATH (for keystore generation — comes with Java/JDK)

---

## License

MIT
