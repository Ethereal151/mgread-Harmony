import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/features/plugins/presentation/data_source_management_sheets.dart';

void main() {
  testWidgets('native runtime build exposes the Rust data-source entry', (tester) async {
    DataSourceImportChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () async => result = await showDataSourceImportSheet(context), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('data-source-add-native')), findsOneWidget);
    expect(find.text('原生数据源'), findsOneWidget);
    expect(find.byKey(const Key('data-source-add-collection')), findsNothing);
    await tester.tap(find.byKey(const Key('data-source-add-native')));
    await tester.pumpAndSettle();
    expect(result, DataSourceImportChoice.native);
  });
}
