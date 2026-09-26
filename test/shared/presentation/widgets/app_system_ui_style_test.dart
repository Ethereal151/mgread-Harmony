/// Verifies only a visible, resumed route can write native system-bar colors.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read/shared/presentation/widgets/app_system_ui_style.dart';
import 'package:novel_reader_ui/novel_reader_ui.dart';

void main() {
  late ReaderPlatform previous;
  late _RecordingPlatform platform;

  setUp(() {
    previous = ReaderPlatform.instance;
    ReaderPlatform.instance = platform = _RecordingPlatform();
  });
  tearDown(() => ReaderPlatform.instance = previous);

  testWidgets('inactive tabs cannot overwrite the visible tab on resume', (tester) async {
    final activeTab = ValueNotifier<int>(0);
    addTearDown(activeTab.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: activeTab,
          builder: (context, active, _) => IndexedStack(
            index: active,
            children: <Widget>[
              for (var index = 0; index < 2; index++)
                TickerMode(enabled: index == active, child: _page(index == 0 ? Colors.white : Colors.black)),
            ],
          ),
        ),
      ),
    );
    expect(platform.colors, <String>['#FFFFFFFF']);
    activeTab.value = 1;
    await tester.pump();
    expect(platform.colors.last, '#FF000000');
    platform.colors.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(platform.colors, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.colors, <String>['#FF000000']);
  });

  testWidgets('covered route stays silent and resynchronizes after pop', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: _page(Colors.white)));
    navigator.currentState!.push<void>(MaterialPageRoute<void>(builder: (_) => _page(Colors.black)));
    await tester.pumpAndSettle();
    platform.colors.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.colors, <String>['#FF000000']);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(platform.colors.last, '#FFFFFFFF');
  });
}

Widget _page(Color color) => AppSystemUiStyle(statusBarColor: color, navigationBarColor: color, child: const SizedBox.expand());

final class _RecordingPlatform extends ReaderPlatform {
  final List<String> colors = <String>[];

  @override
  Future<void> setApplicationSystemUiStyle({
    required String statusBarColor,
    required String navigationBarColor,
    required String statusBarContentColor,
    required String navigationBarContentColor,
  }) async {
    colors.add(statusBarColor);
  }
}
