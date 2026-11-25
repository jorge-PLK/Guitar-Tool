import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/features/backing/study_position.dart';
import 'package:toneforge/features/tab/tab_transport.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';
import 'package:toneforge/widgets/tf_slider.dart';

import 'transport_support.dart';

Json _params(Rig r, String method) => (r.calls(method).last.params! as Map).cast<String, Object?>();

void main() {
  testWidgets('inicio llama a seek(0)', (tester) async {
    final r = await pumpTransport(tester, const TabTransport());
    await tester.tap(find.byKey(const ValueKey<String>('tab_rewind')));
    await tester.pump();
    expect(_params(r, 'study.seek')['seconds'], 0);
  });

  testWidgets('play y pausa según el estado de reproducción', (tester) async {
    final r = await pumpTransport(tester, const TabTransport());
    expect(find.bySemanticsLabel(es.tab_a11yPlay), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('tab_play')));
    await tester.pump();
    expect(r.calls('study.play'), hasLength(1));

    r.core.emit('study.position', {'seconds': 1.0, 'playing': true});
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.bySemanticsLabel(es.tab_a11yPause), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('tab_play')));
    await tester.pump();
    expect(r.calls('study.pause'), hasLength(1));
  });

  testWidgets('el reloj sigue study.position y muestra la duración', (tester) async {
    final r = await pumpTransport(tester, const TabTransport());
    expect(find.textContaining('0:00', findRichText: true), findsOneWidget);
    r.core.emit('study.position', {'seconds': 5.4, 'playing': true});
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('0:05 / 0:08', findRichText: true), findsOneWidget);
    expect(studyPositionProvider, isNotNull);
  });

  testWidgets('tempo en pasos de 5: muestra al arrastrar y llama a setRate al soltar', (tester) async {
    final r = await pumpTransport(tester, const TabTransport());
    final slider = tester.widget<TfSlider>(find.byType(TfSlider));
    expect(slider.step, 5);
    expect(slider.min, 50);
    expect(slider.max, 200);
    slider.onChanged!(115);
    await tester.pump();
    expect(r.calls('study.setRate'), isEmpty);
    expect(find.text('115 %'), findsOneWidget);
    slider.onChangeEnd!(115);
    await tester.pump();
    expect(_params(r, 'study.setRate')['rate'], 1.15);
  });

  testWidgets('metrónomo habilitado con pulsos y llama a setMetronome', (tester) async {
    final r = await pumpTransport(tester, const TabTransport());
    final box = tester.widget<TfCheckbox>(find.byType(TfCheckbox));
    expect(box.onChanged, isNotNull);
    box.onChanged!(true);
    await tester.pump();
    expect(_params(r, 'study.setMetronome')['on'], true);
  });

  testWidgets('metrónomo deshabilitado sin pulsos', (tester) async {
    await pumpTransport(tester, const TabTransport(), tweak: (open) {
      ((open['analysis']! as Map)['beats']! as List).clear();
    });
    expect(tester.widget<TfCheckbox>(find.byType(TfCheckbox)).onChanged, isNull);
  });
}
