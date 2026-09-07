import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_config.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    this.releaseNotes,
  });

  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String? releaseNotes;
}

class GithubUpdateService {
  GithubUpdateService(this.config);

  final UpdateConfig config;

  static const String _dismissedPrefix = 'gh_upd_dismissed_';
  static const String _donePrefix = 'gh_upd_done_';

  /// Parses a GitHub release tag into (version, buildNumber). Tags are either
  /// `v1.2.3`, `1.2.3`, `v1.2.3+45` or `1.2.3+45`. A missing `+build` part
  /// yields buildNumber 0.
  static (String version, int buildNumber) parseTag(String tag) {
    final clean = tag.startsWith('v') ? tag.substring(1) : tag;
    final parts = clean.split('+');
    final version = parts.isNotEmpty ? parts.first : clean;
    final buildNumber = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (version, buildNumber);
  }

  /// Numeric segment comparison of `major.minor.patch`-style versions.
  /// Returns >0 when [a] is newer than [b], <0 when older, 0 when equal.
  static int compareVersions(String a, String b) {
    List<int> segments(String v) =>
        v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pa = segments(a);
    final pb = segments(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }

  Future<UpdateInfo?> fetchLatestRelease() async {
    try {
      final res = await http
          .get(Uri.parse(config.latestReleaseUrl))
          .timeout(config.checkTimeout);
      if (res.statusCode != 200) {
        return await _fetchViaHtmlFallback();
      }
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) {
        return await _fetchViaHtmlFallback();
      }
      final info = _parseApiRelease(body);
      if (info == null) {
        return await _fetchViaHtmlFallback();
      }
      return info;
    } catch (_) {
      return await _fetchViaHtmlFallback();
    }
  }

  UpdateInfo? _parseApiRelease(Map<String, dynamic> body) {
    final tag = (body['tag_name'] as String?) ?? '';
    if (tag.isEmpty) return null;
    final (version, buildNumber) = parseTag(tag);

    String? url;
    final assets = body['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is Map<String, dynamic>) {
          final name = (a['name'] as String?) ?? '';
          if (name == config.apkFileName || name.endsWith('.apk')) {
            url = a['browser_download_url'] as String?;
            break;
          }
        }
      }
    }

    return UpdateInfo(
      version: version,
      buildNumber: buildNumber,
      downloadUrl: url ?? '',
      releaseNotes: body['body'] as String?,
    );
  }

  /// Fallback used when api.github.com is slow, rate-limited (403) or 404s.
  /// Follows the `github.com/<owner>/<repo>/releases/latest` redirect and reads
  /// the tag from the destination URL, then constructs the download URL.
  Future<UpdateInfo?> _fetchViaHtmlFallback() async {
    if (!config.allowHtmlFallback) return null;
    try {
      final uri = Uri.parse(
        'https://github.com/${config.owner}/${config.repo}/releases/latest',
      );
      final res = await http.get(uri).timeout(config.checkTimeout);
      if (res.statusCode != 200) return null;
      final finalUrl = res.request?.url;
      if (finalUrl == null) return null;
      final segments = finalUrl.pathSegments;
      if (segments.isEmpty) return null;
      final tag = segments.last;
      final (version, buildNumber) = parseTag(tag);

      final downloadUrl = 'https://github.com/${config.owner}/${config.repo}'
          '/releases/download/$tag/${config.apkFileName}';

      return UpdateInfo(
        version: version,
        buildNumber: buildNumber,
        downloadUrl: downloadUrl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> isUpdateAvailable(UpdateInfo latest) async {
    if (latest.downloadUrl.isEmpty) return false;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      if (latest.buildNumber > 0) {
        return latest.buildNumber > currentBuild;
      }
      // No +build in the release tag — fall back to version comparison so a
      // tag like `v1.2.3` is still detected as an update.
      return compareVersions(latest.version, info.version) > 0;
    } catch (_) {
      return false;
    }
  }

  Future<File> apkFile() async {
    final dir = await getExternalStorageDirectory();
    return File('${dir!.path}/${config.localApkName}');
  }

  MethodChannel get channel => MethodChannel(config.methodChannelName);

  Future<bool> wasDismissed(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_dismissedPrefix$tag') ?? false;
  }

  Future<void> setDismissed(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_dismissedPrefix$tag', true);
  }

  Future<void> markDownloadComplete(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_donePrefix$tag', true);
  }

  Future<bool> wasDownloadComplete(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_donePrefix$tag') ?? false;
  }

  /// Enqueues a system-level background download of [url] tagged with [tag].
  /// DownloadManager keeps running even if the app is killed; when it finishes,
  /// the bundled native receiver posts an "update ready" notification whose tap
  /// opens the package installer. Returns the system download id on success.
  Future<int?> startBackgroundDownload(String url, String tag) async {
    try {
      return await channel.invokeMethod<int>('startBackgroundDownload', {
        'url': url,
        'tag': tag,
      });
    } catch (_) {
      return null;
    }
  }

  /// Returns whether a background download for [tag] is still in progress
  /// (downloading) or has finished successfully (downloaded).
  Future<({bool downloading, bool downloaded})> backgroundUpdateStatus(
    String tag,
  ) async {
    try {
      final map = await channel.invokeMapMethod<String, dynamic>(
        'backgroundUpdateStatus',
        {'tag': tag},
      );
      return (
        downloading: map?['downloading'] == true,
        downloaded: map?['downloaded'] == true,
      );
    } catch (_) {
      return (downloading: false, downloaded: false);
    }
  }

  /// Absolute path of the native `update.apk` file (may not exist yet).
  Future<String?> apkNativePath() async {
    try {
      return await channel.invokeMethod<String>('apkFilePath');
    } catch (_) {
      return null;
    }
  }
}
