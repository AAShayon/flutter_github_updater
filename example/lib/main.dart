import 'package:flutter/material.dart';
import 'package:flutter_github_updater/flutter_github_updater.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GitHub Updater Example',
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = 'Idle';

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    setState(() => _status = 'Checking for updates...');

    // ──────────────────────────────────────────────────────
    // REPLACE these with YOUR GitHub username and releases repo name
    // ──────────────────────────────────────────────────────
    const config = UpdateConfig(
      owner: 'YOUR_GITHUB_USERNAME',   // ← replace
      repo: 'YOUR_RELEASES_REPO',      // ← replace
    );

    final service = GithubUpdateService(config);
    final latest = await service.fetchLatestRelease();

    if (latest == null) {
      setState(() => _status = 'No release found or network error.');
      return;
    }

    if (!await service.isUpdateAvailable(latest)) {
      setState(() => _status = 'Already up-to-date (v${latest.version}).');
      return;
    }

    setState(() => _status = 'Update available: v${latest.version}');

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(
        config: config,
        info: latest,
        tag: 'v${latest.version}+${latest.buildNumber}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub Updater Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.system_update, size: 64),
            const SizedBox(height: 16),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _checkForUpdate,
              icon: const Icon(Icons.refresh),
              label: const Text('Check for Update'),
            ),
          ],
        ),
      ),
    );
  }
}
