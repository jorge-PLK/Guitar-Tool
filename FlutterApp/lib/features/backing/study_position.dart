import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/features/backing/study_store.dart';

/// Posición y estado de reproducción a la cadencia de `study.position` (≤ 30 Hz), aparte del store para que
/// el resto de la pantalla no se reconstruya. Se reinicia al abrir otro estudio.
final studyPositionProvider =
    NotifierProvider<StudyPositionNotifier, StudyPositionEvent>(StudyPositionNotifier.new);

class StudyPositionNotifier extends Notifier<StudyPositionEvent> {
  @override
  StudyPositionEvent build() {
    final core = ref.watch(coreClientProvider);
    ref.watch(studyStoreProvider.select((s) => s.openProjectId));
    final sub = core.on('study.position', StudyPositionEvent.fromJson).listen((e) => state = e);
    ref.onDispose(sub.cancel);
    // Seek o pausa: el núcleo calla `study.position` si no cambia, así que el transporte también la fija.
    ref.listen(studyStoreProvider.select((s) => s.transport), (_, t) {
      if (t == null) return;
      if (t.playing && state.playing) return;
      if (state.seconds == t.position && state.playing == t.playing) return;
      state = StudyPositionEvent(seconds: t.position, playing: t.playing);
    });
    final t = ref.read(studyStoreProvider).transport;
    return StudyPositionEvent(seconds: t?.position ?? 0, playing: t?.playing ?? false);
  }
}
