## 1.2.1

* **Download completes → install starts automatically.** Background downloads are
  now watched by a foreground service that launches the package installer the
  moment the download finishes — the user no longer has to find a notification
  or reopen the app. The system install confirmation is still shown (never a
  silent install). Requires one-time "Install unknown apps" consent as before.
* **Fixed: completion broadcast never arrived.** The manifest receiver was
  declared `exported="false"`, so on Android 8.0+ it could not receive the
  DownloadManager completion broadcast — the "Update ready" notification never
  appeared and the finished state was never recorded. Now `exported="true"` with
  id re-validation.
* Opening the app after a completed-but-not-installed download now starts the
  install immediately (foreground path) instead of showing the update dialog
  again.

## 1.2.0

* **Background system downloads** — new `UpdateConfig.backgroundDownload` flag.
  When enabled, tapping "Update" enqueues the APK through the system
  `DownloadManager` instead of downloading inside the dialog. Benefits:
  * The download **keeps running** when the phone locks or the app is killed —
    no more restarting from zero when the screen turns off.
  * A **visible progress notification** is shown, so the user doesn't have to
    watch the app.
  * The dialog closes and the app is **moved to the background** automatically.
  * On completion the receiver posts the actionable "Update ready" notification
    (tap → installer), the same flow as before.
* **No more double prompts / double taps**:
  * Tapping "Update" or "Later" can no longer dismiss a *stacked* dialog and
    appear to need a second tap — repeated concurrent checks are suppressed.
  * While a background download for a version is downloading or already
    finished, the check silently skips prompting (the notification flow owns it).
  * Native enqueue is **de-duplicated by tag** — re-tapping Update can never
    enqueue a second download of the same version.
* Requires Android `minSdk 24` (unchanged).

## 1.1.1

* **Fixed silent freeze in `UpdateDialog` on "Update" tap** — the native
  install-permission preflight (`canRequestPackageInstalls`) now runs inside a
  try/catch, so a platform hiccup can never stall the dialog in its initial
  state. When permission is missing it opens install settings and shows a clear
  hint instead of appearing to do nothing.
* **Always-visible download progress** — the progress bar starts animating
  (indeterminate) the moment downloading begins, then switches to a determinate
  percentage once bytes arrive.
* Failed downloads now reset state so "Update" remains retryable.

## 1.1.0

* **Bundled first-party Android plugin** — install permission flow, FileProvider
  APK sharing and installation are now native `android/` code merged automatically.
  **No `setup` run, Kotlin, or manifest edits needed for runtime anymore**; `setup`
  is now optional (signing + CI generation only).
* **Background auto-updates via system `DownloadManager`** — `startBackgroundDownload()`
  keeps downloading even if the app is killed; the native `FlutterGithubUpdaterReceiver`
  posts an "Update ready" notification whose tap launches the installer directly.
  Status queryable via `backgroundUpdateStatus(tag)`.
* `checkForGithubUpdate(config, force: true)` — manual "Check for update" now ignores the "Later" dismissal and always offers the update again.
* Resilient release fetch — when `api.github.com` is slow, rate-limited (403) or 404s, the check falls back to the public `github.com/<repo>/releases/latest` page (`allowHtmlFallback`), so updates no longer silently disappear.
* Semantic-version fallback — tags without a `+build` part (e.g. `v1.2.3`) are now detected as updates by comparing version numbers; build numbers (when present) still take priority.
* Default `checkTimeout` raised 10s → 20s for slow mobile networks.
* Default `methodChannelName` is now `flutter_github_updater` (matches the plugin).
* Extracted pure `parseTag` + `compareVersions` helpers (unit tested).
* Fixed stale `promptIfUpdateAvailable` reference in the README API docs.

## 1.0.0

* Initial release.
* `dart run flutter_github_updater:setup` — auto-generates all Android code, manifest, signing, workflows.
* `GithubUpdateService` — fetch latest release, compare versions, prompt dialog.
* `UpdateDialog` — customizable download + install UI (Material 3).
* `GithubUpdaterConfig` — configure repo owner/name, MethodChannel, labels.
* Native Android Kotlin handler: install permission, FileProvider APK install.
* GitHub Actions workflow templates: `build_release.yml` + `pr_check.yml`.
* Android setup: AndroidManifest, file_paths.xml, build.gradle signing, proguard.
