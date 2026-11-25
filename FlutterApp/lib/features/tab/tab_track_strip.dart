import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_pending_pill.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/features/tab/tab_track_pill.dart';
import 'package:toneforge/theme/tokens.dart';

/// Pistas con partitura (las «entries» de SwiftUI).
List<TabTrackInfo> tabEntries(TabState? tab) => <TabTrackInfo>[
      for (final TabTrackInfo t in tab?.tracks ?? const <TabTrackInfo>[])
        if (t.transcription == TabTranscription.ready) t,
    ];

/// Pistas en cola o transcribiéndose, aún sin partitura.
List<TabTrackInfo> tabPending(TabState? tab) => <TabTrackInfo>[
      for (final TabTrackInfo t in tab?.tracks ?? const <TabTrackInfo>[])
        if (t.transcription == TabTranscription.queued || t.transcription == TabTranscription.transcribing) t,
    ];

/// Tira horizontal de pastillas (`TabScreen.swift:206-242`), sin indicador de scroll.
class TabTrackStrip extends ConsumerWidget {
  const TabTrackStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TabState? tab = ref.watch(tabStoreProvider.select((TabStoreState s) => s.tab));
    final String? selected = tab?.selectedTrack;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: TfSpace.s8,
        children: <Widget>[
          for (final TabTrackInfo t in tabEntries(tab))
            TabTrackPill(key: ValueKey<String>(t.id), track: t, active: t.id == selected),
          for (final TabTrackInfo t in tabPending(tab)) TabPendingPill(key: ValueKey<String>('p-${t.id}'), name: t.name),
        ],
      ),
    );
  }
}
