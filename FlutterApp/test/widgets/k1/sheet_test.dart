import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_accent_bar.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_card.dart';
import 'package:toneforge/widgets/tf_chip.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_song_cover.dart';

import '../../support/harness.dart';

Widget _txt(String s) => Text(
      s,
      style: TfText.body(TfSize.font12, TfWeight.medium).copyWith(color: TfColors.muted, decoration: TextDecoration.none),
    );

Widget _row(String name, List<Widget> cells) => Padding(
      padding: const EdgeInsets.only(bottom: TfSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(width: 130, child: _txt(name)),
          for (final Widget c in cells) SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: c)),
        ],
      ),
    );

Widget _head(List<String> cols) => Padding(
      padding: const EdgeInsets.only(bottom: TfSpace.s8),
      child: Row(children: <Widget>[
        const SizedBox(width: 130),
        for (final String c in cols) SizedBox(width: 130, child: _txt(c)),
      ]),
    );

void main() {
  setUpAll(loadTfFonts);

  testWidgets('k1 lámina de revisión', (WidgetTester t) async {
    t.view.physicalSize = const Size(900, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final Map<String, Widget Function(VoidCallback?)> btn = <String, Widget Function(VoidCallback?)>{
      'Primary': (VoidCallback? f) => TfPrimaryButton(label: 'Guardar', onPressed: f),
      'Apply': (VoidCallback? f) => TfPrimaryButton.apply(label: 'Aplicar', onPressed: f),
      'Secondary 44': (VoidCallback? f) => TfSecondaryButton(label: 'Cancelar', onPressed: f),
      'Secondary 36': (VoidCallback? f) => TfSecondaryButton(label: 'Cancelar', height: TfSize.controlMd, onPressed: f),
      'Icon row': (VoidCallback? f) => TfIconButton(icon: TfIcon.trash, onPressed: f),
      'Icon secondary': (VoidCallback? f) =>
          TfIconButton(icon: TfIcon.folder, kind: TfIconButtonKind.secondary, onPressed: f),
      'Icon nudge': (VoidCallback? f) =>
          TfIconButton(icon: TfIcon.chevronRight, kind: TfIconButtonKind.nudge, onPressed: f),
    };

    final List<Widget> rows = <Widget>[_head(<String>['Reposo', 'Pulsado', 'Deshabilitado', 'Hover'])];
    for (final MapEntry<String, Widget Function(VoidCallback?)> e in btn.entries) {
      rows.add(_row(e.key, <Widget>[
        e.value(() {}),
        KeyedSubtree(key: ValueKey<String>('p_${e.key}'), child: e.value(() {})),
        e.value(null),
        KeyedSubtree(key: ValueKey<String>('h_${e.key}'), child: e.value(() {})),
      ]));
    }
    rows.add(_row('Chip', <Widget>[
      for (final TfChipKind k in TfChipKind.values) TfChip(k.name, kind: k),
    ]));
    rows.add(_row('AccentBar 0 / .5 / 1', <Widget>[
      const SizedBox(width: 110, child: TfAccentBar(value: 0)),
      const SizedBox(width: 110, child: TfAccentBar(value: 0.5)),
      const SizedBox(width: 110, child: TfAccentBar(value: 1)),
      const SizedBox(width: 110, child: TfAccentBar()),
    ]));
    rows.add(_row('Progress / Spinner', <Widget>[
      const SizedBox(width: 110, child: TfProgress(value: 0.4)),
      const TfSpinner.small(),
      const TfSpinner.mini(),
    ]));
    rows.add(_row('Divider / Cover / Card', <Widget>[
      const SizedBox(width: 110, child: TfDivider()),
      const TfSongCover(),
      const TfCard(child: SizedBox(width: 110, height: 44)),
    ]));

    await t.pumpWidget(k1Frame(
      pad: 24,
      key: const ValueKey<String>('sheet'),
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    ));

    final TestGesture mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.descendant(
      of: find.byKey(const ValueKey<String>('h_Icon row')),
      matching: find.byType(GestureDetector),
    )));
    await t.pump();
    final List<TestGesture> gestures = <TestGesture>[];
    int pointer = 10;
    for (final String name in btn.keys) {
      final Finder p = find.descendant(of: find.byKey(ValueKey<String>('p_$name')), matching: find.byType(GestureDetector));
      gestures.add(await t.startGesture(t.getCenter(p), pointer: pointer++));
    }
    await t.pump(const Duration(milliseconds: 400));

    await expectLater(find.byKey(const ValueKey<String>('sheet')), matchesGoldenFile('goldens/k1_sheet.png'));
    for (final TestGesture g in gestures) {
      await g.up();
    }
    await mouse.removePointer();
    await t.pumpWidget(const SizedBox());
  });
}
