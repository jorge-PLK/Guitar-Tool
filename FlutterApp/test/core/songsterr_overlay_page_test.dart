import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/host_services.dart';
import 'package:toneforge/core/songsterr_hidden_host.dart';
import 'package:toneforge/core/songsterr_overlay_page.dart';

import '../support/fake_web_view.dart';

const _url = 'https://www.songsterr.com/a/wsa/x-s1';
const _params = {'url': _url, 'timeout': 1.0, 'readyScript': 'ready()'};

Future<void> _pumpApp(WidgetTester t, {Widget? home}) => t.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings, pageBuilder: (c, _, _) => builder(c)),
      home: home ?? const Center(child: Text('contenido')),
    ));

int _entries(WidgetTester t) => t.widgetList(find.byKey(const ValueKey('fake-web-view'))).length;

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('selección por plataforma', (t) async {
    final calls = <String>[];
    HiddenSongsterrHost host(TargetPlatform p) => HiddenSongsterrHost(
          platform: () => p,
          windowsFactory: () async {
            calls.add('windows');
            throw const HostError('unsupported', 'x');
          },
        );
    await expectLater(host(TargetPlatform.windows).load(_params),
        throwsA(isA<HostError>().having((e) => e.code, 'code', 'unsupported')));
    expect(calls, ['windows']);
    for (final p in [TargetPlatform.linux, TargetPlatform.android, TargetPlatform.iOS]) {
      await expectLater(host(p).load(_params),
          throwsA(isA<HostError>().having((e) => e.code, 'code', 'unsupported')));
    }
    expect(calls, ['windows']);
  });

  testWidgets('sin Overlay: unsupported', (t) async {
    final host = HiddenSongsterrHost(
        platform: () => TargetPlatform.windows,
        windowsFactory: () => OverlayWebPage.create(locate: () => null));
    await expectLater(host.load(_params),
        throwsA(isA<HostError>().having((e) => e.code, 'code', 'unsupported')));
  });

  testWidgets('monta en el Overlay, no cambia el layout y desmonta al cerrar', (t) async {
    await _pumpApp(t);
    final before = t.getSize(find.text('contenido'));
    final factory = FakeWebViewFactory();
    final page = await OverlayWebPage.create(controllerFactory: factory.call);
    final nav = page.navigate(Uri.parse(_url), userAgent: 'UA');
    await t.pump();
    expect(factory.created.length, 1);
    expect(factory.created.single.config.userAgent, 'UA');
    expect(factory.created.single.calls, ['loadUrl:$_url']);
    expect(_entries(t), 1);
    expect(t.getSize(find.byKey(const ValueKey('fake-web-view'))), const Size(1200, 800));
    expect(find.ancestor(of: find.byKey(const ValueKey('fake-web-view')), matching: find.byType(IgnorePointer)),
        findsWidgets);
    final op = t.widget<Opacity>(find.ancestor(of: find.byKey(const ValueKey('fake-web-view')), matching: find.byType(Opacity)).first);
    expect(op.opacity, 0);
    expect(t.getSize(find.text('contenido')), before);

    factory.created.single.simulatePageFinished(_url);
    expect(await nav, isNull);

    await page.close();
    await page.close(); // idempotente
    await t.pump();
    expect(_entries(t), 0);
    expect(OverlayWebPage.mounted, 0);
    expect(factory.created.single.calls.where((c) => c == 'dispose').length, 1);
  });

  testWidgets('carga completa por el anfitrión: sondea, devuelve html y libera la entrada', (t) async {
    await _pumpApp(t);
    final factory = FakeWebViewFactory();
    final host = HiddenSongsterrHost(
      platform: () => TargetPlatform.windows,
      pollInterval: const Duration(milliseconds: 10),
      windowsFactory: () => OverlayWebPage.create(controllerFactory: factory.call),
    );
    final result = await t.runAsync(() async {
      final r = host.load(_params);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      factory.created.single
        ..evalResults['ready()'] = true
        ..evalResults['document.documentElement.outerHTML'] = '<html>ok</html>'
        ..simulatePageFinished(_url);
      return r;
    });
    expect(result, {'status': 200, 'html': '<html>ok</html>'});
    await t.pump();
    expect(_entries(t), 0);
    expect(OverlayWebPage.mounted, 0);
  });

  testWidgets('error que nombra la URL: offline y sin fugas', (t) async {
    await _pumpApp(t);
    final factory = FakeWebViewFactory();
    final page = await OverlayWebPage.create(controllerFactory: factory.call);
    final nav = page.navigate(Uri.parse(_url));
    final expectation = expectLater(
        nav, throwsA(isA<HostError>().having((e) => e.code, 'code', 'offline')));
    await t.pump();
    factory.created.single.config.onError?.call('-2 net::ERR $_url');
    await expectation;
    await page.close();
    await t.pump();
    expect(_entries(t), 0);
    expect(OverlayWebPage.mounted, 0);
  });

  testWidgets('un error de subrecurso no aborta la navegación', (t) async {
    await _pumpApp(t);
    final factory = FakeWebViewFactory();
    final page = await OverlayWebPage.create(controllerFactory: factory.call);
    final nav = page.navigate(Uri.parse(_url));
    await t.pump();
    factory.created.single.config.onError?.call('-2 fail https://cdn.example/x.js');
    factory.created.single.simulatePageFinished(_url);
    expect(await nav, isNull);
    await page.close();
  });
}
