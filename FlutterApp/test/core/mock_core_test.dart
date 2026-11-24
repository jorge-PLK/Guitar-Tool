import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/core/mock_core.dart';

void main() {
  late MockCore core;

  setUp(() async {
    final src = await DirectoryFixtureSource.find();
    expect(src, isNotNull, reason: 'Contract/fixtures no encontrado');
    core = await MockCore.load(src!);
  });

  test('resultado de fixture', () async {
    final v = await core.call('app.info', {}, (j) => j['version']);
    expect(v, '0.1.0');
    final r = await core.call('jobs.cancel', {'id': 'x'}, (j) => j['cancelled']);
    expect(r, true);
    expect(core.calls.map((c) => c.method), ['app.info', 'jobs.cancel']);
  });

  test('método sin fixture: unsupported', () {
    expect(core.call('nope', {}, (j) => j),
        throwsA(isA<CoreError>().having((e) => e.code, 'code', 'unsupported')));
  });

  test('error de fixture', () async {
    core.failWithFixture('jobs.cancel');
    await expectLater(core.call('jobs.cancel', {}, (j) => j),
        throwsA(isA<CoreError>().having((e) => e.code, 'code', 'bad-params')));
  });

  test('evento de fixture e inyectado', () async {
    final got = <Object?>[];
    final sub = core.on('jobs.progress', (j) => j['stage']).listen(got.add);
    core.emitFixture('jobs.progress');
    core.emit('jobs.progress', {'stage': 'import'});
    await Future<void>.delayed(Duration.zero);
    expect(got, ['separation', 'import']);
    await sub.cancel();
  });

  test('handler y result sustituyen al fixture', () async {
    core.handle('app.info', (p) => {'version': 'h'});
    expect(await core.call('app.info', {}, (j) => j['version']), 'h');
    core.result('app.info', {'version': 'r'});
    core.handle('x', (p) => {'echo': p['a']});
    expect(await core.call('x', {'a': 3}, (j) => j['echo']), 3);
  });

  test('lazy espera a los fixtures', () async {
    final src = await DirectoryFixtureSource.find();
    final lazy = MockCore.lazy(() async => src!);
    expect(await lazy.call('app.info', {}, (j) => j['platform']), 'macos');
  });
}
