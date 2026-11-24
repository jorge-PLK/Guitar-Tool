import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_web_view.dart';

import '../support/fake_web_view.dart';

void main() {
  test('la fábrica inyectada entrega el falso con su configuración', () {
    final factory = FakeWebViewFactory();
    final container = ProviderContainer(overrides: [factory.override]);
    addTearDown(container.dispose);
    final seen = <Object?>[];
    final c = container.read(tfWebViewControllerFactoryProvider)(
      TfWebViewConfig(userAgent: 'UA', onMessage: seen.add),
    ) as FakeWebViewController;
    expect(factory.created, [c]);
    expect(c.config.userAgent, 'UA');
  });

  test('carga de fichero y URL, Dart->JS y evaluación', () async {
    final c = FakeWebViewController(const TfWebViewConfig());
    c.evalResults['1+1'] = 2;
    await c.loadFile('/x/tab.html');
    await c.loadUrl(Uri.parse('https://www.songsterr.com/'));
    await c.runJavaScript('tf.go()');
    expect(await c.evaluateJavaScript('1+1'), 2);
    expect(c.calls, [
      'loadFile:/x/tab.html',
      'loadUrl:https://www.songsterr.com/',
      'run:tf.go()',
      'eval:1+1',
    ]);
  });

  test('mensajes JS->Dart: JSON decodificado y texto no JSON por onError', () {
    final msgs = <Object?>[];
    final errors = <String>[];
    final c = FakeWebViewController(TfWebViewConfig(onMessage: msgs.add, onError: errors.add));
    c.simulateMessage({'event': 'beatClick', 'bar': 3});
    c.simulateRawMessage('no es json');
    expect(msgs, [
      {'event': 'beatClick', 'bar': 3},
    ]);
    expect(errors, hasLength(1));
  });

  test('decodeJsResult: JSON de Mac y doble codificación de Windows', () {
    expect(PluginWebViewController.decodeJsResult('{"a":1}'), {'a': 1});
    expect(PluginWebViewController.decodeJsResult('"{\\"a\\":1}"'), {'a': 1});
    expect(PluginWebViewController.decodeJsResult('hola'), 'hola');
  });

  testWidgets('monta la vista cuando está listo y no toma el foco', (tester) async {
    final c = FakeWebViewController(const TfWebViewConfig())..setReady(false);
    final field = FocusNode();
    addTearDown(field.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        Focus(focusNode: field, child: const SizedBox(width: 50, height: 50)),
        SizedBox(width: 200, height: 200, child: TfWebView(controller: c)),
      ]),
    ));
    field.requestFocus();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-web-view')), findsNothing);

    c.setReady(true);
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-web-view')), findsOneWidget);
    expect(find.byType(ExcludeFocus), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fake-web-view')));
    await tester.pump();
    expect(field.hasPrimaryFocus, isTrue);
    expect(c.calls, ['reclaim']);
  });
}
