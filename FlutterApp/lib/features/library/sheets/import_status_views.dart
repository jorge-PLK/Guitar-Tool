import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/features/library/sheets/import_banner.dart';
import 'package:toneforge/features/library/source_messages.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/selected_project.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_progress.dart';

/// Pantallas de estado de la hoja de importación. Cada una pinta su cuerpo y su pie;
/// [onClose] cierra la hoja (la hoja hace `reset()` + pop).

/// Pie de botones alineado a la derecha (`actions`, LS:801).
class _Actions extends StatelessWidget {
  const _Actions(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (final c in children) {
      if (spaced.isNotEmpty) spaced.add(const SizedBox(width: TfSpace.s8));
      spaced.add(c);
    }
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: spaced);
  }
}

/// Spinner + texto + «Cancelar» (comparten resolviendo y preparando).
class _Waiting extends ConsumerWidget {
  const _Waiting({required this.label, this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const TfSpinner.small(),
            const SizedBox(width: TfSpace.s12),
            Text(label, style: TfText.body().copyWith(color: TfColors.text)),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: TfSpace.s16),
          Text(hint!, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
        ],
        const SizedBox(height: TfSpace.s16),
        _Actions([
          TfSecondaryButton(
            label: l.library_importCancel,
            onPressed: () => ref.read(linkImportStoreProvider.notifier).cancel(),
          ),
        ]),
      ],
    );
  }
}

/// «Leyendo metadatos…» / «Buscando en YouTube…» (LS:584-593).
class ImportResolvingView extends ConsumerWidget {
  const ImportResolvingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final searching = ref.watch(linkImportStoreProvider.select((s) => s.resolvePhase)) == LinkResolvePhase.searching;
    return _Waiting(
      label: searching ? l.library_importSearchingYt : l.library_importReadingMeta,
      hint: searching ? l.library_importSlow : null,
    );
  }
}

/// «Preparando…» (LS:572-580).
class ImportPreparingView extends ConsumerWidget {
  const ImportPreparingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _Waiting(label: AppLocalizations.of(context).library_importPreparing);
}

/// Error de fuente (LS:759-789).
class ImportErrorView extends ConsumerWidget {
  const ImportErrorView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final s = ref.watch(linkImportStoreProvider);
    final store = ref.read(linkImportStoreProvider.notifier);
    final error = s.error;
    final t = error == null ? (title: loc.library_importFailTitle, detail: '') : sourceErrorTexts(loc, error);
    final action = s.errorAction;
    final (String, VoidCallback)? primary = switch (action) {
      LinkErrorAction.updateAndRetry => (loc.library_importUpdateRetry, store.updateAndRetry),
      LinkErrorAction.tryOtherLink => (loc.library_importOtherLink, () => _backToField(store)),
      LinkErrorAction.pasteYoutube => (loc.library_importPasteYt, () => _backToField(store)),
      LinkErrorAction.retry => (loc.library_importRetry, store.retry),
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TfIconView(TfIcon.exclamationmarkTriangleFill, size: TfSize.noticeIcon, color: TfColors.danger),
            const SizedBox(width: TfSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: TfText.body(TfSize.font15, TfWeight.semibold).copyWith(color: TfColors.text)),
                  if (t.detail.isNotEmpty) ...[
                    const SizedBox(height: TfSpace.s6),
                    SelectableRegion(
                      selectionControls: emptyTextSelectionControls,
                      child: Text(t.detail, style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (s.alreadyLatest) ...[
          const SizedBox(height: TfSpace.s14),
          ImportBanner(text: loc.library_importAlreadyLatest, tone: ImportBannerTone.warning),
        ],
        const SizedBox(height: TfSpace.s14),
        _Actions([
          TfSecondaryButton(label: loc.library_importClose, onPressed: onClose),
          if (primary != null) TfPrimaryButton(label: primary.$1, onPressed: primary.$2),
        ]),
      ],
    );
  }

  static void _backToField(LinkImportStore store) {
    store.setText('');
    store.reset();
  }
}

/// «Tema importado» (LS:791-796).
class ImportDoneView extends ConsumerWidget {
  const ImportDoneView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final notices = ref.watch(linkImportStoreProvider.select((s) => s.notices));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Headline(TfIcon.checkmarkCircleFill),
        for (final n in notices) ...[
          const SizedBox(height: TfSpace.s14),
          ImportBanner(text: n, tone: ImportBannerTone.warning),
        ],
        const SizedBox(height: TfSpace.s14),
        _Actions([TfPrimaryButton(label: l.library_importClose, onPressed: onClose)]),
      ],
    );
  }
}

/// Icono ok + título 15 semibold de «hecho» y «repetido».
class _Headline extends StatelessWidget {
  const _Headline(this.icon, {this.repeated = false});

  final TfIcon icon;
  final bool repeated;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        TfIconView(icon, size: TfSize.noticeIcon, color: TfColors.ok),
        const SizedBox(width: TfSpace.s8),
        Text(
          repeated ? l.library_importRepeatedTitle : l.library_importDone,
          style: TfText.body(TfSize.font15, TfWeight.semibold).copyWith(color: TfColors.ok),
        ),
      ],
    );
  }
}

/// «Ya está en la biblioteca» (LS:550-568).
class ImportRepeatedView extends ConsumerWidget {
  const ImportRepeatedView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final existing = ref.watch(linkImportStoreProvider.select((s) => s.existing));
    final artist = existing?.artist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Headline(TfIcon.checkmarkCircleFill, repeated: true),
        if (existing != null) ...[
          const SizedBox(height: TfSpace.s14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(TfSpace.s12),
            decoration: BoxDecoration(
              color: TfColors.field,
              borderRadius: BorderRadius.circular(TfRadius.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TfText.body(TfSize.font15, TfWeight.semibold).copyWith(color: TfColors.text),
                ),
                if (artist != null && artist.isNotEmpty) ...[
                  const SizedBox(height: TfSpace.s2),
                  Text(artist, style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: TfSpace.s14),
        Text(l.library_importRepeatedBody, style: TfText.body(TfSize.font12).copyWith(color: TfColors.muted)),
        const SizedBox(height: TfSpace.s14),
        _Actions([
          TfSecondaryButton(label: l.library_importClose, onPressed: onClose),
          TfPrimaryButton(
            label: l.library_importOpen,
            onPressed: () {
              if (existing != null) ref.read(selectedProjectProvider.notifier).select(existing.id);
              onClose();
            },
          ),
        ]),
      ],
    );
  }
}
