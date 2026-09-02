import 'package:flutter/material.dart';

import 'github_update_service.dart';
import 'update_config.dart';
import 'update_dialog.dart';

/// Extension on [BuildContext] for convenient update checking.
extension GithubUpdater on BuildContext {
  /// Checks for updates and shows a dialog if available.
  Future<void> checkForGithubUpdate(UpdateConfig config) async {
    final service = GithubUpdateService(config);
    final latest = await service.fetchLatestRelease();
    if (latest == null) return;
    if (!await service.isUpdateAvailable(latest)) return;
    final tag = 'v${latest.version}+${latest.buildNumber}';
    if (await service.wasDismissed(tag)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: this,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(config: config, info: latest, tag: tag),
    );
  }
}
