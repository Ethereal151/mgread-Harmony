import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mg_read/app/app.dart';
import 'package:mg_read/core/settings/settings.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first-run home matches the light empty bookshelf design', (WidgetTester tester) async {
    final settings = AppSettingsManager(store: _MemorySettingsStore(), registry: AppSettingKeys.registry);
    await settings.initialize();
    addTearDown(settings.close);
    await tester.pumpWidget(ProviderScope(overrides: [appSettingsProvider.overrideWithValue(settings)], child: const MgReadApp()));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsAtLeastNWidgets(1));
    expect(find.text('开始你的阅读旅程'), findsNothing);
    expect(find.text('当前还没有阅读记录'), findsNothing);
    expect(find.text('欢迎来到 MgRead'), findsOneWidget);
    expect(find.text('三步开启阅读'), findsOneWidget);
    expect(find.text('去发现好书'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('library_first_run_light');
  });
}

final class _MemorySettingsStore implements SettingsStore {
  @override
  Future<List<SettingsDocument>> loadAll(Iterable<SettingsDocumentDefinition> documents) async => const <SettingsDocument>[];

  @override
  Future<List<SettingsDocument>> writeAll(List<SettingsDocument> documents) async => documents;

  @override
  Future<void> close() async {}
}
