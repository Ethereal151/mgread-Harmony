import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/shared/presentation/widgets/app_page_backdrop.dart';

void main() {
  testWidgets('uses the theme page background for every primary tab', (WidgetTester tester) async {
    for (final AppPageBackdropStyle style in AppPageBackdropStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AppPageBackdrop(
            style: style,
            child: const SizedBox(key: Key('page-content')),
          ),
        ),
      );

      expect(find.byKey(const Key('page-content')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
        tester.widget<ColoredBox>(find.byKey(const Key('app-page-backdrop-surface'))).color,
        AppThemeTokens.of(tester.element(find.byKey(const Key('page-content')))).pageBackground,
      );
      final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(find.byType(AnnotatedRegion<SystemUiOverlayStyle>));
      final tokens = AppThemeTokens.of(tester.element(find.byKey(const Key('page-content'))));
      expect(overlay.value.statusBarColor, style == AppPageBackdropStyle.home ? tokens.featureSurface : tokens.pageBackground);
      expect(overlay.value.systemNavigationBarColor, tokens.pageBackground);
    }
  });

  testWidgets('keeps the cool-black background exact without an image layer', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(color: AppDarkThemeColor.coolBlack),
        home: AppPageBackdrop(
          style: AppPageBackdropStyle.discover,
          child: const SizedBox(key: Key('page-content')),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(tester.widget<ColoredBox>(find.byKey(const Key('app-page-backdrop-surface'))).color, const Color(0xFF000000));
  });
}
