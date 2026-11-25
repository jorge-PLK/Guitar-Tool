import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/record/record_audio_actions.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/sheets/take_viewer_sheet.dart';
import 'package:toneforge/features/record/widgets/parts_panel.dart';
import 'package:toneforge/features/record/widgets/punch_timeline.dart';
import 'package:toneforge/features/record/widgets/record_bar.dart';
import 'package:toneforge/features/record/widgets/record_header.dart';
import 'package:toneforge/features/record/widgets/record_mixer.dart';
import 'package:toneforge/features/record/widgets/record_preview.dart';
import 'package:toneforge/features/record/widgets/status_lines.dart';
import 'package:toneforge/features/settings/audio_store.dart';
import 'package:toneforge/theme/tokens.dart';

/// Ancho fijo del panel «Partes» (RV:114).
const double _partsWidth = 320;

/// Marco de Grabar (RecordView.swift:101-118): cabecera, columna izquierda y panel «Partes». Sin scroll general.
class RecordBody extends ConsumerStatefulWidget {
  const RecordBody({
    super.key,
    required this.projectId,
    required this.title,
    this.artist,
    required this.onGoMontage,
    required this.onAddPart,
    this.onAdjustOffset,
  });

  final String projectId;
  final String title;
  final String? artist;
  final VoidCallback onGoMontage;
  final VoidCallback onAddPart;
  final ValueChanged<String>? onAdjustOffset;

  @override
  ConsumerState<RecordBody> createState() => _RecordBodyState();
}

class _RecordBodyState extends ConsumerState<RecordBody> {
  /// Nivel de «Tu guitarra» (RV:127-128): máximo de `audio.levels` sobre los canales `guitarIn` (1-based).
  final ValueNotifier<double> _inputLevel = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    // Niveles de `audio.levels` y canales `guitarIn` que `record_store` guarda al entrar.
    ref.listenManual<List<double>?>(audioStoreProvider.select((s) => s.levels?.levels), (_, _) => _updateLevel());
    ref.listenManual<List<int>>(recordStoreProvider.select((s) => s.guitarIn), (_, _) => _updateLevel(), fireImmediately: true);
  }

  void _updateLevel() {
    _inputLevel.value = guitarInputLevel(
      ref.read(recordStoreProvider).guitarIn,
      ref.read(audioStoreProvider).levels?.levels ?? const <double>[],
    );
  }

  Future<void> _viewTake(String takeId) async {
    if (!await ref.read(recordStoreProvider.notifier).prepareViewTake() || !mounted) return;
    await showTakeViewer(context, projectId: widget.projectId, takeId: takeId);
  }

  @override
  void dispose() {
    _inputLevel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = ref.watch(recordStoreProvider.select((s) => s.isBusy));
    final bool punch = ref.watch(recordStoreProvider.select((s) => s.snapshot?.punch.enabled ?? false));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s36, vertical: TfSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RecordHeader(title: widget.title, artist: widget.artist, busy: busy, onGoMontage: widget.onGoMontage),
          const SizedBox(height: TfSpace.s14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // La vista previa toma el espacio libre conservando 16:9; el mezclador expandido se lo quita.
                      const Expanded(child: RecordPreview()),
                      const SizedBox(height: TfSpace.s14),
                      const RecordBar(),
                      const SizedBox(height: TfSpace.s14),
                      const RecordStatusLines(),
                      if (punch) ...<Widget>[const SizedBox(height: TfSpace.s14), const PunchTimeline()],
                      const SizedBox(height: TfSpace.s14),
                      // `mixerExpanded` (RV:95) es estado local de `RecordMixer`: al crecer, el `Expanded` de arriba encoge la vista previa.
                      RecordMixer(inputLevel: _inputLevel),
                    ],
                  ),
                ),
                const SizedBox(width: TfSpace.s20),
                SizedBox(
                  width: _partsWidth,
                  child: SingleChildScrollView(
                    child: PartsPanel(
                      onViewTake: _viewTake,
                      onAddPart: widget.onAddPart,
                      onAdjustOffset: widget.onAdjustOffset,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
