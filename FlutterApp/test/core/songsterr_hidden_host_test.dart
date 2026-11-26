import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/host_services.dart';
import 'package:toneforge/core/songsterr_hidden_host.dart';

class FakePage implements HiddenWebPage {
  FakePage({this.navigateError, this.status, this.readyAfter = 0, this.gate});
  final HostError? navigateError;
  final int? status;
  final int readyAfter; // evaluaciones que dan false antes del true; -1 = nunca
  final Completer<void>? gate;
  String? ua;
  Uri? url;
  int evals = 0;
  bool closed = false;

  @override
  Future<int?> navigate(Uri url, {String? userAgent}) async {
    this.url = url;
    ua = userAgent;
    await gate?.future;
    if (navigateError != null) throw navigateError!;
    return status;
  }

  @override
  Future<bool> evaluateBool(String js) async {
    evals++;
    return readyAfter >= 0 && evals > readyAfter;
  }

  @override
  Future<String> outerHtml() async => '<html>ok</html>';

  @override
  Future<void> close() async => closed = true;
}

HiddenSongsterrHost hostWith(List<FakePage> pages) {
  final queue = [...pages];
  return HiddenSongsterrHost(
    pageFactory: () async => queue.removeAt(0),
    pollInterval: const Duration(milliseconds: 10),
  );
}

const _p = {'url': 'https://www.songsterr.com/a/wsa/x-s1', 'timeout': 1.0};

void main() {
  test('éxito sin readyScript: vuelve al cargar, status 200 si no se lee', () async {
    final page = FakePage();
    final r = await hostWith([page]).load({..._p, 'userAgent': 'UA'});
    expect(r, {'status': 200, 'html': '<html>ok</html>'});
    expect(page.ua, 'UA');
    expect(page.evals, 0);
    expect(page.closed, isTrue);
  });

  test('éxito con readyScript: sondea hasta true', () async {
    final page = FakePage(status: 203, readyAfter: 3);
    final r = await hostWith([page]).load({..._p, 'readyScript': 'x'});
    expect(r['status'], 203);
    expect(page.evals, 4);
    expect(page.closed, isTrue);
  });

  test('readyTimeout y se libera', () async {
    final page = FakePage(readyAfter: -1);
    await expectLater(
        hostWith([page]).load({'url': _p['url'], 'timeout': 0.1, 'readyScript': 'x'}),
        throwsA(isA<HostError>().having((e) => e.code, 'code', 'readyTimeout')));
    expect(page.closed, isTrue);
  });

  test('httpStatus 429 lleva status en el JSON', () async {
    final page = FakePage(navigateError: const HostError('httpStatus', 'x', status: 429));
    try {
      await hostWith([page]).load(_p);
      fail('debía fallar');
    } on HostError catch (e) {
      expect(e.toJson(), containsPair('code', 'httpStatus'));
      expect(e.toJson(), containsPair('status', 429));
    }
    expect(page.closed, isTrue);
  });

  test('offline y navegación que no termina', () async {
    final a = FakePage(navigateError: const HostError('offline', 'dns'));
    await expectLater(hostWith([a]).load(_p),
        throwsA(isA<HostError>().having((e) => e.code, 'code', 'offline')));
    expect(a.closed, isTrue);
    final b = FakePage(gate: Completer<void>());
    await expectLater(hostWith([b]).load({'url': _p['url'], 'timeout': 0.05}),
        throwsA(isA<HostError>().having((e) => e.code, 'code', 'offline')));
    expect(b.closed, isTrue);
  });

  test('dos cargas se serializan', () async {
    final gate = Completer<void>();
    final first = FakePage(gate: gate);
    final second = FakePage();
    final created = <int>[];
    final queue = [first, second];
    final host = HiddenSongsterrHost(
      pageFactory: () async {
        created.add(created.length);
        return queue.removeAt(0);
      },
    );
    final f1 = host.load(_p);
    final f2 = host.load(_p);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(created, [0]);
    expect(second.url, isNull);
    gate.complete();
    await Future.wait([f1, f2]);
    expect(created, [0, 1]);
    expect(first.closed && second.closed, isTrue);
  });

  test('una carga fallida no bloquea la cola', () async {
    final host = hostWith([FakePage(navigateError: const HostError('offline', 'x')), FakePage()]);
    await expectLater(host.load(_p), throwsA(isA<HostError>()));
    expect((await host.load(_p))['status'], 200);
  });

  test('plataforma sin soporte: unsupported', () async {
    final host = HiddenSongsterrHost(pageFactory: () => throw StateError('no'));
    await expectLater(host.load(_p),
        throwsA(isA<HostError>().having((e) => e.code, 'code', 'unsupported')));
  });

  test('decodeHtmlResult quita las comillas JSON de Mac', () {
    expect(OffscreenWebPage.decodeHtmlResult(r'"<a b=\"c\">"'), '<a b="c">');
    expect(OffscreenWebPage.decodeHtmlResult('<a>'), '<a>');
  });
}
