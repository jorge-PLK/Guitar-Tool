import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/songsterr_pairing_row.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_scroll.dart';

/// Paso `.pairing` de la hoja de Songsterr (TSS:205-248): tabla de emparejamiento, pistas
/// extra, avisos y botonera.
class SongsterrPairing extends ConsumerWidget {
  const SongsterrPairing({super.key, required this.pairing});

  final SongsterrPairingInfo? pairing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final SongsterrStore store = ref.read(songsterrStoreProvider.notifier);
    final SongsterrPairingInfo? p = pairing;
    final List<Widget> rows = <Widget>[
      if (p != null)
        for (final SongsterrSlotInfo slot in p.slots) ...songsterrSlotRows(l, slot, store.assign),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s10,
      children: <Widget>[
        Text(l.tab_sheetPairingHelp, style: const TextStyle(color: TfColors.muted)),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: _Table(rows: rows),
          ),
        ),
        if (p != null && p.extraNames.isNotEmpty)
          Text(
            l.tab_sheetExtraTracks(p.extraNames.join(', ')),
            style: const TextStyle(color: TfColors.muted),
          ),
        if (p != null && p.warnings.isNotEmpty) _Warnings(items: p.warnings),
        Row(
          spacing: TfSpace.s12,
          children: <Widget>[
            TfSecondaryButton(label: l.tab_sheetBackShort, height: TfSpace.s36, onPressed: store.back),
            TfSecondaryButton(
              label: l.tab_sheetAllAutomatic,
              height: TfSpace.s36,
              onPressed: store.allAutomatic,
            ),
            const Spacer(),
            TfSecondaryButton(label: l.tab_sheetCancel, height: TfSpace.s36, onPressed: store.close),
            TfPrimaryButton(label: l.tab_sheetAccept, onPressed: store.accept),
          ],
        ),
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12),
      decoration: BoxDecoration(
        color: TfColors.field,
        borderRadius: BorderRadius.circular(TfRadius.control),
        border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: TfScroll(
        builder: (BuildContext context, ScrollController c) => ListView.separated(
          controller: c,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: rows.length,
          separatorBuilder: (_, _) => const TfDivider(),
          itemBuilder: (_, int i) => rows[i],
        ),
      ),
    );
  }
}

class _Warnings extends StatelessWidget {
  const _Warnings({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: TfSize.songsterrWarningsMaxHeight),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(TfSpace.s12),
        decoration: BoxDecoration(
          color: TfColors.accentBg,
          borderRadius: BorderRadius.circular(TfRadius.control),
        ),
        child: TfScroll(
          builder: (BuildContext context, ScrollController c) => ListView.separated(
            controller: c,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: TfSpace.s4),
            itemBuilder: (_, int i) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: TfSpace.s6,
              children: <Widget>[
                const TfIconView(TfIcon.exclamationmarkTriangle,
                    size: TfSize.font12, color: TfColors.accent),
                Expanded(child: Text(items[i], style: const TextStyle(color: TfColors.text2))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
