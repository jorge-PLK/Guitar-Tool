import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

/// Alto de los botones de la barra de edición (`tablatura.md` §2.5); sin token en `theme/`.
const double tabEditButtonHeight = 32;

/// Piezas de batería en el orden de la barra: Bombo, Caja, Charles, Charles abierto, Tom, Platos.
const List<String> tabDrumPieces = <String>['kick', 'snare', 'hiHat', 'openHiHat', 'tom', 'crash'];

/// Barra de edición de Tablatura (`tablatura.md` §2.5): deshacer, rehacer y la acción de la pista.
class TabEditBar extends ConsumerWidget {
  const TabEditBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TabStore store = ref.read(tabStoreProvider.notifier);
    final bool canUndo = ref.watch(tabStoreProvider.select((TabStoreState s) => s.tab?.canUndo ?? false));
    final bool canRedo = ref.watch(tabStoreProvider.select((TabStoreState s) => s.tab?.canRedo ?? false));
    final TabSelectionInfo? selection =
        ref.watch(tabStoreProvider.select((TabStoreState s) => s.tab?.selection));
    final bool drums = ref.watch(tabStoreProvider.select(_selectedTrackIsDrums));
    final TextStyle muted = TfText.body(TfSize.font13).copyWith(color: TfColors.muted);

    final bool hasNote = selection?.hasNote == true;
    final bool hasSelection = selection != null;

    return Row(
      spacing: TfSpace.s10,
      children: <Widget>[
        TfSecondaryButton(
          label: l.tab_undo,
          height: tabEditButtonHeight,
          onPressed: canUndo ? () => store.edit(TabEditParams.undo()) : null,
        ),
        TfSecondaryButton(
          label: l.tab_redo,
          height: tabEditButtonHeight,
          onPressed: canRedo ? () => store.edit(TabEditParams.redo()) : null,
        ),
        if (drums) ...<Widget>[
          for (final String piece in tabDrumPieces)
            TfSecondaryButton(
              label: _capitalize(_pieceLabel(l, piece)),
              height: tabEditButtonHeight,
              onPressed: hasSelection ? () => store.edit(TabEditParams.hit(piece: piece)) : null,
            ),
          Flexible(child: Text(l.tab_drumKeysHint, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ] else ...<Widget>[
          TfSecondaryButton(
            label: l.tab_addNote,
            height: tabEditButtonHeight,
            onPressed: hasNote ? () => store.edit(TabEditParams.addNote()) : null,
          ),
          Semantics(
            label: l.tab_a11yShortenNote,
            child: TfSecondaryButton(
              label: '–',
              height: tabEditButtonHeight,
              onPressed: hasNote ? () => store.edit(TabEditParams.duration(sign: -1)) : null,
            ),
          ),
          Semantics(
            label: l.tab_a11yLengthenNote,
            child: TfSecondaryButton(
              label: '+',
              height: tabEditButtonHeight,
              onPressed: hasNote ? () => store.edit(TabEditParams.duration(sign: 1)) : null,
            ),
          ),
          TfSecondaryButton(
            label: l.tab_delete,
            height: tabEditButtonHeight,
            onPressed: hasNote ? () => store.edit(TabEditParams.delete()) : null,
          ),
          Flexible(
            child: Text(
              defaultTargetPlatform == TargetPlatform.macOS ? l.tab_keysHintMac : l.tab_keysHintWin,
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

/// Verdadero si la pista seleccionada es de batería (mismo criterio que `tab_track_controls.dart`).
bool _selectedTrackIsDrums(TabStoreState s) {
  final TabState? tab = s.tab;
  if (tab == null) return false;
  for (final TabTrackInfo t in tab.tracks) {
    if (t.id == tab.selectedTrack) return t.kind == TabTrackKind.drums;
  }
  return false;
}

String _pieceLabel(AppLocalizations l, String piece) => switch (piece) {
      'kick' => l.tab_pieceKick,
      'snare' => l.tab_pieceSnare,
      'hiHat' => l.tab_pieceHiHat,
      'openHiHat' => l.tab_pieceOpenHiHat,
      'tom' => l.tab_pieceTom,
      _ => l.tab_pieceCrash,
    };

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
