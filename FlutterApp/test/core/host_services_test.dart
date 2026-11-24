import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/host_services.dart';

void main() {
  const host = PlatformHostServices();

  test('método desconocido: unsupported', () {
    expect(host.handle('nope', {}),
        throwsA(isA<HostError>().having((e) => e.code, 'code', 'unsupported')));
  });

  test('projectsFolderChanged responde ok', () async {
    expect(await host.handle('projectsFolderChanged', {'path': '/x'}), {'ok': true});
  });

  test('Songsterr (ola 2): unsupported', () async {
    for (final m in ['showPreview', 'hidePreview', 'load']) {
      await expectLater(host.handle(m, {}),
          throwsA(isA<HostError>().having((e) => e.code, 'code', 'unsupported')), reason: m);
    }
  });
}
