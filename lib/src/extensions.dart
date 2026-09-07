import 'package:flutter/material.dart';

import 'github_update_service.dart';
import 'update_config.dart';
import 'update_dialog.dart';

/// Extension on [BuildContext] for convenient update checking.
extension GithubUpdater on BuildContext {
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
    if (!mounted) return;
    await showDialog<void>(
      context: this,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(config: config, info: latest, tag: tag),
    );
  }
}
