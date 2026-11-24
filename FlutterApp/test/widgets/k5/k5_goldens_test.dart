import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_list_row.dart';
import 'package:toneforge/widgets/tf_notice.dart';
import 'package:toneforge/widgets/tf_settings_group.dart';
import 'package:toneforge/widgets/tf_sidebar.dart';
import 'package:toneforge/widgets/tf_sidebar_cards.dart';
import 'package:toneforge/widgets/tf_state_message.dart';
import 'package:toneforge/widgets/tf_tab_bar.dart';

import '../../support/harness.dart';

void _noop() {}

Widget _sidebar({required bool active, required bool connected, String title = 'Wish You Were Here'}) {
  return SizedBox(
    height: 900,
    child: TfSidebar(
      logoTone: 'Tone',
      logoForge: 'Forge',
      entries: const <TfSidebarEntry>[
        TfSidebarEntry(icon: TfIcon.musicNoteList, label: 'Biblioteca', selected: true, onTap: _noop),
        TfSidebarEntry(icon: TfIcon.sliderVertical3, label: 'Backing track', selected: false, onTap: _noop),
        TfSidebarEntry(icon: TfIcon.musicQuarternote3, label: 'Tablatura', selected: false, onTap: _noop),
        TfSidebarEntry(icon: TfIcon.recordCircle, label: 'Grabar', selected: false, onTap: _noop),
        TfSidebarEntry(icon: TfIcon.film, label: 'Montaje', selected: false, onTap: _noop),
      ],
      bottom: <Widget>[
        const TfNavRow(icon: TfIcon.gearshape, label: 'Ajustes', active: false, onTap: _noop),
        TfSelectedTrackCard(title: title, artist: 'Pink Floyd', active: active, onTap: _noop),
        TfDeviceCard(
          title: connected ? 'Scarlett 2i2 USB' : 'Interfaz desconectada',
          subtitle: connected ? '44,1 kHz · 2 entradas' : 'Sin conexión',
          connected: connected,
        ),
      ],
    ),
  );
}

Widget _tabs() => const TfTabBar(
      labels: <String>['Audio', 'Vídeo', 'Biblioteca'],
      selected: 1,
      onSelect: _ignore,
    );

void _ignore(int _) {}

Widget _group() => SizedBox(
      width: 640,
      child: TfSettingsGroup(
        title: 'Interfaz de audio',
        note: 'Elige el dispositivo de entrada y salida que usará ToneForge.',
        children: <Widget>[
          for (final (String, String) r in const <(String, String)>[
            ('Dispositivo', 'Scarlett 2i2 USB'),
            ('Frecuencia de muestreo', '44100 Hz'),
            ('Latencia', '5,3 ms'),
          ])
            TfInfoRow(
              label: r.$1,
              trailing: Text(r.$2, style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text2)),
            ),
        ],
      ),
    );

Widget _rowContent(String title, String artist) => Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s2,
            children: <Widget>[
              Text(title, style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text)),
              Text(artist, style: TfText.body(13).copyWith(color: TfColors.muted)),
            ],
          ),
        ),
        SizedBox(
          width: 70,
          child: Text('3', style: TfText.body().copyWith(color: TfColors.text2)),
        ),
      ],
    );

Widget _list() => SizedBox(
      width: 640,
      child: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s10),
            child: Row(
              children: <Widget>[
                Expanded(child: TfTableHeaderCell('Canción')),
                SizedBox(width: 70, child: TfTableHeaderCell('Tomas')),
              ],
            ),
          ),
          TfListRow(child: _rowContent('Reposo', 'Artista')),
          TfListRow(key: const ValueKey<String>('hover'), child: _rowContent('Hover', 'Artista')),
          TfListRow(selected: true, child: _rowContent('Seleccionada', 'Artista')),
        ],
      ),
    );

Widget _notices() => const SizedBox(
      width: 520,
      child: Column(
        spacing: TfSpace.s12,
        children: <Widget>[
          TfNotice(messages: <String>['Tablatura importada con 2 compases ajustados.'], onDismiss: _noop),
          TfNotice(
            messages: <String>['No se pudo leer la fuente.', 'Prueba con otra versión.'],
            tone: TfNoticeTone.danger,
            onDismiss: _noop,
          ),
        ],
      ),
    );

