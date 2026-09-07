import 'package:flutter/material.dart';

import 'github_update_service.dart';
import 'update_config.dart';
import 'update_dialog.dart';

/// Extension on [BuildContext] for convenient update checking.
extension GithubUpdater on BuildContext {
  /// Guards against a second prompt being stacked on top of an already-open
  /// one (the usual cause of "nothing happened / tap twice" when the check
  /// fires again while a dialog is showing).
  static bool _promptOpen = false;

  /// Checks for updates and shows a dialog if available.
  ///
  /// Pass `force: true` for a manual "Check for update" action — it ignores a
  /// previous "Later" dismissal and always offers the update again when a newer
  /// build exists.
  Future<void> checkForGithubUpdate(UpdateConfig config, {bool force = false}) async {
    final service = GithubUpdateService(config);
    final latest = await service.fetchLatestRelease();
    if (latest == null) return;
    if (!await service.isUpdateAvailable(latest)) return;
    final tag = latest.buildNumber > 0
        ? 'v${latest.version}+${latest.buildNumber}'
        : 'v${latest.version}';
    if (!force && await service.wasDismissed(tag)) return;

    // Background mode: a download for this version is already enqueued or
    // finished. If it's still downloading the notification flow owns it — never
    // prompt or re-download. If it's finished but not installed, start the
    // install right away (the app is in the foreground here, so this works).
    if (config.backgroundDownload) {
      final status = await service.backgroundUpdateStatus(tag);
      if (status.downloading) return;
      if (status.downloaded) {
        await service.installDownloadedApk();
        return;
      }
    }

    if (_promptOpen) return;
    if (!mounted) return;
    _promptOpen = true;
    try {
      await showDialog<void>(
        context: this,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(config: config, info: latest, tag: tag),
      );
    } finally {
      _promptOpen = false;
    }
  }
}
