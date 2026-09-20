/// Queue artwork presentation tests without host or network I/O.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read_audio_player/mg_read_audio_player.dart';
import 'package:mg_read_audio_player/src/ui/audio_player_sheets.dart';

void main() {
  testWidgets('queue renders host artwork', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _openQueue(
      tester,
      controller,
      artworkBuilder: (_, _) => const ColoredBox(
        key: Key('host-queue-artwork'),
        color: Color(0xFF8A4B36),
      ),
    );

    expect(
      find.byKey(const Key('audio-queue-artwork-current')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('host-queue-artwork')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue keeps its fallback compact', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _openQueue(tester, controller);

    expect(
      find.byKey(const Key('audio-queue-artwork-fallback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

AudioPlayerController _controller() {
  final controller = AudioPlayerController();
  final owner = Object();
  controller.bind(
    owner: owner,
    play: _done,
    pause: _done,
    toggle: _done,
    seek: _doneWith,
    seekBy: _doneWith,
    previous: _done,
    next: _done,
    jump: _doneWith,
    selectQueueEntry: _doneWith,
    setRate: _doneWith,
    setVolume: _doneWith,
    setSleepTimer: _doneWith,
    retry: _done,
    recover: _done,
    requestExit: _done,
  );
  controller.updateSnapshot(
    AudioPlayerSnapshot(
      status: AudioPlayerStatus.ready,
      queue: <AudioTrack>[
        AudioTrack(
          id: 'current',
          title: '当前章节',
          resource: Uri.parse('https://example.test/current.mp3'),
        ),
      ],
      queueEntries: const <AudioQueueEntry>[
        AudioQueueEntry(id: 'current', title: '当前章节'),
        AudioQueueEntry(id: 'fallback', title: '无封面章节'),
      ],
    ),
    owner: owner,
  );
  return controller;
}

Future<void> _openQueue(
  WidgetTester tester,
  AudioPlayerController controller, {
  AudioQueueArtworkBuilder? artworkBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAudioQueueSheet(
            context,
            snapshot: controller.snapshot,
            controller: controller,
            artworkBuilder: artworkBuilder,
          ),
          child: const Text('打开队列'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开队列'));
  await tester.pumpAndSettle();
}

Future<void> _done() async {}

Future<void> _doneWith<T>(T _) async {}
