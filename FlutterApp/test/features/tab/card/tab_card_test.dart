import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_card.dart';
import 'package:toneforge/features/tab/tab_footer.dart';
import 'package:toneforge/features/tab/tab_listen_selector.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/features/tab/tab_track_controls.dart';
import 'package:toneforge/features/tab/tab_track_strip.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';
import 'package:toneforge/widgets/tf_pill.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_toggle_button.dart';

import '../../../support/harness.dart';
import 'card_support.dart';

Color? _textColor(WidgetTester t, String text) => t.widget<Text>(find.text(text)).style?.color;

void main() {
  setUpAll(loadTfFonts);

  group('TabCard', () {
    testWidgets('compone selector, pastillas, controles, zona y pie', (tester) async {
      final tab = tabState(<TabTrackInfo>[track('g', name: 'Guitarra')], selected: 'g', header: '4/4 · 120 BPM');
      await pumpCard(tester, const SizedBox(height: 560, child: TabCard(stage: SizedBox(key: Key('stage')))), tab: tab);
      expect(find.byType(TabListenSelector), findsOneWidget);
      expect(find.byType(TabTrackStrip), findsOneWidget);
      expect(find.byType(TabTrackControls), findsOneWidget);
      expect(find.byType(TabFooter), findsOneWidget);
      expect(find.byKey(const Key('stage')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('stage'))).height, greaterThanOrEqualTo(tabStageMinHeight));
      expect(find.text('4/4 · 120 BPM'), findsOneWidget);
    });

    testWidgets('sin pistas no hay selector Oír ni controles', (tester) async {
      await pumpCard(tester, const SizedBox(height: 560, child: TabCard(stage: SizedBox())), tab: tabState(const []));
      expect(find.byType(TabListenSelector), findsNothing);
      expect(find.byType(TabTrackControls), findsNothing);
    });
  });

  group('Pastillas', () {
    testWidgets('activa e inactiva; tocar selecciona', (tester) async {
      final tab = tabState(<TabTrackInfo>[track('g', name: 'Guitarra'), track('b', name: 'Bajo')], selected: 'g');
      final store = await pumpCard(tester, const TabTrackStrip(), tab: tab);
      final pills = tester.widgetList<TfPill>(find.byType(TfPill)).toList();
      expect(pills.map((p) => p.active), <bool>[true, false]);
      await tester.tap(find.text('Bajo'));
      expect(store.calls, <String>['select:b']);
    });

    testWidgets('grupo atenuado al 0,55 con isDimmed', (tester) async {
      final tab = tabState(<TabTrackInfo>[track('g', name: 'Guitarra', dimmed: true), track('b', name: 'Bajo')]);
      await pumpCard(tester, const TabTrackStrip(), tab: tab);
      double opacityOf(String name) => tester
          .widget<Opacity>(find.ancestor(of: find.text(name), matching: find.byType(Opacity)).first)
          .opacity;
      expect(opacityOf('Guitarra'), TfOpacity.muted);
      expect(opacityOf('Bajo'), 1);
    });

    testWidgets('M y S miden 28x28 y llaman a mute y solo', (tester) async {
      final tab = tabState(<TabTrackInfo>[track('g', name: 'Guitarra', muted: true)]);
      final store = await pumpCard(tester, const TabTrackStrip(), tab: tab);
      final buttons = find.byType(TfToggleButton);
      expect(buttons, findsNWidgets(2));
      expect(tester.getSize(buttons.first), const Size(28, 28));
      expect(tester.getSize(buttons.last), const Size(28, 28));
      expect(tester.widget<TfToggleButton>(buttons.first).on, isTrue);
      expect(tester.widget<TfToggleButton>(buttons.first).semanticLabel, 'Activar Guitarra');
      await tester.tap(buttons.first);
      await tester.tap(buttons.last);
      expect(store.calls, <String>['mute:g', 'solo:g']);
    });

    testWidgets('altavoz solo en la pastilla escuchada', (tester) async {
      final tab = tabState(<TabTrackInfo>[track('g', name: 'Guitarra', listening: true), track('b', name: 'Bajo')]);
      await pumpCard(tester, const TabTrackStrip(), tab: tab);
      final speakers = find.byWidgetPredicate((w) => w is TfIconView && w.icon == TfIcon.speakerWave2Fill);
      expect(speakers, findsOneWidget);
      expect(find.descendant(of: find.byType(TfPill).first, matching: speakers), findsOneWidget);
    });

    testWidgets('pista pendiente con borde discontinuo', (tester) async {
      final tab = tabState(<TabTrackInfo>[
        track('g', name: 'Guitarra'),
        track('d', name: 'Batería', kind: TabTrackKind.drums, transcription: TabTranscription.queued),
      ]);
      await pumpCard(tester, const TabTrackStrip(), tab: tab);
      final pending = tester.widgetList<TfPill>(find.byType(TfPill)).where((p) => p.pending).toList();
      expect(pending.map((p) => p.label), <String>['Batería']);
      expect(find.byType(TfToggleButton), findsNWidgets(2));
    });
  });

  group('Selector Oír', () {
    testWidgets('Stems activo; tocar Transcripción llama setAllListening(true)', (tester) async {
      final tab = tabState(<TabTrackInfo>[track('g')]);
      final store = await pumpCard(tester, const TabListenSelector(), tab: tab);
      expect(_textColor(tester, 'Stems'), TfColors.accent);
      expect(_textColor(tester, 'Transcripción'), TfColors.text2);
      expect(find.text('Mixto'), findsNothing);
      await tester.tap(find.text('Transcripción'));
      await tester.tap(find.text('Stems'));
      expect(store.calls, <String>['listenAll:true', 'listenAll:false']);
    });

    testWidgets('Transcripción activa', (tester) async {
      final tab = tabState(<TabTrackInfo>[track('g')], mode: TabListenMode.transcription);
      await pumpCard(tester, const TabListenSelector(), tab: tab);
      expect(_textColor(tester, 'Transcripción'), TfColors.accent);
      expect(_textColor(tester, 'Stems'), TfColors.text2);
    });

    testWidgets('Mixto: ninguna activa y aparece «Mixto»', (tester) async {
      final tab = tabState(<TabTrackInfo>[track('g')], mode: TabListenMode.mixed);
      await pumpCard(tester, const TabListenSelector(), tab: tab);
      expect(_textColor(tester, 'Stems'), TfColors.text2);
      expect(_textColor(tester, 'Transcripción'), TfColors.text2);
      expect(find.text('Mixto'), findsOneWidget);
    });

    testWidgets('Sintetizando n/total con spinner', (tester) async {
      final tab = tabState(<TabTrackInfo>[
        track('g', synth: TabSynth.ready),
        track('b', synth: TabSynth.rendering),
        track('v', synth: TabSynth.rendering),
      ]);
      await pumpCard(tester, const TabListenSelector(), tab: tab);
      expect(find.text('Sintetizando 1/3…'), findsOneWidget);
      expect(find.byType(TfSpinner), findsOneWidget);
    });
  });

  group('Controles de pista', () {
    testWidgets('guitarra: afinación y casilla; la casilla llama setListening', (tester) async {
      final t = track('g', name: 'Guitarra');
      final store = await pumpCard(tester, TabTrackControls(track: t), tab: tabState(<TabTrackInfo>[t]));
      expect(find.text('Afinación'), findsOneWidget);
      expect(find.byType(TfDropdown<TabTuningPreset>), findsOneWidget);
      await tester.tap(find.text('Oír transcripción'));
      expect(store.calls, <String>['listen:g:true']);
      expect(tester.widget<TfCheckbox>(find.byType(TfCheckbox)).value, isFalse);
    });

    testWidgets('batería: sin afinación', (tester) async {
      final t = track('d', name: 'Batería', kind: TabTrackKind.drums, listening: true);
      await pumpCard(tester, TabTrackControls(track: t), tab: tabState(<TabTrackInfo>[t]));
      expect(find.text('Afinación'), findsNothing);
      expect(find.byType(TfDropdown<TabTuningPreset>), findsNothing);
      expect(tester.widget<TfCheckbox>(find.byType(TfCheckbox)).value, isTrue);
    });

    testWidgets('síntesis de la pista en curso: «Sintetizando…»', (tester) async {
      final t = track('g', synth: TabSynth.rendering);
      await pumpCard(tester, TabTrackControls(track: t), tab: tabState(<TabTrackInfo>[t]));
      expect(find.text('Sintetizando…'), findsOneWidget);
    });
  });

  group('Pie', () {
    const sel = TabSelectionInfo(track: 'g', beat: 1, tick: 0, summary: 'Compás 2, pulso 1 · cuerda 3, traste 5');

    testWidgets('fijo según la fuente, en muted', (tester) async {
      await pumpCard(tester, const TabFooter(), tab: tabState(<TabTrackInfo>[track('g')]));
      expect(find.text('Transcripción automática · revisa y corrige si hace falta'), findsOneWidget);
      expect(_textColor(tester, 'Transcripción automática · revisa y corrige si hace falta'), TfColors.muted);
      expect(tester.getSize(find.byType(TabFooter)).height, 18);
    });

    testWidgets('fuente Songsterr', (tester) async {
      await pumpCard(tester, const TabFooter(), tab: tabState(<TabTrackInfo>[track('g')], source: TabSource.songsterr));
      expect(find.text('Tablatura de Songsterr · revisa y corrige si hace falta'), findsOneWidget);
    });

    testWidgets('selección gana al fijo; el flash gana a la selección', (tester) async {
      final tab = tabState(<TabTrackInfo>[track('g')], selection: sel);
      final store = await pumpCard(tester, const TabFooter(), tab: tab);
      expect(find.text(sel.summary!), findsOneWidget);
      expect(_textColor(tester, sel.summary!), TfColors.muted);
      store.set(TabStoreState(tab: tab, flash: 'Guardado x.gp.'));
      await tester.pump();
      expect(find.text('Guardado x.gp.'), findsOneWidget);
      expect(find.text(sel.summary!), findsNothing);
      expect(_textColor(tester, 'Guardado x.gp.'), TfColors.accent);
      store.set(TabStoreState(tab: tab));
      await tester.pump();
      expect(find.text(sel.summary!), findsOneWidget);
    });
  });
}
