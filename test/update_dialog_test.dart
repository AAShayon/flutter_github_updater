import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_github_updater/flutter_github_updater.dart';

void main() {
  Widget buildTestWidget({
    UpdateLabels? labels,
    bool downloaded = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return UpdateDialog(
              config: UpdateConfig(
                owner: 'test',
                repo: 'test_releases',
                labels: labels ?? const UpdateLabels(),
              ),
              info: const UpdateInfo(
                version: '2.0.0',
                buildNumber: 10,
                downloadUrl: 'https://example.com/app.apk',
                releaseNotes: 'Bug fixes and improvements',
              ),
              tag: 'v2.0.0+10',
            );
          },
        ),
      ),
    );
  }

  group('UpdateDialog', () {
    testWidgets('shows update available title', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Update Available'), findsOneWidget);
    });

    testWidgets('shows version number in description', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(
        find.textContaining('2.0.0'),
        findsOneWidget,
      );
    });

    testWidgets('shows release notes', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Bug fixes and improvements'), findsOneWidget);
    });

    testWidgets('shows Update and Later buttons', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('custom Bengali labels render', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        labels: const UpdateLabels(
          updateAvailable: 'নতুন সংস্করণ পাওয়া গেছে',
          updateButton: 'আপডেট করুন',
          later: 'পরে',
          updateDescription: 'সংস্করণ v%s পাওয়া গেছে।',
        ),
      ));
      expect(find.text('নতুন সংস্করণ পাওয়া গেছে'), findsOneWidget);
      expect(find.text('আপডেট করুন'), findsOneWidget);
      expect(find.text('পরে'), findsOneWidget);
      expect(find.textContaining('2.0.0'), findsOneWidget);
    });

    testWidgets('no release notes section when notes is null', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return UpdateDialog(
                config: const UpdateConfig(
                  owner: 'test',
                  repo: 'test',
                ),
                info: const UpdateInfo(
                  version: '1.0.0',
                  buildNumber: 5,
                  downloadUrl: 'https://example.com/app.apk',
                  // releaseNotes is null
                ),
                tag: 'v1.0.0+5',
              );
            },
          ),
        ),
      ));
      // Should not find any release notes text
      expect(find.textContaining('Bug fixes'), findsNothing);
      // But title and buttons should still be there
      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('dialog is not dismissible by tapping outside', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Try to tap outside the dialog (on the scaffold)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Dialog should still be there
      expect(find.text('Update Available'), findsOneWidget);
    });
  });
}
