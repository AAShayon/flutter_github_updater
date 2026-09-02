/// Entry point for `flutter_github_updater:setup`.
///
/// Delegates to the implementation in `tool/setup.dart`.
///
/// Usage:
/// ```
/// dart run flutter_github_updater:setup
/// ```
library;

import '../tool/setup.dart' as setup;

void main(List<String> args) => setup.main(args);
