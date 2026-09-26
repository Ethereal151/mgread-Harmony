/// Verifies window metrics survive the root and nested SafeAreas consume them once.
/// These widget checks do not replace HarmonyOS device validation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read/app/app_theme.dart';

void main() {
  for (final isOhos in <bool>[true, false]) {
    testWidgets('preserves safe areas through rotation and keyboard: ohos=$isOhos', (tester) async {
      for (final insets in <MediaQueryData>[
        const MediaQueryData(padding: EdgeInsets.fromLTRB(3, 64, 5, 56), viewPadding: EdgeInsets.fromLTRB(3, 64, 5, 56)),
        const MediaQueryData(padding: EdgeInsets.fromLTRB(64, 0, 24, 16), viewPadding: EdgeInsets.fromLTRB(64, 0, 24, 16)),
        const MediaQueryData(
          padding: EdgeInsets.fromLTRB(3, 64, 5, 0),
          viewPadding: EdgeInsets.fromLTRB(3, 64, 5, 56),
          viewInsets: EdgeInsets.only(bottom: 320),
        ),
      ]) {
        final metrics = AppSpacing.normalizeWindowInsets(insets, isOhos: isOhos);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: metrics,
              child: SafeArea(
                child: SafeArea(
                  child: Builder(
                    builder: (context) {
                      expect(MediaQuery.paddingOf(context), EdgeInsets.zero);
                      expect(MediaQuery.viewInsetsOf(context), insets.viewInsets);
                      return const SizedBox.expand(key: Key('content'));
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        expect(metrics.viewPadding, insets.viewPadding);
        expect(tester.getTopLeft(find.byKey(const Key('content'))), Offset(insets.padding.left, insets.padding.top));
        expect(
          tester.getSize(find.byKey(const Key('content'))).height,
          tester.view.physicalSize.height / tester.view.devicePixelRatio - insets.padding.vertical,
        );
      }
    });
  }
}
