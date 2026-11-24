import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_fader.dart';
import 'package:toneforge/widgets/tf_input_meters.dart';
import 'package:toneforge/widgets/tf_level_bar.dart';
import 'package:toneforge/widgets/tf_mixer_channel.dart';
import 'package:toneforge/widgets/tf_pill.dart';
import 'package:toneforge/widgets/tf_toggle_button.dart';

import '../../support/harness.dart';

String _fmt(double d) => '${d.toStringAsFixed(1)} dB';

Widget _fader(double dB, [double h = TfSize.faderBaseHeight]) =>
    TfFader(dB: dB, onChanged: (_) {}, semanticLabel: 'Volumen', semanticValue: _fmt, height: h);

Widget _text(String s, [Color c = TfColors.text2]) =>
    Text(s, style: TfText.body(TfSize.font12).copyWith(color: c));

Widget _channel({
  TfMixerChannelVariant variant = TfMixerChannelVariant.normal,
  bool dimmed = false,
  double height = TfSize.mixerChannelHeight,
  double dB = 0,
  double? rms = -18,
  String name = 'Bajo',
}) {
  final bool master = variant == TfMixerChannelVariant.master;
  return TfMixerChannel(
    variant: variant,
    dimmed: dimmed,
    height: height,
    title: Text(name, style: TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: TfColors.text)),
    faderBuilder: (double h) => _fader(dB, h),
    levelBuilder: master ? null : (double h) => TfLevelBar(rmsDb: rms, height: h, dim: dimmed),
    value: _text(_fmt(dB)),
    toggles: master
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: TfSpace.s6,
            children: <Widget>[
              TfToggleButton(text: 'M', on: dimmed, onPressed: () {}, semanticLabel: 'Silenciar'),
              TfToggleButton(text: 'S', on: false, onPressed: () {}, semanticLabel: 'Solo'),
            ],
          ),
  );
}

Widget _labeled(String label, Widget child) => Column(
      mainAxisSize: MainAxisSize.min,
      spacing: TfSpace.s6,
      children: <Widget>[child, _text(label, TfColors.muted)],
    );

Widget _icon(Color c) => SizedBox(width: 12, height: 12, child: ColoredBox(color: c));

List<(String, Widget)> _cases() => <(String, Widget)>[
      ('fader -60', _fader(-60)),
      ('fader 0', _fader(0)),
      ('fader +6', _fader(6)),
      ('nivel 0', const TfLevelBar(rmsDb: -60, height: 150)),
      ('nivel 50', const TfLevelBar(rmsDb: -30, height: 150)),
      ('nivel 100', const TfLevelBar(rmsDb: 0, height: 150)),
      ('medidores', const TfInputMeters(levels: <double>[0, 0.3, 0.7, 1])),
      ('toggle off 36', TfToggleButton(text: 'M', on: false, onPressed: () {}, semanticLabel: 'M')),
      ('toggle on 36', TfToggleButton(text: 'M', on: true, onPressed: () {}, semanticLabel: 'M')),
      (
        'toggle off 28',
        TfToggleButton(text: 'S', on: false, onPressed: () {}, semanticLabel: 'S', size: TfToggleSize.small)
      ),
      (
        'toggle on 28',
        TfToggleButton(text: 'S', on: true, onPressed: () {}, semanticLabel: 'S', size: TfToggleSize.small)
      ),
      ('pastilla activa', TfPill(label: 'Guitarra', active: true, onPressed: () {}, iconBuilder: _icon)),
      ('pastilla inactiva', TfPill(label: 'Bajo', onPressed: () {}, iconBuilder: _icon)),
      ('pastilla pendiente', const TfPill(label: 'Voz', pending: true)),
      ('compacta activa', TfCompactPill(label: 'Solo', active: true, onPressed: () {}, iconBuilder: _icon)),
      ('compacta inactiva', TfCompactPill(label: 'Sección', onPressed: () {}, iconBuilder: _icon)),
      ('canal normal', _channel()),
      ('canal master', _channel(variant: TfMixerChannelVariant.master, name: 'Master')),
      ('canal atenuado', _channel(dimmed: true, dB: -6)),
      ('canal alto mínimo', _channel(height: TfSize.mixerChannelMinHeight, dB: 3)),
    ];

void main() {
  setUpAll(loadTfFonts);

  group('k3 goldens', () {
    for (final (String name, Widget w) in _cases()) {
      testWidgets(name, (WidgetTester t) async {
        await pumpK3(t, w);
        await expectLater(
          find.byKey(const ValueKey('k3')),
          matchesGoldenFile('goldens/${name.replaceAll(' ', '_').replaceAll('+', 'p').replaceAll('-', 'm')}.png'),
        );
      });
    }

    testWidgets('lámina k3_sheet', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(900, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await pumpK3(
        t,
        SizedBox(
          width: 860,
          child: Wrap(
            spacing: TfSpace.s24,
            runSpacing: TfSpace.s24,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: <Widget>[for (final (String n, Widget w) in _cases()) _labeled(n, w)],
          ),
        ),
        key: const ValueKey('sheet'),
      );
      await expectLater(find.byKey(const ValueKey('sheet')), matchesGoldenFile('goldens/k3_sheet.png'));
    });
  });
}