Widget _state() => const SizedBox(
      width: 320,
      child: TfStateMessage(icon: TfIcon.musicNoteList, text: 'Aún no hay canciones. Importa una para empezar.'),
    );

Future<void> _hover(WidgetTester tester, Finder target) async {
  final TestGesture g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: const Offset(-50, -50));
  addTearDown(g.removePointer);
  await g.moveTo(tester.getCenter(target));
  await tester.pump();
}

Future<void> _golden(String name) =>
    expectLater(find.byKey(k5Boundary), matchesGoldenFile('goldens/$name.png'));

void main() {
  group('k5 goldens', () {
    testWidgets('barra lateral: fila activa, tarjeta activa, dispositivo conectado', (tester) async {
      await pumpK5(tester, _sidebar(active: true, connected: true), size: const Size(240, 900));
      await _golden('k5_sidebar_active');
    });

    testWidgets('barra lateral: tarjeta inactiva con título largo, dispositivo desconectado', (tester) async {
      await pumpK5(
        tester,
        _sidebar(active: false, connected: false, title: 'Un título larguísimo que no cabe en la tarjeta'),
        size: const Size(240, 900),
      );
      await _golden('k5_sidebar_inactive');
    });

    testWidgets('tab bar', (tester) async {
      await pumpK5(tester, _tabs(), size: const Size(360, 80));
      await _golden('k5_tab_bar');
    });

    testWidgets('grupo de ajustes con 3 InfoRow', (tester) async {
      await pumpK5(tester, _group(), size: const Size(640, 300));
      await _golden('k5_settings_group');
    });

    testWidgets('lista: cabecera, reposo, hover, seleccionada', (tester) async {
      await pumpK5(tester, _list(), size: const Size(640, 260));
      await _hover(tester, find.byKey(const ValueKey<String>('hover')));
      await _golden('k5_list_rows');
    });

    testWidgets('estado vacío', (tester) async {
      await pumpK5(tester, _state(), size: const Size(320, 120));
      await _golden('k5_state_message');
    });

    testWidgets('avisos accent y danger', (tester) async {
      await pumpK5(tester, _notices(), size: const Size(520, 160));
      await _golden('k5_notices');
    });

    testWidgets('lámina k5 sobre bg', (tester) async {
      await pumpK5(
        tester,
        Padding(
          padding: const EdgeInsets.all(TfSpace.s20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s20,
            children: <Widget>[
              SizedBox(height: 760, child: _sidebarSheet(active: true, connected: true)),
              SizedBox(height: 760, child: _sidebarSheet(active: false, connected: false)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: TfSpace.s20,
                children: <Widget>[_tabs(), _group(), _list(), _notices(), _state()],
              ),
            ],
          ),
        ),
        size: const Size(1500, 800),
      );
      await _golden('k5_sheet');
    });
  });
}

Widget _sidebarSheet({required bool active, required bool connected}) => SizedBox(
      height: 760,
      child: TfSidebar(
        logoTone: 'Tone',
        logoForge: 'Forge',
        entries: const <TfSidebarEntry>[
          TfSidebarEntry(icon: TfIcon.musicNoteList, label: 'Biblioteca', selected: true, onTap: _noop),
          TfSidebarEntry(icon: TfIcon.sliderVertical3, label: 'Backing track', selected: false, onTap: _noop),
          TfSidebarEntry(icon: TfIcon.film, label: 'Montaje', selected: false, onTap: _noop),
        ],
        bottom: <Widget>[
          const TfNavRow(icon: TfIcon.gearshape, label: 'Ajustes', active: false, onTap: _noop),
          TfSelectedTrackCard(title: 'Wish You Were Here', artist: 'Pink Floyd', active: active, onTap: _noop),
          TfDeviceCard(title: 'Scarlett 2i2 USB', subtitle: '44,1 kHz', connected: connected),
        ],
      ),
    );
