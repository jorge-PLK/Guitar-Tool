import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/core/core_client.dart' show CoreError;
import 'package:toneforge/features/record/record_offset_actions.dart';
import 'package:toneforge/features/record/record_store.dart';
import 'package:toneforge/features/record/record_topics_provider.dart';
import 'package:toneforge/features/record/sheets/add_part_sheet.dart';
import 'package:toneforge/features/record/sheets/offset_sheet.dart';
import 'package:toneforge/features/record/widgets/record_body.dart';
import 'package:toneforge/features/record/widgets/record_topic_chooser.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/shell/shell_providers.dart';
import 'package:toneforge/shell/shell_route.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_card.dart';
import 'package:toneforge/widgets/tf_progress.dart';
import 'package:toneforge/widgets/tf_state_message.dart';

/// Proyecto con el que hay que tener abierta Grabar: el elegido, ya conocido en la biblioteca y separado.
final _recordTargetProvider = Provider.autoDispose<String?>((ref) {
  final String? id = ref.watch(selectedProjectProvider);
  if (id == null) return null;
  final ProjectSummary? p = _find(ref.watch(recordTopicsProvider).value, id);
  return p != null && p.separationState == SeparationState.done ? id : null;
});

ProjectSummary? _find(List<ProjectSummary>? list, String id) {
  for (final ProjectSummary p in list ?? const <ProjectSummary>[]) {
    if (p.id == id) return p;
  }
  return null;
}

/// Pantalla Grabar (RecordView.swift:7-85): selector de tema, carga, aviso de tema sin separar o cuerpo.
/// `record.open` al elegir un tema separado; `record.close` al salir o cambiar de tema.
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  late final RecordStore _store = ref.read(recordStoreProvider.notifier);
  ProviderSubscription<String?>? _sub;
  String? _openId;
  Future<void> _chain = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual<String?>(_recordTargetProvider, (String? _, String? next) => _switchTo(next), fireImmediately: true);
  }

  void _switchTo(String? next) {
    final String? previous = _openId;
    _openId = next;
    if (previous == next) return;
    _chain = _chain.then((_) async {
      if (previous != null) await _store.close();
      if (next != null) await _store.open(next);
    }).catchError((Object _) {});
  }

  bool _offsetOpen = false;

  Future<void> _openOffsetSheet() async {
    if (_offsetOpen || !mounted) return;
    _offsetOpen = true;
    try {
      await showOffsetSheet(context);
    } finally {
      _offsetOpen = false;
    }
  }

  Future<void> _goMontage() async {
    _openId = null;
    await _chain;
    await _store.close(toMontage: true);
    if (mounted) ref.read(shellRouteProvider.notifier).select(ShellRoute.montage);
  }

  @override
  void dispose() {
    _sub?.close();
    final String? open = _openId;
    _openId = null;
    if (open != null) {
      final Future<void> previous = _chain;
      unawaited(previous.then((_) => _store.close()).catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? id = ref.watch(selectedProjectProvider);
    final AsyncValue<List<ProjectSummary>> topics = ref.watch(recordTopicsProvider);
    final List<ProjectSummary>? list = topics.value;
    if (list == null) return const _Loading();
    final ProjectSummary? project = id == null ? null : _find(list, id);
    if (project == null) {
      return RecordTopicChooser(topics: list, onPick: ref.read(selectedProjectProvider.notifier).select);
    }
    if (project.separationState != SeparationState.done) return const _NotSeparated();
    // La hoja de desfase se abre al pasar `snapshot.offset` a no nulo (toma nueva o menú de toma), solo una vez.
    ref.listen<bool>(recordStoreProvider.select((s) => s.offset != null), (bool? _, bool on) {
      if (on) unawaited(_openOffsetSheet());
    });
    final RecordState s = ref.watch(recordStoreProvider);
    final CoreError? error = s.error;
    if (!s.opened && error != null) {
      // TODO(ola3): traducir por `error.code` cuando haya claves ARB genéricas de Grabar; hoy `message` del núcleo.
      return TfStateMessage(icon: TfIcon.exclamationmarkTriangle, text: error.message);
    }
    if (!s.opened || s.snapshot == null) return const _Loading();
    return RecordBody(
      projectId: project.id,
      title: project.title,
      artist: project.artist,
      onGoMontage: _goMontage,
      onAddPart: () => unawaited(showAddPartSheet(context)),
      onAdjustOffset: (String takeId) => unawaited(_store.adjustOffset(takeId)),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(child: TfSpinner.small());
}

/// Tema elegido pero sin stems (RV:57-66).
class _NotSeparated extends ConsumerWidget {
  const _NotSeparated();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(TfSpace.s36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          TfCard(
            child: Padding(
              padding: const EdgeInsets.all(TfSpace.s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(l.record_notSeparatedTitle, style: TfText.display(TfSize.font18).copyWith(color: TfColors.text)),
                  const SizedBox(height: TfSpace.s12),
                  Text(l.record_notSeparatedBody, style: TfText.body().copyWith(color: TfColors.muted)),
                  const SizedBox(height: TfSpace.s12),
                  TfSecondaryButton(
                    label: l.record_goLibrary,
                    onPressed: () => ref.read(shellRouteProvider.notifier).select(ShellRoute.library),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
