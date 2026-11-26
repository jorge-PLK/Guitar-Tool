import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/frame_channel.dart';
import 'package:toneforge/core/frame_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/record/take_viewer_scrub.dart';
import 'package:toneforge/features/record/take_viewer_store.dart';

import 'take_viewer_store_test.dart' show snap, takeId, pos;

/// Reloj manual: el tiempo solo avanza con [advance]; dispara los temporizadores vencidos.
class FakeScrubClock extends ScrubClock {
  DateTime _now = DateTime(2026);
  final _timers = <(DateTime, void Function())>[];

  @override
  DateTime now() => _now;

  @override
  Timer timer(Duration d, void Function() cb) {
    final entry = (_now.add(d), cb);
    _timers.add(entry);
    return _FakeTimer(() => _timers.remove(entry));
  }

  void advance(Duration d) {
    final target = _now.add(d);
    while (true) {
      _timers.sort((a, b) => a.$1.compareTo(b.$1));
      if (_timers.isEmpty || _timers.first.$1.isAfter(target)) break;
      final t = _timers.removeAt(0);
      _now = t.$1;
      t.$2();
    }
    _now = target;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._cancel);
  final void Function() _cancel;
  @override
  void cancel() => _cancel();
  @override
  bool get isActive => true;
  @override
  int get tick => 0;
}

void main() {
  test('arrastre de 1 s con cambios cada 16 ms: 10-14 seeks, el último exacto, ignora al núcleo', () async {
    final clock = FakeScrubClock();
    final core = MockCore()
      ..result('takeview.open', snap('open'))
      ..result('takeview.close', <String, Object?>{})
      ..result('takeview.seek', snap('seek'));
    final c = ProviderContainer(overrides: [
      coreClientProvider.overrideWithValue(core),
      scrubClockProvider.overrideWithValue(clock),
      frameChannelProvider(FrameChannelId.take).overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    c.listen(takeViewerStoreProvider, (_, _) {});
    final store = c.read(takeViewerStoreProvider.notifier);
    await store.open('p', takeId);
    final before = c.read(takeViewerStoreProvider).position;

    List<double> seeks() => [
          for (final x in core.calls.where((x) => x.method == 'takeview.seek')) ((x.params as Map)['seconds'] as num).toDouble()
        ];

    for (var i = 0; i <= 62; i++) {
      store.scrub(i * 0.04);
      core.emit('takeview.position', pos({'seconds': 0.1, 'epoch': 50}));
      await Future<void>.delayed(Duration.zero);
      clock.advance(const Duration(milliseconds: 16));
    }
    await Future<void>.delayed(Duration.zero);
    expect(c.read(takeViewerStoreProvider).position, before, reason: 'el núcleo se ignora durante el arrastre');
    await store.scrubEnd(2.5);
    final sent = seeks();
    expect(sent.length, inInclusiveRange(10, 14));
    expect(sent.last, 2.5);
    core.emit('takeview.position', pos({'seconds': 0.1, 'epoch': 50}));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(takeViewerStoreProvider).position, isNot(before), reason: 'tras soltar vuelve a seguir al núcleo');
  });
}
