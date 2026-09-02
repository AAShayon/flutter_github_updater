/// Configuration for [GithubUpdateService].
class UpdateConfig {
  const UpdateConfig({
    required this.owner,
    required this.repo,
    this.methodChannelName = 'com.example.app/updater',
    this.apkFileName = 'app-release.apk',
    this.localApkName = 'update.apk',
    this.checkTimeout = const Duration(seconds: 10),
    this.downloadTimeout = const Duration(minutes: 5),
    this.labels = const UpdateLabels(),
  });

  final String owner;
  final String repo;
  final String methodChannelName;
  final String apkFileName;
  final String localApkName;
  final Duration checkTimeout;
  final Duration downloadTimeout;
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
    this.installPermissionHint = 'Allow the permission, then tap Install.',
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
