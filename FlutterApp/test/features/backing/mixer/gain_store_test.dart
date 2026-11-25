import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/launch_options.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/shell/selected_project.dart';

/// Núcleo que retiene `setMix`/`setMaster` hasta que el test los libere.
class _GatedCore implements CoreClient {
  _GatedCore(this.inner);

  final MockCore inner;
  final List<Completer<void>> gates = <Completer<void>>[];
  final List<Object?> sent = <Object?>[];

  @override
  Future<T> call<T>(String method, Object? params, T Function(Json) decode) async {
    if (method == 'study.setMix' || method == 'study.setMaster') {
      sent.add(params);
      final Completer<void> g = Completer<void>();
      gates.add(g);
      await g.future;
    }
    return inner.call(method, params, decode);
  }

  @override
  Stream<T> on<T>(String event, T Function(Json) decode) => inner.on(event, decode);

  @override
  Future<void> shutdown() => inner.shutdown();
}

Future<void> _pump() async {
  for (int i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _GatedCore gated;
  late ProviderContainer c;
  late String channelId;

  Future<void> setup() async {
    final DirectoryFixtureSource src = (await DirectoryFixtureSource.find())!;
    final MockCore core = await MockCore.load(src);
    final String path = (await src.list()).firstWhere((String p) => p.endsWith('study.open.result.json'));
    final Json open = (json.decode(await src.read(path)) as Map).cast<String, Object?>();
    final Json t = Map<String, Object?>.of((open['transport']! as Map).cast());
    final List<Json> chans = <Json>[
      for (final Object? ch in t['channels']! as List) Map<String, Object?>.of((ch! as Map).cast()),
    ];
    t['channels'] = chans;
    channelId = chans.first['id']! as String;
    core.handle('study.setMix', (Json p) {
      for (final Json ch in chans) {
        if (ch['id'] == p['channel']) ch['gainDB'] = p['gainDB'];
      }
      return t;
    });
    core.handle('study.setMaster', (Json p) {
      t['masterGainDB'] = p['gainDB'];
      return t;
    });
    gated = _GatedCore(core);
    c = ProviderContainer(overrides: [
      coreClientProvider.overrideWithValue(gated),
      launchOptionsProvider.overrideWithValue(const LaunchOptions()),
    ]);
    addTearDown(c.dispose);
    c.read(selectedProjectProvider.notifier).select('00000000-0000-0000-0000-00000000000a');
    c.listen(studyStoreProvider, (_, _) {});
    await _pump();
  }

  double gainOf() => c.read(studyStoreProvider).transport!.channels.firstWhere((ch) => ch.id == channelId).gainDB;

  test('fader de canal: una llamada en vuelo, la última gana y el valor local sigue al dedo', () async {
    await setup();
    final StudyStore store = c.read(studyStoreProvider.notifier);
    unawaited(store.setMix(channelId, gainDB: -10));
    unawaited(store.setMix(channelId, gainDB: -20));
    final Future<void> last = store.setMix(channelId, gainDB: -30);
    await _pump();
    expect(gated.sent, hasLength(1), reason: 'solo una en vuelo');
    expect(gainOf(), -30, reason: 'valor optimista');
    gated.gates[0].complete();
    await _pump();
    expect(gated.sent, hasLength(2));
    expect((gated.sent[1]! as Map)['gainDB'], -30);
    expect(gainOf(), -30, reason: 'la respuesta vieja no pisa lo mostrado');
    gated.gates[1].complete();
    await last;
    expect(gated.sent, hasLength(2));
    expect(gainOf(), -30);
  });

  test('master: coalesce igual y reconcilia con el núcleo', () async {
    await setup();
    final StudyStore store = c.read(studyStoreProvider.notifier);
    unawaited(store.setMaster(-5));
    final Future<void> last = store.setMaster(-8);
    await _pump();
    expect(gated.sent, hasLength(1));
    expect(c.read(studyStoreProvider).transport!.masterGainDB, -8);
    gated.gates[0].complete();
    await _pump();
    gated.gates[1].complete();
    await last;
    expect(gated.sent, hasLength(2));
    expect((gated.sent[1]! as Map)['gainDB'], -8);
    expect(c.read(studyStoreProvider).transport!.masterGainDB, -8);
  });
}
