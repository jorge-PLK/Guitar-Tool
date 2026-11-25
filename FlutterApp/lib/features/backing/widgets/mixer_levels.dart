import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/core/core_providers.dart';
import 'package:toneforge/features/backing/study_store.dart';

/// Último `study.levels` (≤ 30 Hz) por id de canal. Aparte del store para que solo se repinten las barras.
/// Se reinicia al abrir otro estudio. El núcleo manda -120 dB al quedar en silencio.
final mixerLevelsProvider =
    NotifierProvider<MixerLevelsNotifier, Map<String, StudyMeter>>(MixerLevelsNotifier.new);

class MixerLevelsNotifier extends Notifier<Map<String, StudyMeter>> {
  @override
  Map<String, StudyMeter> build() {
    final core = ref.watch(coreClientProvider);
    ref.watch(studyStoreProvider.select((s) => s.openProjectId));
    final sub = core.on('study.levels', StudyLevelsEvent.fromJson).listen((e) {
      state = <String, StudyMeter>{...state, ...e.channels};
    });
    ref.onDispose(sub.cancel);
    return const <String, StudyMeter>{};
  }
}
