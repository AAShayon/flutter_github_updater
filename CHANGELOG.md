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
