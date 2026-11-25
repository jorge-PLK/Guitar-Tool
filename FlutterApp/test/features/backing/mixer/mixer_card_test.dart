import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/widgets/mixer_card.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_fader.dart';
import 'package:toneforge/widgets/tf_level_bar.dart';
import 'package:toneforge/widgets/tf_mixer_channel.dart';
import 'package:toneforge/widgets/tf_slider.dart';
import 'package:toneforge/widgets/tf_toggle_button.dart';

import 'mixer_support.dart';

Widget card({bool compact = false, bool low = false, double? height}) => SizedBox(
      width: 1000,
      height: height,
      child: MixerCard(compact: compact, lowHeight: low),
    );

List<TfMixerChannel> channels(WidgetTester t) => t.widgetList<TfMixerChannel>(find.byType(TfMixerChannel)).toList();

void main() {
  testWidgets('orden fijo y se omiten los stems vacíos', (WidgetTester tester) async {
    await pumpMixer(tester, card(height: 346), tweak: (Map<String, Object?> open, Map<String, Object?> t) {
      t['channels'] = <Object?>[
        ch('other', 'other'),
        ch('piano', 'piano'),
        ch('guitar', 'guitar'),
        ch('bass', 'bass'),
        ch('vocals', 'vocals'),
        ch('drums', 'drums'),
      ];
      open['usesSeparatedGuitars'] = false;
      open['emptyStems'] = <Object?>[
        <String, Object?>{'kind': 'piano', 'name': 'Piano'},
      ];
    });
    double x(String s) => tester.getTopLeft(find.text(s)).dx;
    final List<String> names = <String>['Master', 'Voz', 'Batería', 'Bajo', 'Guitarra', 'Resto'];
    for (int i = 1; i < names.length; i++) {
      expect(x(names[i]), greaterThan(x(names[i - 1])), reason: names[i]);
    }
    expect(find.text('Piano'), findsNothing);
    expect(channels(tester).length, 6);
  });

  testWidgets('guitarras separadas: un canal por pista, renombrable con doble clic', (WidgetTester tester) async {
    final MixerRig rig = await pumpMixer(tester, card(height: 346));
    expect(find.text('Guitarra izq.'), findsOneWidget);
    expect(find.text('Guitarra der.'), findsOneWidget);
    expect(find.text('Guitarra'), findsNothing);
    expect(find.text('Guitarras en L y R'), findsOneWidget);
    await tester.tap(find.text('Guitarra izq.'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Guitarra izq.'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Lead');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(seconds: 1));
    expect(rig.callsOf('study.renameGuitar'), <Map<String, Object?>>[
      <String, Object?>{'role': 'left', 'name': 'Lead'},
    ]);
  });

  testWidgets('M y S llaman a setMix', (WidgetTester tester) async {
    final MixerRig rig = await pumpMixer(tester, card(height: 346));
    // Canales: Batería, Bajo, Guitarra izq., Guitarra der.; botones M,S por canal.
    final Finder buttons = find.byType(TfToggleButton);
    await tester.tap(buttons.at(0));
    await tester.pump();
    await tester.tap(buttons.at(3));
    await tester.pump();
    expect(rig.callsOf('study.setMix'), <Map<String, Object?>>[
      <String, Object?>{'channel': 'drums', 'mute': true},
      // En el fixture el bajo ya está en solo: pulsar S lo quita.
      <String, Object?>{'channel': 'bass', 'solo': false},
    ]);
  });

  testWidgets('fader: −60, 0 con imán y +6 llaman a setMix / setMaster', (WidgetTester tester) async {
    final MixerRig rig = await pumpMixer(tester, card(height: 346),
        tweak: (Map<String, Object?> open, Map<String, Object?> t) {
      t['channels'] = <Object?>[ch('drums', 'drums', gain: -20)];
      open['usesSeparatedGuitars'] = false;
    });
    // Primero el canal: el MockCore responde a setMaster con el transporte del fixture y repondría los canales.
    final Rect drums = tester.getRect(find.byType(TfFader).at(1));
    // 0 dB está a 6/66 del alto desde arriba; 1 dB por encima de 0 cae dentro del imán (±1,5).
    await tester.tapAt(drums.topCenter + Offset(0, drums.height * 5 / 66));
    await tester.pump();
    final List<Map<String, Object?>> mix = rig.callsOf('study.setMix');
    expect(mix.single['channel'], 'drums');
    expect(mix.single['gainDB'], 0);

    final Rect master = tester.getRect(find.byType(TfFader).at(0));
    await tester.tapAt(master.bottomCenter - const Offset(0, 0.01));
    await tester.pump();
    await tester.tapAt(master.topCenter + const Offset(0, 0.01));
    await tester.pump();
    final List<double> master0 = <double>[
      for (final Map<String, Object?> m in rig.callsOf('study.setMaster')) (m['gainDB']! as num).toDouble(),
    ];
    expect(master0.length, 2);
    expect(master0[0], closeTo(-60, 0.05));
    expect(master0[1], closeTo(6, 0.05));
    await tester.pump(const Duration(seconds: 1));

    expect(TfFader.dbAt(0, 150), 6);
    expect(TfFader.dbAt(150, 150), -60);
    expect(TfFader.dbAt(150 * 6 / 66, 150), 0);
  });

  test('barra de nivel: f a −60/−30/0 dB y 0 si atenuado', () {
    expect(TfLevelBar.fractionFor(-60), 0);
    expect(TfLevelBar.fractionFor(-30), 0.5);
    expect(TfLevelBar.fractionFor(0), 1);
    expect(TfLevelBar.fractionFor(-30, dim: true), 0);
  });

  testWidgets('study.levels llega a las barras y el canal atenuado tiene nivel 0', (WidgetTester tester) async {
    final MixerRig rig = await pumpMixer(tester, card(height: 346),
        tweak: (Map<String, Object?> open, Map<String, Object?> t) {
      t['channels'] = <Object?>[ch('drums', 'drums'), ch('bass', 'bass', muted: true)];
    });
    rig.core.emit('study.levels', <String, Object?>{
      'channels': <String, Object?>{
        'drums': <String, Object?>{'rmsDB': -22.0, 'peakDB': -11.0},
        'bass': <String, Object?>{'rmsDB': -18.0, 'peakDB': -9.0},
      },
    });
    await tester.pump(const Duration(milliseconds: 20));
    final List<TfLevelBar> bars = tester.widgetList<TfLevelBar>(find.byType(TfLevelBar)).toList();
    expect(bars[0].rmsDb, -22);
    expect(bars[0].dim, isFalse);
    expect(bars[1].dim, isTrue);
    expect(TfLevelBar.fractionFor(bars[1].rmsDb, dim: bars[1].dim), 0);
    expect(find.text('Silenciado'), findsOneWidget);
  });

  testWidgets('silencio o solo ajeno atenúan a 0,55', (WidgetTester tester) async {
    await pumpMixer(tester, card(height: 346), tweak: (Map<String, Object?> open, Map<String, Object?> t) {
      t['channels'] = <Object?>[ch('drums', 'drums'), ch('bass', 'bass', solo: true), ch('vocals', 'vocals')];
      t['anySolo'] = true;
    });
    final List<TfMixerChannel> list = channels(tester);
    // Master, Voz, Batería, Bajo.
    expect(list.map((TfMixerChannel c) => c.dimmed), <bool>[false, true, true, false]);
    expect(tester.widgetList<Opacity>(find.byType(Opacity)).where((Opacity o) => o.opacity == TfOpacity.muted).length, 2);
  });

  testWidgets('compacto: slider master y M/S sin faders', (WidgetTester tester) async {
    final MixerRig rig = await pumpMixer(tester, card(compact: true));
    expect(find.byType(TfFader), findsNothing);
    expect(find.byType(TfLevelBar), findsNothing);
    expect(find.byType(TfSlider), findsOneWidget);
    expect(find.byType(TfToggleButton), findsNWidgets(8));
    await tester.tap(find.byType(TfToggleButton).first);
    await tester.pump();
    expect(rig.callsOf('study.setMix').single['channel'], 'drums');
    final Rect s = tester.getRect(find.byType(TfSlider));
    await tester.tapAt(s.centerRight - const Offset(1, 0));
    await tester.pump();
    expect(rig.callsOf('study.setMaster').single['gainDB'], 6);
  });

  testWidgets('alto del canal según el alto del cuerpo', (WidgetTester tester) async {
    await pumpMixer(tester, card(height: MixerCard.minHeightLow, low: true));
    expect(channels(tester).first.height, 166);
    expect(MixerCard.minHeight, 270);
    expect(MixerCard.minHeightLow, 236);
    expect(MixerCard.idealHeight, 346);
    expect(MixerCard.channelHeightFor(210), 200);
    expect(MixerCard.channelHeightFor(286), 276);
    expect(TfMixerChannel.faderHeightFor(166), 40);
  });

  testWidgets('alto ideal: canal de 276', (WidgetTester tester) async {
    await pumpMixer(tester, card(height: MixerCard.idealHeight));
    expect(channels(tester).first.height, 276);
  });
}
