/// Zero-cost in-app auto-updater for Flutter Android apps via GitHub Releases.
///
/// ## Usage
///
/// ```dart
/// import 'package:flutter_github_updater/flutter_github_updater.dart';
///
/// // One-time config
/// final config = UpdateConfig(
///   owner: 'myuser',
///   repo: 'myapp_releases',
/// );
///
/// // Check on every launch
/// final service = GithubUpdateService(config);
/// await service.promptIfUpdateAvailable(context);
/// ```
library flutter_github_updater;

export 'src/update_config.dart';
export 'src/github_update_service.dart';
export 'src/update_dialog.dart';
export 'src/extensions.dart';
