import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/l10n/app_localizations.dart';

import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../library_store.dart';
import 'artist_avatar.dart';

/// Interlineado fijo de los dos textos del recuadro: el delegado de la cuadrícula necesita un
/// alto de fila determinista (ver `artistTileCaptionHeight`).
const double artistTileLineHeight = 1.25;
const double _nameSize = 14;
const double _countSize = 12;

/// Alto del pie del recuadro (separación + nombre + separación + «N temas»), sin el cuadrado.
const double artistTileCaptionHeight =
    TfSpace.s8 + _nameSize * artistTileLineHeight + TfSpace.s8 + _countSize * artistTileLineHeight;

/// Bytes de una URL `data:`; `null` si no es válida.
Uint8List? decodeDataUrl(String? url) {
  if (url == null || !url.startsWith('data:')) return null;
  try {
    return UriData.parse(url).contentAsBytes();
  } on FormatException {
    return null;
  }
}

/// Recuadro de un artista (AG:7-34): foto o iniciales, nombre y «N temas».
class ArtistTile extends ConsumerStatefulWidget {
  const ArtistTile({super.key, required this.name, required this.count, required this.onTap});

  /// Vacío = «Sin artista».
  final String name;
  final int count;
  final VoidCallback onTap;

  @override
  ConsumerState<ArtistTile> createState() => _ArtistTileState();
}

class _ArtistTileState extends ConsumerState<ArtistTile> {
  bool _hover = false;
  Uint8List? _photo;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(ArtistTile old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      _photo = null;
      _loadPhoto();
    }
  }

  /// Solo los recuadros construidos piden foto (el builder de la cuadrícula es perezoso).
  Future<void> _loadPhoto() async {
    final name = widget.name;
    if (name.isEmpty) return;
    final url = await ref.read(libraryStoreProvider.notifier).artistPhoto(name);
    final bytes = decodeDataUrl(url);
    if (!mounted || widget.name != name || bytes == null) return;
    setState(() => _photo = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final unknown = widget.name.isEmpty;
    final title = unknown ? l.library_noArtist : widget.name;
    final count = l.library_artistTrackCount(widget.count);
    const radius = BorderRadius.all(Radius.circular(TfRadius.card));
    final photo = _photo;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: l.library_artistTileLabel(title, widget.count),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: _hover
                          ? TfColors.accent.withValues(alpha: TfOpacity.borderAccent)
                          : TfColors.line,
                      width: TfStroke.hairline,
                    ),
                  ),
                  position: DecorationPosition.foreground,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: photo != null
                        ? Image.memory(
                            photo,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (c, e, s) => ArtistAvatar(name: widget.name, isUnknown: unknown),
                          )
                        : ArtistAvatar(name: widget.name, isUnknown: unknown),
                  ),
                ),
              ),
              const SizedBox(height: TfSpace.s8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TfText.body(_nameSize, TfWeight.semibold).copyWith(
                  color: TfColors.text,
                  height: artistTileLineHeight,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: TfSpace.s8),
              Text(
                count,
                maxLines: 1,
                style: TfText.body(_countSize).copyWith(
                  color: TfColors.muted,
                  height: artistTileLineHeight,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
