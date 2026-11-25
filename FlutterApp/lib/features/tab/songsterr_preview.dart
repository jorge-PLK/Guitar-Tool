import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/features/tab/songsterr_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_web_view.dart';

/// User agent de Safari, el mismo que `SongsterrHiddenPage.userAgent` del núcleo (el estado no lo trae).
const String songsterrPreviewUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.0 Safari/605.1.15';

/// Panel de vista previa de la hoja de Songsterr (SP): cabecera con «Usar esta» y «Cerrar», y un WebView
/// secundario con la página de la canción marcada. Recarga solo si cambia la URL (`previewUrl`).
class SongsterrPreview extends ConsumerStatefulWidget {
  const SongsterrPreview({super.key, required this.selected, required this.onClose});

  /// Canción marcada; sin ella «Usar esta» queda deshabilitado y no se carga nada.
  final SongsterrSongInfo? selected;
  final VoidCallback onClose;

  @override
  ConsumerState<SongsterrPreview> createState() => _SongsterrPreviewState();
}

class _SongsterrPreviewState extends ConsumerState<SongsterrPreview> {
  late final TfWebViewController _web;
  String? _loaded;

  @override
  void initState() {
    super.initState();
    _web = ref.read(tfWebViewControllerFactoryProvider)(
      const TfWebViewConfig(userAgent: songsterrPreviewUserAgent),
    );
    _load();
  }

  @override
  void didUpdateWidget(SongsterrPreview old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final String? url = widget.selected?.previewUrl;
    if (url == null || url == _loaded) return;
    _loaded = url;
    _web.loadUrl(Uri.parse(url));
  }

  @override
  void dispose() {
    _web.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool hasSong = widget.selected != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TfSpace.s10,
      children: <Widget>[
        Row(
          spacing: TfSpace.s10,
          children: <Widget>[
            Expanded(
              child: Text(
                l.tab_sheetPreview,
                style: TfText.body(14, TfWeight.semibold).copyWith(color: TfColors.text),
              ),
            ),
            TfPrimaryButton(
              label: l.tab_sheetUseThis,
              onPressed: hasSong ? ref.read(songsterrStoreProvider.notifier).use : null,
            ),
            TfSecondaryButton(
              label: l.tab_sheetClose,
              height: TfSpace.s32,
              onPressed: widget.onClose,
            ),
          ],
        ),
        Expanded(
          // Borde de fondo y sin recorte: un borde en primer plano o un recorte sobre la vista nativa
          // (WKWebView) le quitan los clics en macOS. La vista queda inscrita dentro del borde.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TfRadius.control),
              border: Border.all(color: TfColors.fieldLine, width: TfStroke.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(TfStroke.hairline),
              child: TfWebView(controller: _web),
            ),
          ),
        ),
      ],
    );
  }
}
