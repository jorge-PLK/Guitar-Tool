import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/shell/selected_project.dart';

late MockCore core;
late ProviderContainer c;
late Json open;

Future<void> pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Json _transport() => Map<String, Object?>.of((open['transport']! as Map).cast<String, Object?>());

Future<void> setup() async {
  final src = (await DirectoryFixtureSource.find())!;
  core = await MockCore.load(src);
  final path = (await src.list()).firstWhere((p) => p.endsWith('study.open.result.json'));
  open = (json.decode(await src.read(path)) as Map).cast<String, Object?>();
  c = ProviderContainer(overrides: [
    coreClientProvider.overrideWithValue(core),
    launchOptionsProvider.overrideWithValue(const LaunchOptions()),
  ]);
  addTearDown(c.dispose);
  c.read(selectedProjectProvider.notifier).select('00000000-0000-0000-0000-00000000000a');
  c.listen(studyStoreProvider, (_, _) {});
  await pump();
}

StudyStore get store => c.read(studyStoreProvider.notifier);
double get shownRate => c.read(studyStoreProvider).transport!.rate;
double get shownFine => c.read(studyStoreProvider).transport!.fineCents;
List<MockCall> calls(String m) => [for (final x in core.calls) if (x.method == m) x];

void main() {
  test('arrastrar el tempo muestra el valor local y no llama setRate hasta soltar', () async {
    await setup();
    final base = shownRate;
    store.dragRate(1.35);
    store.dragRate(1.4);
    await pump();
    expect(shownRate, 1.4);
    expect(calls('study.setRate'), isEmpty);
    core.result('study.setRate', _transport()..['rate'] = 1.4);
    await store.commitRate(1.4);
    expect(calls('study.setRate'), hasLength(1));
    expect((calls('study.setRate').single.params! as Map)['rate'], 1.4);
    expect(shownRate, 1.4);
    expect(base, isNot(1.4));
  });

  test('soltar el tempo en el valor original no llama al núcleo y restaura', () async {
    await setup();
    final base = shownRate;
    store.dragRate(base + 0.5);
    store.dragRate(base);
    await store.commitRate(base);
    expect(calls('study.setRate'), isEmpty);
    expect(shownRate, base);
  });

  test('afinación fina: valor local, una en vuelo y la última gana', () async {
    await setup();
    core.handle('study.setTranspose', (p) => _transport()..['fineCents'] = p['fineCents']);
    final all = Future.wait(<Future<void>>[
      store.setTranspose(fineCents: 10),
      store.setTranspose(fineCents: 20),
      store.setTranspose(fineCents: 30),
    ]);
    expect(shownFine, 30);
    await all;
    await pump();
    final sent = [for (final x in calls('study.setTranspose')) (x.params! as Map)['fineCents']];
    expect(sent, [10, 30]);
    expect(shownFine, 30);
  });
}
