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

  Future<UpdateInfo?> fetchLatestRelease() async {
    try {
      final res = await http
          .get(Uri.parse(config.latestReleaseUrl))
          .timeout(config.checkTimeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return null;

      final tag = (body['tag_name'] as String?) ?? '';
      final clean = tag.startsWith('v') ? tag.substring(1) : tag;
      final parts = clean.split('+');
      final version = parts.isNotEmpty ? parts.first : clean;
      final buildNumber =
          parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

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
    } catch (_) {
      return null;
    }
  }

  Future<bool> isUpdateAvailable(UpdateInfo latest) async {
    if (latest.buildNumber <= 0 || latest.downloadUrl.isEmpty) return false;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      return latest.buildNumber > current;
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
}
