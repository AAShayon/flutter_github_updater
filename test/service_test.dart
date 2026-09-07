import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_github_updater/flutter_github_updater.dart';

void main() {
  group('UpdateConfig', () {
    test('generates correct latestReleaseUrl', () {
      const config = UpdateConfig(
        owner: 'testuser',
        repo: 'test_releases',
      );
      expect(
        config.latestReleaseUrl,
        'https://api.github.com/repos/testuser/test_releases/releases/latest',
      );
    });

    test('uses custom channel name', () {
      const config = UpdateConfig(
        owner: 'user',
        repo: 'repo',
        methodChannelName: 'com.custom.app/updater',
      );
      expect(config.methodChannelName, 'com.custom.app/updater');
    });

    test('defaults for labels are non-empty', () {
      const labels = UpdateLabels();
      expect(labels.updateAvailable, isNotEmpty);
      expect(labels.downloading, isNotEmpty);
      expect(labels.installNow, isNotEmpty);
      expect(labels.later, isNotEmpty);
      expect(labels.updateButton, isNotEmpty);
    });

    test('html fallback enabled and timeout default to 20s', () {
      const config = UpdateConfig(owner: 'u', repo: 'r');
      expect(config.allowHtmlFallback, isTrue);
      expect(config.checkTimeout, const Duration(seconds: 20));
    });
  });

  group('parseTag', () {
    test('parses v1.2.3+45', () {
      expect(GithubUpdateService.parseTag('v1.2.3+45'), ('1.2.3', 45));
    });
    test('parses 1.2.3+45 without v prefix', () {
      expect(GithubUpdateService.parseTag('1.2.3+45'), ('1.2.3', 45));
    });
    test('no +build yields buildNumber 0', () {
      expect(GithubUpdateService.parseTag('v1.2.3'), ('1.2.3', 0));
      expect(GithubUpdateService.parseTag('2.0.0'), ('2.0.0', 0));
    });
    test('unparsable build part yields 0', () {
      expect(GithubUpdateService.parseTag('v1.2.3+abc'), ('1.2.3', 0));
    });
  });

  group('compareVersions', () {
    test('detects newer version', () {
      expect(GithubUpdateService.compareVersions('1.2.4', '1.2.3'),
          greaterThan(0));
    });
    test('detects older version', () {
      expect(GithubUpdateService.compareVersions('1.2.3', '1.2.4'),
          lessThan(0));
    });
    test('equal versions', () {
      expect(GithubUpdateService.compareVersions('1.2.3', '1.2.3'), 0);
    });
    test('numeric comparison not lexicographic', () {
      expect(GithubUpdateService.compareVersions('1.10.0', '1.9.0'),
          greaterThan(0));
    });
    test('handles differing segment counts', () {
      expect(GithubUpdateService.compareVersions('2.0', '2.0.0'), 0);
    });
  });

  group('GithubUpdateService', () {
    test('fetchLatestRelease returns null on network error', () async {
      const config = UpdateConfig(
        owner: 'nonexistent_user_123456789',
        repo: 'nonexistent_repo_123456789',
      );
      final service = GithubUpdateService(config);
      final result = await service.fetchLatestRelease();
      expect(result, isNull);
    });

    test('isUpdateAvailable returns false when buildNumber is 0', () async {
      const config = UpdateConfig(owner: 'u', repo: 'r');
      final service = GithubUpdateService(config);
      final info = UpdateInfo(
        version: '1.0.0',
        buildNumber: 0,
        downloadUrl: 'https://example.com/app.apk',
      );
      expect(await service.isUpdateAvailable(info), isFalse);
    });

    test('isUpdateAvailable returns false when downloadUrl is empty', () async {
      const config = UpdateConfig(owner: 'u', repo: 'r');
      final service = GithubUpdateService(config);
      final info = UpdateInfo(
        version: '1.0.0',
        buildNumber: 5,
        downloadUrl: '',
      );
      expect(await service.isUpdateAvailable(info), isFalse);
    });

    test('UpdateInfo holds fields correctly', () {
      const info = UpdateInfo(
        version: '2.1.0',
        buildNumber: 12,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: 'Bug fixes',
      );
      expect(info.version, '2.1.0');
      expect(info.buildNumber, 12);
      expect(info.downloadUrl, 'https://example.com/app.apk');
      expect(info.releaseNotes, 'Bug fixes');
    });

    test('UpdateInfo with null releaseNotes', () {
      const info = UpdateInfo(
        version: '1.0.0',
        buildNumber: 1,
        downloadUrl: 'https://example.com/app.apk',
      );
      expect(info.releaseNotes, isNull);
    });
  });

  group('UpdateLabels', () {
    test('custom labels override defaults', () {
      const labels = UpdateLabels(
        updateAvailable: 'Custom Update Available',
        updateButton: 'Install Now Please',
        later: 'No Thanks',
      );
      expect(labels.updateAvailable, 'Custom Update Available');
      expect(labels.updateButton, 'Install Now Please');
      expect(labels.later, 'No Thanks');
      // Non-overridden labels still have defaults
      expect(labels.downloading, isNotEmpty);
    });

    test('default labels are all non-empty', () {
      const labels = UpdateLabels();
      expect(labels.updateAvailable, isNotEmpty);
      expect(labels.updateDescription, isNotEmpty);
      expect(labels.downloading, isNotEmpty);
      expect(labels.downloadComplete, isNotEmpty);
      expect(labels.downloadFailed, isNotEmpty);
      expect(labels.installNow, isNotEmpty);
      expect(labels.installWaiting, isNotEmpty);
      expect(labels.installFailed, isNotEmpty);
      expect(labels.installPermissionHint, isNotEmpty);
      expect(labels.later, isNotEmpty);
      expect(labels.updateButton, isNotEmpty);
    });
  });
}
