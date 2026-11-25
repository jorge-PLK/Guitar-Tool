import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/core/mock_core.dart';
import 'package:toneforge/features/library/link_import_store.dart';

import 'link_import_store_test.dart' as base;

/// MockCore que retiene `link.import` hasta abrir la puerta.
class _ImportGateCore implements CoreClient {
  _ImportGateCore(this.inner, this.gate);
  final MockCore inner;
  final Completer<void> gate;

  @override
  Future<T> call<T>(String method, Object? params, T Function(Json) decode) async {
    if (method == 'link.import' && !gate.isCompleted) await gate.future;
    return inner.call(method, params, decode);
  }

  @override
  Stream<T> on<T>(String event, T Function(Json) decode) => inner.on(event, decode);

  @override
  Future<void> shutdown() => inner.shutdown();
}

Future<(ProviderContainer, MockCore, Completer<void>)> _setup() async {
  final core = await MockCore.load((await DirectoryFixtureSource.find())!);
  core.result('link.classify', {'kind': 'track', 'source': 'spotify'});
  core.result('link.resolve', base.resolved());
  core.result('link.cancel', {'cancelled': true});
  final gate = Completer<void>();
  final c = ProviderContainer(overrides: [coreClientProvider.overrideWithValue(_ImportGateCore(core, gate))]);
  addTearDown(c.dispose);
  c.listen(linkImportStoreProvider, (_, _) {});
  return (c, core, gate);
}

void main() {
  group('link_import_store: cancelar durante link.import', () {
    test('un link.finished con duplicado posterior llega como alerta', () async {
      final (c, core, gate) = await _setup();
      await base.toCandidates(c);
      core.result('link.import', {'jobId': 'link-1'});
      final pending = base.st(c).importSelected();
      await Future<void>.delayed(Duration.zero);
      await base.st(c).cancel();
      gate.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(base.count(core, 'link.cancel'), 1);
      expect(base.params(core, 'link.cancel'), {'jobId': 'link-1'});
      core.emit('link.finished', base.finished(dup: true));
      await Future<void>.delayed(Duration.zero);
      expect(base.sv(c).duplicateOf, base.kUuid);
    });

    test('lo llegado mientras se encolaba también se atiende', () async {
      final (c, core, gate) = await _setup();
      await base.toCandidates(c);
      core.result('link.import', {'jobId': 'link-1'});
      final pending = base.st(c).importSelected();
      await Future<void>.delayed(Duration.zero);
      await base.st(c).cancel();
      core.emit('link.finished', base.finished(dup: true));
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await pending;
      expect(base.sv(c).duplicateOf, base.kUuid);
    });

    test('después, un segundo importSelected funciona', () async {
      final (c, core, gate) = await _setup();
      await base.toCandidates(c);
      core.result('link.import', {'jobId': 'link-1'});
      final pending = base.st(c).importSelected();
      await Future<void>.delayed(Duration.zero);
      await base.st(c).cancel();
      gate.complete();
      await pending;
      expect(base.sv(c).screen, LinkImportScreen.candidates);
      base.st(c).dismissDuplicate();
      core.result('link.import', {'jobId': 'link-2'});
      await base.st(c).importSelected();
      expect(base.sv(c).jobId, 'link-2');
      core.emit('link.finished', base.finished(jobId: 'link-2'));
      await Future<void>.delayed(Duration.zero);
      expect(base.sv(c).screen, LinkImportScreen.done);
    });
  });
}
