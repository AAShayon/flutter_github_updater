/// Configuration for [GithubUpdateService].
class UpdateConfig {
  const UpdateConfig({
    required this.owner,
    required this.repo,
    this.methodChannelName = defaultMethodChannelName,
    this.apkFileName = 'app-release.apk',
    this.localApkName = 'update.apk',
    this.checkTimeout = const Duration(seconds: 20),
    this.downloadTimeout = const Duration(minutes: 5),
    this.allowHtmlFallback = true,
    this.backgroundDownload = false,
    this.labels = const UpdateLabels(),
  });

  /// Method channel used for natively handled operations. This must match the
  /// bundled Android plugin, so as a first-party plugin we own this default.
  static const String defaultMethodChannelName = 'flutter_github_updater';

  final String owner;
  final String repo;
  final String methodChannelName;
  final String apkFileName;
  final String localApkName;
  final Duration checkTimeout;
  final Duration downloadTimeout;

  /// When true (default), a failed/rate-limited/404 response from the GitHub
  /// REST API falls back to following the `github.com/<owner>/<repo>/
  /// releases/latest` redirect, which is not rate-limited the same way. This
  /// keeps the update check working when the anonymous API limit is exhausted.
  final bool allowHtmlFallback;

  /// When true, tapping "Update" enqueues a system-level download through
  /// DownloadManager instead of downloading inside the dialog. The download
  /// keeps running if the app is backgrounded or killed, a progress
  /// notification is shown, the dialog closes and the app minimizes, and the
  /// bundled receiver posts an "Update ready" notification on completion whose
  /// tap opens the installer. Repeated prompts are suppressed while a download
  /// for the same version is already enqueued.
  final bool backgroundDownload;

  final UpdateLabels labels;

  String get latestReleaseUrl =>
      'https://api.github.com/repos/$owner/$repo/releases/latest';
}

class UpdateLabels {
  const UpdateLabels({
    this.updateAvailable = 'Update Available',
    this.updateDescription = 'A new version (v%s) is available.',
    this.downloading = 'Downloading update...',
    this.downloadComplete = 'Download complete — tap Install.',
    this.downloadFailed = 'Download failed. Check your connection.',
    this.installNow = 'Install Now',
    this.installWaiting = 'Please wait...',
    this.installFailed = 'Installation failed. Try again.',
    this.installPermissionHint =
      'Allow "Install unknown apps", then tap Update again.',
    this.later = 'Later',
    this.updateButton = 'Update',
  });

  final String updateAvailable;
  final String updateDescription;
  final String downloading;
  final String downloadComplete;
  final String downloadFailed;
  final String installNow;
  final String installWaiting;
  final String installFailed;
  final String installPermissionHint;
  final String later;
  final String updateButton;
}
