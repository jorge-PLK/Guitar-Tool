import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_list_row.dart';
import 'package:toneforge/widgets/tf_marquee.dart';
import 'package:toneforge/widgets/tf_notice.dart';
import 'package:toneforge/widgets/tf_sidebar.dart';
import 'package:toneforge/widgets/tf_tab_bar.dart';

import '../../support/harness.dart';

Future<TestGesture> _mouseOver(WidgetTester tester, Finder target) async {
  final TestGesture g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: const Offset(-50, -50));
  addTearDown(g.removePointer);
  await g.moveTo(tester.getCenter(target));
  await tester.pump();
  return g;
}

Widget _marquee(String text) => SizedBox(
      width: 100,
      child: TfMarquee(text: text, style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
    );

void main() {
  group('k5 nav row y barra lateral', () {
    testWidgets('tap en una fila llama a onTap solo de esa fila', (tester) async {
      int taps = 0;
      int other = 0;
      await pumpK5(
        tester,
        TfSidebar(
          logoTone: 'Tone',
          logoForge: 'Forge',
          entries: <TfSidebarEntry>[
            TfSidebarEntry(icon: TfIcon.musicNoteList, label: 'Uno', selected: true, onTap: () => taps++),
            TfSidebarEntry(icon: TfIcon.film, label: 'Dos', selected: false, onTap: () => other++),
          ],
        ),
        size: const Size(240, 400),
      );
      await tester.tap(find.text('Dos'));
      expect(other, 1);
      expect(taps, 0);
      expect(tester.getSize(find.byType(TfSidebar)).width, TfSize.sidebarWidth);
      expect(tester.getSize(find.byType(TfNavRow).first).height, TfSize.controlLg);
    });
  });

  group('k5 fila de lista', () {
    testWidgets('hover tiñe con accent @0.07 y al salir vuelve a transparente', (tester) async {
      final Color hover = TfColors.accent.withValues(alpha: TfOpacity.tint07);
      bool hasColor(Color c) => tester
          .widgetList<DecoratedBox>(find.descendant(of: find.byType(TfListRow), matching: find.byType(DecoratedBox)))
          .any((d) => d.decoration is BoxDecoration && (d.decoration as BoxDecoration).color == c);
      await pumpK5(tester, const SizedBox(width: 600, child: TfListRow(child: SizedBox(height: 20))));
      expect(hasColor(hover), isFalse);
      final TestGesture g = await _mouseOver(tester, find.byType(TfListRow));
      expect(hasColor(hover), isTrue);
      await g.moveTo(const Offset(700, 580));
      await tester.pump();
      expect(hasColor(hover), isFalse);
    });

    testWidgets('seleccionada: franja de 3 y fondo ok @0.12 mandan sobre el hover', (tester) async {
      await pumpK5(
        tester,
        const SizedBox(width: 600, child: TfListRow(selected: true, child: SizedBox(height: 20))),
      );
      await _mouseOver(tester, find.byType(TfListRow));
      final Finder stripe = find.byWidgetPredicate((w) => w is ColoredBox && w.color == TfColors.ok);
      expect(stripe, findsOneWidget);
      expect(tester.getSize(stripe).width, 3);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == TfColors.ok.withValues(alpha: TfOpacity.tint12),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tap llama a onTap', (tester) async {
      int taps = 0;
      await pumpK5(
        tester,
        SizedBox(width: 600, child: TfListRow(onTap: () => taps++, child: const SizedBox(height: 20))),
      );
      await tester.tap(find.byType(TfListRow));
      expect(taps, 1);
    });
  });

  group('k5 marquee', () {
    testWidgets('si cabe no corre aunque haya hover', (tester) async {
      await pumpK5(tester, _marquee('Corto'));
      await _mouseOver(tester, find.byType(TfMarquee));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(TfMarquee.runningKey), findsNothing);
      expect(find.text('Corto'), findsOneWidget);
    });

    testWidgets('si no cabe: «…» en reposo y corre con hover a 30 px/s', (tester) async {
      await pumpK5(tester, _marquee('Un título muchísimo más largo que la caja'));
      expect(find.byKey(TfMarquee.runningKey), findsNothing);
      final Text rest = tester.widget<Text>(find.byType(Text));
      expect(rest.overflow, TextOverflow.ellipsis);

      final TestGesture g = await _mouseOver(tester, find.byType(TfMarquee));
      await tester.pump(const Duration(seconds: 1));
      final double dx = tester.widget<Transform>(find.byKey(TfMarquee.runningKey)).transform.getTranslation().x;
      expect(dx, closeTo(-30, 1.5));

      await g.moveTo(const Offset(700, 580));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(TfMarquee.runningKey), findsNothing);
    });

    testWidgets('cambiar el texto reinicia', (tester) async {
      String text = 'Un título muchísimo más largo que la caja';
      late StateSetter set;
      await pumpK5(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return _marquee(text);
          },
        ),
      );
      await _mouseOver(tester, find.byType(TfMarquee));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(TfMarquee.runningKey), findsOneWidget);
      set(() => text = 'Otro título también larguísimo, sí');
      await tester.pump();
      expect(find.byKey(TfMarquee.runningKey), findsNothing);
    });
  });

  group('k5 pestañas', () {
    testWidgets('tap y teclado ← → cambian la pestaña', (tester) async {
      final List<int> picks = <int>[];
      int selected = 1;
      late StateSetter set;
      await pumpK5(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return TfTabBar(
              labels: const <String>['Audio', 'Vídeo', 'Biblioteca'],
              selected: selected,
              onSelect: (i) {
                picks.add(i);
                set(() => selected = i);
              },
            );
          },
        ),
      );
      await tester.tap(find.text('Audio'));
      expect(picks, <int>[0]);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(picks, <int>[0, 1, 2]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(picks, <int>[0, 1, 2], reason: 'sin salto más allá del último');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(picks.last, 1);
    });
  });

  group('k5 aviso', () {
    testWidgets('la X llama a onDismiss', (tester) async {
      int n = 0;
      await pumpK5(
        tester,
        SizedBox(width: 400, child: TfNotice(messages: const <String>['Hola'], onDismiss: () => n++)),
      );
      await tester.tap(find.byWidgetPredicate((w) => w is TfIconView && w.icon == TfIcon.xmark));
      expect(n, 1);
    });
  });
}
