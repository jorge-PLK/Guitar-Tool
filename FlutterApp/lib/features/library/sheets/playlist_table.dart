import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/features/library/playlist_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_scroll.dart';

/// Table frame of the playlist sheet (PI:241-243: bg @0.5, radius 10, fieldLine border)
/// with scroll. Fills the height its parent gives it; rows go in [children] (see [PlaylistRow]).
class PlaylistTable extends StatelessWidget {
  const PlaylistTable({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TfRadius.control);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TfColors.bg.withValues(alpha: TfOpacity.half),
        borderRadius: radius,
        border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: TfScroll(builder: (ctx, c) => ListView(controller: c, padding: EdgeInsets.zero, children: children)),
      ),
    );
  }
}

/// Row of the table: padding h14 v8 and a `line` divider underneath (PI:262-267).
class PlaylistRow extends StatelessWidget {
  const PlaylistRow({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s14, vertical: TfSpace.s8),
      child: child,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        onTap == null ? body : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: body),
        const TfDivider(),
      ],
    );
  }
}

/// Header of every list phase (PI:226-231): list name 16 semibold and a 13 muted subtitle.
class PlaylistHeader extends ConsumerWidget {
  const PlaylistHeader({required this.subtitle, super.key});

  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(playlistStoreProvider.select((p) => p.snapshot?.name ?? ''));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: TfSpace.s4,
      children: [
        Text(
          name.isEmpty ? AppLocalizations.of(context).library_plDefaultName : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TfText.body(16, TfWeight.semibold).copyWith(color: TfColors.text),
        ),
        Text(subtitle, style: TfText.body(13).copyWith(color: TfColors.muted)),
      ],
    );
  }
}

/// Title (14 semibold) over artist (12 muted) of a track (PI:255-260).
class PlaylistTrackTitle extends StatelessWidget {
  const PlaylistTrackTitle({required this.title, required this.artist, super.key});

  final String title;
  final String artist;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: TfSpace.s2,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text),
      ),
      Text(
        artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TfText.body(12).copyWith(color: TfColors.muted),
      ),
    ],
  );
}

/// Footer of buttons aligned to the right (PI:233-235).
class PlaylistActions extends StatelessWidget {
  const PlaylistActions(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.end, spacing: TfSpace.s8, children: children);
}

/// «Cerrar»: with a live queue only hides the sheet (the queue goes on); otherwise `playlist.close`.
/// If the core still reports `live`, the queue is kept too. Then resets the link field and pops the sheet.
Future<void> closePlaylistSheet(BuildContext context, WidgetRef ref) async {
  final store = ref.read(playlistStoreProvider.notifier);
  final link = ref.read(linkImportStoreProvider.notifier);
  final nav = Navigator.of(context);
  if (ref.read(playlistStoreProvider).isLive) {
    store.closeSheet();
  } else {
    final out = await store.close();
    if (out.result?.live ?? false) store.closeSheet();
  }
  link.reset();
  nav.maybePop();
}

/// «Probar con otro enlace»: discards the list (`close(force: true)`) and goes back to the link field.
Future<void> discardPlaylist(WidgetRef ref) async {
  final link = ref.read(linkImportStoreProvider.notifier);
  await ref.read(playlistStoreProvider.notifier).close(force: true);
  link.setText('');
  link.reset();
}
