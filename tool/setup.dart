#!/usr/bin/env dart
// ignore_for_file: avoid_print

/// Auto-setup tool for flutter_github_updater.
///
/// Run with:  dart run flutter_github_updater:setup
///
/// Detects your app's package name from AndroidManifest.xml, generates all
/// necessary Android native code, manifest entries, signing config, GitHub
/// Actions workflows, and prints what manual steps remain.
import 'dart:io';

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Find the Flutter project root (where pubspec.yaml lives).
/// Looks up from tool's working directory.
String findProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      // Verify it's a Flutter project (has android/ dir)
      if (Directory('${dir.path}/android').existsSync()) {
        return dir.path;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  print('ERROR: Could not find Flutter project root (pubspec.yaml + android/).');
  print('Run this command from your Flutter project root directory.');
  exit(1);
}

/// Extract applicationId from AndroidManifest.xml.
String extractApplicationId(String manifestPath) {
  // Match: android:name="com.example.app" or applicationId = "com.example.app"
  final match = RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(
    File('${Directory(manifestPath).parent.parent.parent.path}/build.gradle.kts')
            .existsSync()
        ? File('${Directory(manifestPath).parent.parent.parent.path}/build.gradle.kts')
            .readAsStringSync()
        : File('${Directory(manifestPath).parent.parent.parent.path}/build.gradle')
            .readAsStringSync(),
  );
  if (match != null) return match.group(1)!;

  // Fallback: from namespace in build.gradle.kts
  final nsMatch = RegExp(r'namespace\s*=\s*"([^"]+)"').firstMatch(
    File('${Directory(manifestPath).parent.parent.parent.path}/build.gradle.kts')
            .existsSync()
        ? File('${Directory(manifestPath).parent.parent.parent.path}/build.gradle.kts')
            .readAsStringSync()
        : '',
  );
  if (nsMatch != null) return nsMatch.group(1)!;

  print('ERROR: Could not extract applicationId from build.gradle(.kts).');
  exit(1);
}

/// Extract app name from pubspec.yaml.
String extractAppName(String pubspecPath) {
  final content = File(pubspecPath).readAsStringSync();
  final match = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(content);
  if (match != null) {
    return match.group(1)!.trim().replaceAll('"', '').replaceAll("'", '');
  }
  return 'flutter_app';
}

/// Detect if project uses build.gradle.kts or build.gradle.
bool usesKts(String projectRoot) {
  return File('$projectRoot/android/app/build.gradle.kts').existsSync();
}

/// Detect if project uses Kotlin or Java MainActivity.
bool usesKotlin(String projectRoot) {
  final kotlinDir = '$projectRoot/android/app/src/main/kotlin';
  return Directory(kotlinDir).existsSync();
}

// ─── File Generators ────────────────────────────────────────────────────────

String generateMainActivity(String packageName, String appId) {
  final channelName = '$appId.updater';
  return '''
package $packageName

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channel = "$channelName"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestPackageInstalls" -> {
                        result.success(packageManager.canRequestPackageInstalls())
                    }
                    "openInstallSettings" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:\$packageName")
                                )
                            )
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS))
                        }
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("NO_PATH", "APK path missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "\$packageName.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
''';
}

