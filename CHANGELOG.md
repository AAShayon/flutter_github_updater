## 1.0.0

* Initial release.
* `dart run flutter_github_updater:setup` — auto-generates all Android code, manifest, signing, workflows.
* `GithubUpdateService` — fetch latest release, compare versions, prompt dialog.
* `UpdateDialog` — customizable download + install UI (Material 3).
* `GithubUpdaterConfig` — configure repo owner/name, MethodChannel, labels.
* Native Android Kotlin handler: install permission, FileProvider APK install.
* GitHub Actions workflow templates: `build_release.yml` + `pr_check.yml`.
* Android setup: AndroidManifest, file_paths.xml, build.gradle signing, proguard.
