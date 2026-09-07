import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'github_update_service.dart';
import 'update_config.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.config,
    required this.info,
    required this.tag,
  });

  final UpdateConfig config;
  final UpdateInfo info;
  final String tag;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  bool _installing = false;
  bool _downloaded = false;
  double _progress = 0;
  String _status = '';
  bool _resumedFromBackground = false;

  late final GithubUpdateService _service;

  @override
  void initState() {
    super.initState();
    _service = GithubUpdateService(widget.config);
    _checkExistingApk();
  }

  Future<void> _checkExistingApk() async {
    try {
      final file = await _service.apkFile();
      if (!await file.exists()) return;
      final done = await _service.wasDownloadComplete(widget.tag);
      if (done) {
        if (!mounted) return;
        setState(() {
          _downloaded = true;
          _status = widget.config.labels.downloadComplete;
        });
      } else {
        if (!mounted || _resumedFromBackground) return;
        _resumedFromBackground = true;
        _downloadAndInstall();
      }
    } catch (_) {}
  }

  void _dismiss() {
    _service.setDismissed(widget.tag);
    Navigator.of(context).pop();
  }

  Future<void> _downloadAndInstall() async {
    if (_downloaded) {
      await _install();
      return;
    }

    // Defensive pre-flight: if the native permission check throws or the
    // platform doesn't answer, fail soft (open install settings + show hint)
    // instead of stalling the dialog in its initial state.
    bool canInstall;
    try {
      canInstall = await _service.channel
              .invokeMethod<bool>('canRequestPackageInstalls') ??
          false;
    } catch (_) {
      canInstall = false;
    }

    if (!canInstall) {
      try {
        await _service.channel.invokeMethod('openInstallSettings');
      } catch (_) {}
      if (!mounted) return;
      setState(() => _status = widget.config.labels.installPermissionHint);
      return;
    }

    if (!mounted) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = widget.config.labels.downloading;
    });

    try {
      final file = await _service.apkFile();
      final req =
          http.Request('GET', Uri.parse(widget.info.downloadUrl));
      final res = await req.send().timeout(widget.config.downloadTimeout);
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (mounted) {
          setState(() {
            _progress = total > 0 ? received / total : 0;
          });
        }
      }
      await sink.close();
      await _service.markDownloadComplete(widget.tag);
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloaded = true;
        _status = widget.config.labels.downloadComplete;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloaded = false;
        _status = widget.config.labels.downloadFailed;
      });
    }
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _status = widget.config.labels.installWaiting;
    });
    try {
      final file = await _service.apkFile();
      final ok = await _service.channel
          .invokeMethod<bool>('installApk', {'path': file.path});
      if (ok == true && mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _status = widget.config.labels.installFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = widget.config.labels;

    return AlertDialog(
      title: Text(l.updateAvailable),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.updateDescription.replaceAll('%s', widget.info.version)),
          if (widget.info.releaseNotes?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              widget.info.releaseNotes!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            // Indeterminate bar the moment download starts (progress == 0),
            // then determinate once the first bytes arrive — never a silent
            // freeze while the download runs.
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_status,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary)),
          ],
        ],
      ),
      actions: [
        if (!_downloading && !_installing)
          TextButton(onPressed: _dismiss, child: Text(l.later)),
        FilledButton(
          onPressed:
              _downloading || _installing ? null : _downloadAndInstall,
          child: Text(_installing
              ? l.installWaiting
              : _downloaded
                  ? l.installNow
                  : l.updateButton),
        ),
      ],
    );
  }
}
