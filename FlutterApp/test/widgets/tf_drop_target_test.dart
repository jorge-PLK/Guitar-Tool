import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_drop_target.dart';

Future<void> _send(WidgetTester tester, String method, Object? args) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'desktop_drop',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
  await tester.pump();
}

void main() {
  testWidgets('entrega las rutas soltadas dentro de la zona', (tester) async {
    final received = <List<String>>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TfDropTarget(onPaths: received.add, child: const SizedBox.expand()),
      ),
    );
    await _send(tester, 'entered', <double>[10, 10]);
    await _send(tester, 'performOperation', <String>['/a/uno.wav', '/a/dos.mp3']);
    expect(received, <List<String>>[
      <String>['/a/uno.wav', '/a/dos.mp3'],
    ]);
  });

  testWidgets('no entrega nada si no hay arrastre previo o la lista está vacía', (tester) async {
    final received = <List<String>>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TfDropTarget(onPaths: received.add, child: const SizedBox.expand()),
      ),
    );
    await _send(tester, 'performOperation', <String>['/a/uno.wav']);
    await _send(tester, 'entered', <double>[10, 10]);
    await _send(tester, 'performOperation', <String>[]);
    expect(received, isEmpty);
  });
}