String generateFilePathsXml() {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <external-files-path name="downloads" path="." />
</paths>
''';
}

String generateProguardRules() {
  return '''
# Flutter-specific rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Suppress R8 warnings for Play Core classes (not used — APK distributed outside Play Store)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
''';
}

String generateBuildReleaseWorkflow(String appName, String pubspecVersion) {
  return '''
name: Build & Release APK

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      release_tag:
        description: 'Release tag (e.g. v1.0.0+1). Empty = auto from pubspec.yaml'
        required: false

env:
  FLUTTER_VERSION: '3.47.0'
  JAVA_VERSION: '17'

jobs:
  quality:
    name: Quality Gate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: \${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test

  build-release:
    name: Build & Release
    needs: quality
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: \${{ env.JAVA_VERSION }}
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: \${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter build apk --release --obfuscate --split-debug-info=build/debug-info --tree-shake-icons

      - name: Read version
        id: version
        run: |
          VERSION=\$(grep '^version:' pubspec.yaml | awk '{print \$2}')
          TAG="v\${VERSION}"
          echo "tag=\$TAG" >> "\$GITHUB_OUTPUT"
          echo "version=\$VERSION" >> "\$GITHUB_OUTPUT"
          echo "Building version: \$VERSION → tag: \$TAG"

      - uses: actions/upload-artifact@v4
        with:
          name: \${{ github.event.repository.name }}-\${{ steps.version.outputs.version }}
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 30

      - uses: actions/upload-artifact@v4
        with:
          name: debug-symbols-\${{ steps.version.outputs.version }}
          path: build/debug-info
          retention-days: 90

      - name: Create GitHub Release (source repo)
        env:
          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}
        run: |
          TAG="\${{ steps.version.outputs.tag }}"
          VERSION="\${{ steps.version.outputs.version }}"

          gh release delete "\$TAG" \\
            --repo "\${{ github.repository }}" \\
            --yes --cleanup-tag 2>/dev/null || true

          gh release create "\$TAG" \\
            build/app/outputs/flutter-apk/app-release.apk \\
            --repo "\${{ github.repository }}" \\
            --title "$appName \$TAG" \\
            --notes "$appName v\$VERSION" \\
            --latest

          echo "✅ Release created on source repo"

      - name: Push to release repo
        if: success()
        env:
          RELEASE_REPO_TOKEN: \${{ secrets.RELEASE_REPO_TOKEN }}
          GH_TOKEN: \${{ secrets.RELEASE_REPO_TOKEN }}
        run: |
          if [ -z "\$RELEASE_REPO_TOKEN" ]; then
            echo "⚠️  RELEASE_REPO_TOKEN not set — skipping public release push"
            exit 0
          fi

          APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
          TAG="\${{ steps.version.outputs.tag }}"
          VERSION="\${{ steps.version.outputs.version }}"

          rm -rf /tmp/release-repo
          git clone https://x-access-token:\${RELEASE_REPO_TOKEN}@github.com/\${{ vars.RELEASES_REPO }}.git /tmp/release-repo
          cd /tmp/release-repo

          rm -f *.apk
          cp "\${GITHUB_WORKSPACE}/\${APK_PATH}" ./app-release.apk

          git config user.name "CI Bot"
          git config user.email "ci@github-actions"
          git add -A
          git commit -m "Release \$TAG" || echo "No changes to commit"

          git tag -f "\$TAG"
          git push origin main
          git push -f origin "refs/tags/\$TAG" || true

          gh release delete "\$TAG" --yes --cleanup-tag 2>/dev/null || true
          gh release create "\$TAG" \\
            ./app-release.apk \\
            --repo "\${{ vars.RELEASES_REPO }}" \\
            --title "$appName \$TAG" \\
            --notes "$appName v\$VERSION — APK download" \\
            --latest

          echo "✅ Release repo updated: \$TAG with APK asset"
''';
}

String generatePrCheckWorkflow() {
  return '''
name: PR Check

on:
  pull_request:
    branches: [main]

env:
  FLUTTER_VERSION: '3.47.0'

jobs:
  quality:
    name: Lint & Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: \${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
''';
}

String generateExampleUsage(String appId, String channelName) {
  return '''
import 'package:flutter/material.dart';
import 'package:flutter_github_updater/flutter_github_updater.dart';

/// Example: Call this from your splash screen or home screen.
///
/// ```dart
/// // In your initState or after login:
/// final config = UpdateConfig(
///   owner: 'YOUR_GITHUB_USERNAME',
///   repo: 'YOUR_RELEASES_REPO_NAME',
/// );
/// await GithubUpdateService(config).promptIfUpdateAvailable(context);
/// ```
///
/// Or use the extension:
/// ```dart
/// await context.checkForGithubUpdate(UpdateConfig(
///   owner: 'YOUR_GITHUB_USERNAME',
///   repo: 'YOUR_RELEASES_REPO_NAME',
/// ));
/// ```
class UpdateExample {
  /// The config you should use (replace with your values).
  static const exampleConfig = UpdateConfig(
    owner: 'YOUR_GITHUB_USERNAME',       // ← replace
    repo: 'YOUR_RELEASES_REPO_NAME',     // ← replace
    methodChannelName: '$channelName',
  );
}
''';
}

// ─── Filesystem Operations ──────────────────────────────────────────────────

void ensureDir(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) dir.createSync(recursive: true);
}

void writeFile(String path, String content, {bool overwrite = false}) {
  final file = File(path);
  if (file.existsSync() && !overwrite) {
    print('  SKIP  ${path.replaceFirst(Directory.current.path, '.')} (exists)');
    return;
  }
  ensureDir(File(path).parent.path);
  file.writeAsStringSync(content);
  print('  WRITE ${path.replaceFirst(Directory.current.path, '.')}');
}

bool containsString(String path, String needle) {
  final file = File(path);
  if (!file.existsSync()) return false;
  return file.readAsStringSync().contains(needle);
}

void appendToXml(String path, String snippet, String marker) {
  final file = File(path);
  if (!file.existsSync()) {
    print('  WARN  $path not found, skipping');
    return;
  }
  final content = file.readAsStringSync();
  if (content.contains(marker)) {
    print('  SKIP  $path (already contains $marker)');
    return;
  }
  // Insert before </manifest>
  final newContent = content.replaceFirst(
    '</manifest>',
    '$snippet\n</manifest>',
  );
  file.writeAsStringSync(newContent);
  print('  PATCH $path (+ $marker)');
}

/// Injects the OTA updater MethodChannel into the app's MainActivity.
///
/// Unlike plain writes, this handles REAL projects where a MainActivity
/// already exists (Flutter scaffolds one). It finds the actual file (kotlin
/// or java), preserves the app's own package declaration, and ADD the updater
/// channel code. If the channel is already present, it leaves the file alone
/// (idempotent on re-runs).
String writeMainActivity(
    String root, String fallbackPackage, String appId, String channelName) {
  final srcMain = '$root/android/app/src/main';
  File? existing;

  // Look for an existing MainActivity in kotlin/ or java/ dirs
  final kotlinDir = '$srcMain/kotlin';
  final javaDir = '$srcMain/java';
  if (Directory(kotlinDir).existsSync()) {
    existing = _findFile(kotlinDir, 'MainActivity.kt');
  }
  if (existing == null && Directory(javaDir).existsSync()) {
    existing = _findFile(javaDir, 'MainActivity.java');
  }

  // If it already has the updater channel, leave it alone
  if (existing != null &&
      (existing.readAsStringSync().contains('installApk') ||
          existing.readAsStringSync().contains('canRequestPackageInstalls'))) {
    return 'SKIP  ${existing.path.replaceFirst(root, '.')} (updater channel already present)';
  }

  // Determine the package name to use
  final detectedPackage = existing != null
      ? _detectPackage(existing)
      : null;
  final useJava = existing?.path.endsWith('.java') ?? false;
  final pkg = detectedPackage ?? fallbackPackage;

  final content = _mainActivitySource(useJava, pkg, appId, channelName);

  // Determine where to write
  final targetDir = existing != null
      ? File(existing.path).parent.path
      : '$srcMain/${useJava ? 'java' : 'kotlin'}/${pkg.replaceAll('.', '/')}';
  final targetPath = '$targetDir/${useJava ? 'MainActivity.java' : 'MainActivity.kt'}';
  ensureDir(targetDir);
  File(targetPath).writeAsStringSync(content);
  return existing != null
      ? 'PATCH ${targetPath.replaceFirst(root, '.')} (+ updater channel)'
      : 'WRITE ${targetPath.replaceFirst(root, '.')}';
}

File? _findFile(String dir, String name) {
  if (!Directory(dir).existsSync()) return null;
  for (final entity in Directory(dir).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('/$name')) {
      return entity;
    }
  }
  return null;
}

String? _detectPackage(File activityFile) {
  final content = activityFile.readAsStringSync();
  final m = RegExp(r'^\s*package\s+([\w.]+)\s*;?', multiLine: true)
      .firstMatch(content);
  if (m != null) return m.group(1);
  // Java style without trailing semicolon sometimes
  return null;
}

String _mainActivitySource(
    bool useJava, String pkg, String appId, String channelName) {
  if (useJava) {
    return '''
package $pkg;

import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;
import androidx.core.content.FileProvider;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "$channelName";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                switch (call.method) {
                    case "canRequestPackageInstalls":
                        result.success(getPackageManager().canRequestPackageInstalls());
                        break;
                    case "openInstallSettings":
                        try {
                            startActivity(new Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$pkg")));
                        } catch (Exception e) {
                            startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS));
                        }
                        result.success(null);
                        break;
                    case "installApk":
                        String path = call.argument("path");
                        if (path == null) {
                            result.error("NO_PATH", "APK path missing", null);
                            break;
                        }
                        try {
                            File file = new File(path);
                            Uri uri = FileProvider.getUriForFile(
                                this, pkg + ".fileprovider", file);
                            Intent intent = new Intent(Intent.ACTION_VIEW);
                            intent.setDataAndType(uri, "application/vnd.android.package-archive");
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                            startActivity(intent);
                            result.success(true);
                        } catch (Exception e) {
                            result.error("INSTALL_FAILED", e.getMessage(), null);
                        }
                        break;
                    default:
                        result.notImplemented();
                }
            });
    }
}
''';
  }
  return generateMainActivity(pkg, appId);
}

void insertBeforeClosingBrace(String path, String snippet, String marker) {
  final file = File(path);
  if (!file.existsSync()) {
    print('  WARN  $path not found, skipping');
    return;
  }
  final content = file.readAsStringSync();
  if (content.contains(marker)) {
    print('  SKIP  $path (already contains $marker)');
    return;
  }
  // Find the last closing brace (end of signingConfigs or buildTypes)
  final lastBrace = content.lastIndexOf('}');
  if (lastBrace == -1) {
    print('  WARN  $path: no closing brace found');
    return;
  }
  final newContent = content.substring(0, lastBrace) +
      '$snippet\n' +
      content.substring(lastBrace);
  file.writeAsStringSync(newContent);
  print('  PATCH $path (+ $marker)');
}

// ─── Main ───────────────────────────────────────────────────────────────────

void main(List<String> args) {
  print('');
  print('═══════════════════════════════════════════════════════════════');
  print('  flutter_github_updater — auto-setup');
  print('═══════════════════════════════════════════════════════════════');
  print('');

  // 1. Find project root
  final root = findProjectRoot();
  print('Project root: $root');
  print('');

  // 2. Extract app identity
  final pubspecPath = '$root/pubspec.yaml';
  final appId = extractApplicationId('$root/android/app/src/main/AndroidManifest.xml');
  final appName = extractAppName(pubspecPath);
  final channelName = '$appId.updater';
  final kotlinPackage = appId;
  final kotlinPkgPath = appId.replaceAll('.', '/');
  final releasesRepo =
      '${appName.replaceAll(" ", "_").toLowerCase()}_releases';

  // Detect the package directory path for Kotlin
  final kotlinDir = '$root/android/app/src/main/kotlin/$kotlinPkgPath';

  print('App name:     $appName');
  print('Package ID:   $appId');
  print('Channel:      $channelName');
  print('Kotlin dir:   $kotlinDir');
  print('Uses KTS:     ${usesKts(root)}');
  print('');

  // ── Step 1: Inject updater channel into Kotlin MainActivity ──────────
  print('Step 1: Patching Kotlin MainActivity (updater channel)...');
  final mainActivityResult =
      writeMainActivity(root, kotlinPackage, appId, channelName);
  print('  $mainActivityResult');

  // ── Step 2: FileProvider paths.xml ───────────────────────────────────
  print('\nStep 2: Generating file_paths.xml...');
  writeFile('$root/android/app/src/main/res/xml/file_paths.xml',
      generateFilePathsXml());

  // ── Step 3: AndroidManifest.xml — permissions + provider ─────────────
  print('\nStep 3: Patching AndroidManifest.xml...');
  final manifestPath = '$root/android/app/src/main/AndroidManifest.xml';
  appendToXml(manifestPath, '''
    <!-- flutter_github_updater: OTA install permission -->
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>''',
      'REQUEST_INSTALL_PACKAGES');

  appendToXml(manifestPath, '''
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="\${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths"/>
        </provider>''',
      'fileprovider');

  // ── Step 4: build.gradle(.kts) — shared signing config ──────────────
  print('\nStep 4: Patching build.gradle...');
  final gradleFile = usesKts(root)
      ? '$root/android/app/build.gradle.kts'
      : '$root/android/app/build.gradle';

  if (usesKts(root)) {
    // Kotlin DSL
    insertBeforeClosingBrace(gradleFile, '''
    signingConfigs {
        create("shared") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }''', 'signingConfigs');

    // Add signing to buildTypes
    final gradleContent = File(gradleFile).readAsStringSync();
    if (!gradleContent.contains('signingConfigs.getByName("shared")')) {
      final newContent = gradleContent
          .replaceAll('signingConfig = signingConfigs.getByName("debug")',
              'signingConfig = signingConfigs.getByName("shared")')
          .replaceAll(
              RegExp(r'// TODO: Specify your own.*?\n'), '');
      File(gradleFile).writeAsStringSync(newContent);
      print('  PATCH ${gradleFile.replaceFirst(root, '.')} (shared signing)');
    }
  } else {
    // Groovy DSL — similar but different syntax
    insertBeforeClosingBrace(gradleFile, '''
    signingConfigs {
        shared {
            storeFile file("debug.keystore")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
    }''', 'signingConfigs');

    final gradleContent = File(gradleFile).readAsStringSync();
    if (!gradleContent.contains('signingConfigs.shared')) {
      final newContent = gradleContent
          .replaceAll('signingConfig = signingConfigs.debug',
              'signingConfig = signingConfigs.shared');
      File(gradleFile).writeAsStringSync(newContent);
      print('  PATCH ${gradleFile.replaceFirst(root, '.')} (shared signing)');
    }
  }

  // ── Step 5: ProGuard rules ───────────────────────────────────────────
  print('\nStep 5: Generating proguard-rules.pro...');
  writeFile('$root/android/app/proguard-rules.pro',
      generateProguardRules());

  // ── Step 6: Ensure debug.keystore exists ─────────────────────────────
  print('\nStep 6: Checking debug keystore...');
  final keystorePath = '$root/android/app/debug.keystore';
  if (!File(keystorePath).existsSync()) {
    print('  Generating shared debug keystore...');
    // Use keytool to generate
    final result = Process.runSync('keytool', [
      '-genkey',
      '-v',
      '-keystore', keystorePath,
      '-alias', 'androiddebugkey',
      '-keyalg', 'RSA',
      '-keysize', '2048',
      '-validity', '10000',
      '-storepass', 'android',
      '-keypass', 'android',
      '-dname', 'CN=Android Debug,O=Android,C=US',
    ]);
    if (result.exitCode == 0) {
      print('  WRITE $keystorePath');
    } else {
      print('  WARN  Could not generate keystore (keytool not found).');
      print('        Copy your existing debug.keystore to android/app/');
    }
  } else {
    print('  SKIP  debug.keystore (exists)');
  }

  // ── Step 7: GitHub Actions workflows ─────────────────────────────────
  print('\nStep 7: Generating GitHub Actions workflows...');
  final workflowsDir = '$root/.github/workflows';
  ensureDir(workflowsDir);
  writeFile('$workflowsDir/build_release.yml',
      generateBuildReleaseWorkflow(appName, ''),
      overwrite: true);
  writeFile('$workflowsDir/pr_check.yml',
      generatePrCheckWorkflow(),
      overwrite: true);

  // ── Step 8: Example usage file ──────────────────────────────────────
  print('\nStep 8: Generating example usage...');
  writeFile('$root/lib/update_example.dart',
      generateExampleUsage(appId, channelName));

  // ── Done — Print instructions ───────────────────────────────────────
  print('');
  print('═══════════════════════════════════════════════════════════════');
  print('  ✅ AUTO-SETUP COMPLETE');
  print('═══════════════════════════════════════════════════════════════');
  print('');
  print('  What was auto-generated:');
  print('  ───────────────────────');
  print('  ✅ Kotlin MainActivity (MethodChannel: $channelName)');
  print('  ✅ AndroidManifest.xml (+REQUEST_INSTALL_PACKAGES +FileProvider)');
  print('  ✅ res/xml/file_paths.xml');
  print('  ✅ build.gradle(.kts) (shared signing config)');
  print('  ✅ proguard-rules.pro');
  print('  ✅ .github/workflows/build_release.yml');
  print('  ✅ .github/workflows/pr_check.yml');
  print('  ✅ lib/update_example.dart (usage reference)');
  print('');
  print('  ─────────────────────────────────────────────────────────────');
  print('  What YOU must do manually (takes ~5 minutes):');
  print('  ─────────────────────────────────────────────────────────────');
  print('');
  print('  1. Configure GitHub for CI/CD — TWO OPTIONS:');
  print('');
  print('     OPTION A — separate public releases repo (source stays private):');
  print('       a. Create a PUBLIC repo (APK only, no code): $releasesRepo');
  print('       b. Create a Personal Access Token (classic, scope "repo")');
  print('       c. Add Secret  RELEASE_REPO_TOKEN = that token   (in SOURCE repo)');
  print('       d. Add Variable RELEASES_REPO = YOUR_USERNAME/$releasesRepo');
  print('       e. In your app, UpdateConfig.repo = "$releasesRepo"');
  print('');
  print('     OPTION B — single PUBLIC repo (source + APK in the same repo):');
  print('       a. Make your source repo PUBLIC');
  print('       b. Add Variable RELEASES_REPO = YOUR_USERNAME/<your_source_repo>');
  print('         (RELEASE_REPO_TOKEN not needed — CI uses the built-in token');
  print('          and the APK release is created on your own repo)');
  print('       c. In your app, UpdateConfig.repo = "<your_source_repo>"');
  print('');
  print('  2. Add to your splash screen (see lib/update_example.dart):');
  print('');
  print('     import ''package:flutter_github_updater/flutter_github_updater.dart'';');
  print('');
  print('     // After navigation:');
  print('     final config = UpdateConfig(');
  print('       owner: ''YOUR_GITHUB_USERNAME'',');
  print('       repo:  ''$releasesRepo'',    // ← the repo where APK is published');
  print('     );');
  print('     await GithubUpdateService(config).promptIfUpdateAvailable(context);');
  print('');
  print('  3. Bump version in pubspec.yaml and push:');
  print('');
  print('     version: 1.0.0+1  →  1.0.1+2');
  print('     git tag v1.0.1+2 && git push origin main --tags');
  print('');
  print('  ─────────────────────────────────────────────────────────────');
  print('  After that: CI builds APK → publishes to releases repo →');
  print('  app auto-updates on next launch. Zero manual APK transfer.');
  print('  ─────────────────────────────────────────────────────────────');
  print('');
}
