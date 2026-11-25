import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/tab_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_pill.dart';
import 'package:toneforge/widgets/tf_toggle_button.dart';

/// Icono por tipo de pista (`TabScreen.swift:285-292`).
TfIcon tabTrackIcon(TabTrackKind kind) => switch (kind) {
      TabTrackKind.bass => TfIcon.waveform,
      TabTrackKind.drums => TfIcon.circleGrid2x2,
      TabTrackKind.vocal => TfIcon.mic,
      _ => TfIcon.guitars,
    };

/// Grupo de una pista: pastilla + M + S, al 55 % si está atenuada (`TabScreen.swift:212-232`).
class TabTrackPill extends ConsumerWidget {
  const TabTrackPill({super.key, required this.track, required this.active});

  final TabTrackInfo track;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TabStore store = ref.read(tabStoreProvider.notifier);
    final Widget group = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TfSpace.s4,
      children: <Widget>[
        TfPill(
          label: track.name,
          active: active,
          onPressed: () => store.selectTrack(track.id),
          iconBuilder: (Color c) => TfIconView(tabTrackIcon(track.kind), size: TfSize.font12, color: c),
          trailing: track.listening
              ? TfIconView(
                  TfIcon.speakerWave2Fill,
                  size: TfSize.font11,
                  color: active ? TfColors.accent : TfColors.text2,
                  filled: true,
                )
              : null,
        ),
        TfToggleButton(
          text: l.tab_trackMuteLetter,
          on: track.muted,
          size: TfToggleSize.small,
          semanticLabel: track.muted ? l.tab_a11yUnmute(track.name) : l.tab_a11yMute(track.name),
          onPressed: () => store.toggleMute(track.id),
        ),
        TfToggleButton(
          text: l.tab_trackSoloLetter,
          on: track.solo,
          size: TfToggleSize.small,
          semanticLabel: l.tab_a11ySolo(track.name),
          onPressed: () => store.toggleSolo(track.id),
        ),
      ],
    );
    return Opacity(opacity: track.dimmed ? TfOpacity.muted : 1, child: group);
  }
}
