import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_alert.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext host;
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
          PageRouteBuilder<T>(settings: s, pageBuilder: (c, a, s2) => b(c)),
      home: Builder(builder: (c) {
        host = c;
        return const SizedBox();
      }),
    ),
  );
  return host;
}

void _expectNoDecoration(WidgetTester tester, String text) {
  final BuildContext ctx = tester.element(find.text(text));
  expect(DefaultTextStyle.of(ctx).style.decoration, TextDecoration.none);
}

void main() {
  testWidgets('showTfSheet: el título no hereda decoración', (tester) async {
    final host = await _pumpHost(tester);
    unawaited(showTfSheet<void>(
      context: host,
      builder: (_) => const TfSheetScaffold(width: 420, title: 'Título hoja'),
    ));
    await tester.pumpAndSettle();
    _expectNoDecoration(tester, 'Título hoja');
  });

  testWidgets('showTfAlert y showTfConfirm: título sin decoración', (tester) async {
    final host = await _pumpHost(tester);
    unawaited(showTfAlert(context: host, title: 'Aviso', okLabel: 'OK', message: 'Mensaje'));
    await tester.pumpAndSettle();
    _expectNoDecoration(tester, 'Aviso');
    Navigator.of(host).pop();
    await tester.pumpAndSettle();

    unawaited(showTfConfirm(
        context: host, title: 'Confirma', confirmLabel: 'Sí', cancelLabel: 'No'));
    await tester.pumpAndSettle();
    _expectNoDecoration(tester, 'Confirma');
  });
}
