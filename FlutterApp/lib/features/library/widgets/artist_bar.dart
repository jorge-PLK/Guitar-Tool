import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/l10n/app_localizations.dart';

import '../../../theme/icons.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../library_store.dart';

/// Barra del artista abierto (LV:88-97): «‹ Artistas» + nombre («Sin artista» si vacío).
class ArtistBar extends ConsumerWidget {
  const ArtistBar({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: ref.read(libraryStoreProvider.notifier).closeArtist,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TfIconView(TfIcon.chevronLeft, size: TfSize.font14, color: TfColors.accent),
                const SizedBox(width: TfSpace.s4),
                Text(
                  l.library_artistsBack,
                  style: TfText.body().copyWith(color: TfColors.accent, decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: TfSpace.s14),
        Flexible(
          child: Text(
            name.isEmpty ? l.library_noArtist : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TfText.display(TfSize.font22).copyWith(color: TfColors.text, decoration: TextDecoration.none),
          ),
        ),
      ],
    );
  }
}
