///
/// 职责：
/// - 验证鸿蒙系统栏安全区被收敛到共享手机布局契约。
/// - 确认非鸿蒙窗口指标和键盘 inset 不受影响。
///
/// 注意：
/// - 这里只验证纯布局指标变换，不替代真实鸿蒙设备验收。
///
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mg_read/app/app_theme.dart';

void main() {
  test('limits OHOS system insets to the shared phone layout contract', () {
    const MediaQueryData input = MediaQueryData(
      padding: EdgeInsets.fromLTRB(3, 64, 5, 56),
      viewPadding: EdgeInsets.fromLTRB(3, 64, 5, 56),
      viewInsets: EdgeInsets.only(bottom: 320),
    );

    final MediaQueryData output = AppSpacing.normalizeWindowInsets(input, isOhos: true);

    expect(output.padding, const EdgeInsets.fromLTRB(3, 0, 5, 0));
    expect(output.viewPadding, const EdgeInsets.fromLTRB(3, 0, 5, 0));
    expect(output.viewInsets, input.viewInsets);
  });

  test('keeps non-OHOS window metrics unchanged', () {
    const MediaQueryData input = MediaQueryData(padding: EdgeInsets.fromLTRB(3, 64, 5, 56), viewPadding: EdgeInsets.fromLTRB(3, 64, 5, 56));

    expect(AppSpacing.normalizeWindowInsets(input, isOhos: false), input);
  });
}
