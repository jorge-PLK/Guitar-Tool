import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/tab/tab_canvas_controller.dart';
import 'package:toneforge/features/tab/tab_source_menu.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Diálogo de guardado (ficha: `file_selector`). Devuelve la ruta o `null` si se cancela. Inyectable.
typedef TabSavePath = Future<String?> Function(String suggestedName);

final tabSavePathProvider = Provider<TabSavePath>((ref) => (name) async {
      final loc = await getSaveLocation(suggestedName: name);
      return loc?.path;
    });

/// `.gp` en base64 que genera alphaTab (`exportGpBase64`). Lo enchufa la zona del WebView; `null` = sin lienzo.
final tabExportDataProvider = Provider<Future<String?> Function()?>((ref) =>
    // ignore: deprecated_member_use
    () async => ref.exists(tabCanvasProvider) ? ref.read(tabCanvasProvider.notifier).exportGpBase64() : null);

/// «Exportar a Guitar Pro»: nombre sugerido, diálogo de guardado, `.gp` del lienzo y `tab.export {data, path}`.
Future<void> runTabExport(WidgetRef ref, AppLocalizations l) async {
  final store = ref.read(tabStoreProvider.notifier);
  final data = ref.read(tabExportDataProvider);
  if (data == null) return;
  final name = await store.loadExportName();
  if (name == null) return;
  final path = await ref.read(tabSavePathProvider)(name);
  if (path == null) return;
  final b64 = await data();
  if (b64 == null) return;
  final r = await store.export(data: b64, path: path);
  // Éxito: el aviso «Guardado …» lo manda el núcleo en `tab.state.flash` (no se duplica aquí).
  // `saved:false` (sin ruta no llega a pasar) = nada que avisar; un fallo llega como error.
  if (r == null) {
    final e = ref.read(tabStoreProvider).error;
    store.showFlash(l.tab_flashExportFailed(e?.message ?? ''));
  }
}

/// Cabecera (TabScreen.swift:121-149): «artista · título», «Tablatura» y las acciones.
class TabHeader extends ConsumerWidget {
  const TabHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tab = ref.watch(tabStoreProvider.select((s) => s.tab));
    final study = ref.watch(studyStoreProvider.select((s) => s.study));
    final ready = tab?.phase == TabPhase.ready;
    final subtitle = [
      for (final p in [study?.artist, study?.title])
        if (p != null && p.isNotEmpty) p,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: TfSpace.s12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s2,
            children: [
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted)),
              Text(l.tab_title, style: TfText.display(26).copyWith(color: TfColors.text)),
            ],
          ),
        ),
        const TabSourceMenu(),
        _EditToggle(
          label: l.tab_editNotes,
          active: tab?.editMode ?? false,
          onTap: ready
              ? () => ref
                  .read(tabStoreProvider.notifier)
                  .setEditMode(on: !(tab?.editMode ?? false))
              : null,
        ),
        TfSecondaryButton(
          label: l.tab_exportGuitarPro,
          height: TfSize.pillHeight,
          onPressed: ready && (tab?.tracks.isNotEmpty ?? false) ? () => runTabExport(ref, l) : null,
        ),
      ],
    );
  }
}

/// «Editar notas» (TabScreen.swift:132-142): alto 34, radio 8, h 14; activo en acento.
class _EditToggle extends StatelessWidget {
  const _EditToggle({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? TfColors.accent : TfColors.text;
    return Semantics(
      button: true,
      selected: active,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? TfOpacity.disabled : 1,
        child: MouseRegion(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: TfSize.pillHeight,
              padding: const EdgeInsets.symmetric(horizontal: TfSpace.s14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? TfColors.accentBg : TfColors.field,
                borderRadius: BorderRadius.circular(TfRadius.field),
                border: Border.all(
                  color: active ? TfColors.accent : TfColors.fieldLine,
                  width: TfStroke.hairline,
                ),
              ),
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TfText.body(TfSize.font13, active ? TfWeight.semibold : TfWeight.medium)
                    .copyWith(color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
