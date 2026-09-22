import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/features/profile/presentation/feedback_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS feedback page renders its browser handoff', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: FeedbackPage(onBackRequested: () {}, onDestinationRequested: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feedback-page-content')), findsOneWidget);
    expect(find.text('当前不提供应用内提交'), findsOneWidget);
    expect(find.text(ohosGithubFeedbackUrl), findsOneWidget);
    expect(find.byKey(const Key('feedback-open-github')), findsOneWidget);
    await tester.tap(find.byKey(const Key('feedback-open-github')));
    await tester.pump(const Duration(milliseconds: 500));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
