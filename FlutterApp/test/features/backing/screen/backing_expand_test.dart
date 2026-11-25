import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/features/backing/widgets/chords_area.dart';
import 'package:toneforge/features/backing/widgets/chords_expanded.dart';
import 'package:toneforge/features/backing/widgets/mixer_card.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';

import 'screen_support.dart';

void main() {
  testWidgets('expandido: el mezclador mide su alto natural y queda hueco debajo', (tester) async {
    final rig = await pumpBacking(tester, size: const Size(1100, 1400));
    final mixer = find.byType(MixerCard);
    expect(tester.getSize(mixer).height, MixerCard.idealHeight);
    await rig.container.read(chordsExpandedProvider.notifier).set(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(mixer).height, lessThan(MixerCard.minHeightLow));
    expect(tester.getBottomLeft(mixer).dy, lessThan(1400 - 100));
    await rig.container.read(chordsExpandedProvider.notifier).set(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(mixer).height, MixerCard.idealHeight);
  });

  testWidgets('la transicion dura ~150 ms: a mitad hay tira y rejilla', (tester) async {
    final rig = await pumpBacking(tester, size: const Size(1100, 1400));
    expect(find.byKey(const ValueKey<String>('chords-strip')), findsOneWidget);
    await rig.container.read(chordsExpandedProvider.notifier).set(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(find.byKey(const ValueKey<String>('chords-strip')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chords-grid')), findsOneWidget);
    expect(tester.getSize(find.byType(MixerCard)).height, lessThan(MixerCard.idealHeight));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey<String>('chords-strip')), findsNothing);
    expect(find.byType(ChordsArea), findsOneWidget);
  });

  testWidgets('expandir o plegar cierra la hoja de seccion', (tester) async {
    final rig = await pumpBacking(tester);
    final c = rig.container;
    c.read(sectionPopoverProvider.notifier).open('x');
    expect(c.read(sectionPopoverProvider), 'x');
    await c.read(chordsExpandedProvider.notifier).set(true);
    expect(c.read(sectionPopoverProvider), isNull);
    c.read(sectionPopoverProvider.notifier).open('y');
    await c.read(chordsExpandedProvider.notifier).set(false);
    expect(c.read(sectionPopoverProvider), isNull);
  });
}
