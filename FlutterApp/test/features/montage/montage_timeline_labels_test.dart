import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/montage.dart';
import 'package:toneforge/features/montage/montage_timeline_labels.dart';
import 'package:toneforge/features/montage/widgets/montage_timeline_painter.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

import '../../support/harness.dart';

MontageSnapshot _twoLanes() {
  final Map<String, Object?> j =
      (json.decode(File('../Contract/fixtures/montage/montage.open.result.json').readAsStringSync()) as Map).cast<String, Object?>();
  final List<Map<String, Object?>> lanes = (j['lanes']! as List).cast<Map<String, Object?>>();
  final Map<String, Object?> second = Map<String, Object?>.from(lanes.first)
    ..['id'] = '00000000-0000-0000-0000-000000000002'
    ..['takeId'] = '00000000-0000-0000-0000-000000000005'
    ..['partName'] = 'Bajo';
  return MontageSnapshot.fromJson(<String, Object?>{...j, 'lanes': <Object?>[...lanes, second]});
}

void main() {
  testWidgets('arrastrar desde el borde de la etiqueta llama a onMoveLane con los ids', (t) async {
    await t.runAsync(loadTfFonts);
    setTestSurface(t, const Size(400, 300));
    final MontageSnapshot s = _twoLanes();
    final List<(String, String)> moves = <(String, String)>[];
    await t.pumpWidget(WidgetsApp(
      color: TfColors.bg,
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      pageRouteBuilder: <T>(RouteSettings st, WidgetBuilder b) => PageRouteBuilder<T>(settings: st, pageBuilder: (c, a, b2) => b(c)),
      home: DefaultTextStyle(
        style: TfText.body().copyWith(color: TfColors.text),
        child: Align(
          alignment: Alignment.topLeft,
          child: MontageTimelineLabels(
            snapshot: s,
            analyzing: const <String>{},
            onOpenFraming: (_) {},
            onRotate: (_) {},
            onMoveLane: (String id, String to) => moves.add((id, to)),
            onAddCut: () {},
          ),
        ),
      ),
    ));
    await t.pump();
    final Finder from = find.byKey(ValueKey('montage-lane-${s.lanes[0].id}'));
    final Finder to = find.byKey(ValueKey('montage-lane-${s.lanes[1].id}'));
    // Borde derecho de la fila, en el hueco sin contenido del Spacer (no el icono).
    Offset edge(Finder f) => t.getTopLeft(f) + Offset(MontageTimelineGeometry.labelWidth * 0.5, t.getSize(f).height - 2);
    final TestGesture g = await t.startGesture(edge(from));
    await t.pump(const Duration(milliseconds: 50));
    await g.moveBy(const Offset(0, 20));
    await t.pump();
    final Offset target = edge(to);
    final Offset start = edge(from);
    for (int i = 1; i <= 5; i++) {
      await g.moveTo(Offset.lerp(start, target, i / 5)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
    expect(moves, <(String, String)>[(s.lanes[0].id, s.lanes[1].id)]);
  });
}
