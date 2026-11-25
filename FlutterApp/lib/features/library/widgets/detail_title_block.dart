import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/library_store.dart';
import 'package:toneforge/features/library/widgets/song_info_fields.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

// SongTitleBlock (LV:286-310): ancho máximo del modo edición, sin token en el kit.
const double _editMaxWidth = 480;
const double _titleSize = 32;

/// Título del tema con lápiz; el lápiz abre el modo edición local (`SongInfoFields` + Guardar/Cancelar).
class DetailTitleBlock extends ConsumerStatefulWidget {
  const DetailTitleBlock({super.key, required this.projectId, required this.title, this.artist});

  final String projectId;
  final String title;
  final String? artist;

  @override
  ConsumerState<DetailTitleBlock> createState() => _DetailTitleBlockState();
}

class _DetailTitleBlockState extends ConsumerState<DetailTitleBlock> {
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _titleFocus = FocusNode();
  bool _editing = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _start() {
    _title.text = widget.title;
    _artist.text = widget.artist ?? '';
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _titleFocus.requestFocus());
  }

  void _cancel() => setState(() => _editing = false);

  bool get _canSave => _title.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    final artist = _artist.text.trim();
    final error = await ref
        .read(libraryStoreProvider.notifier)
        .rename(widget.projectId, _title.text.trim(), artist.isEmpty ? null : artist);
    if (error == null && mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_editing) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _editMaxWidth),
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SongInfoFields(
                titleController: _title,
                artistController: _artist,
                titleFocus: _titleFocus,
                autofocusTitle: true,
                onSubmitted: _save,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: TfSpace.s8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TfPrimaryButton(label: l.library_save, onPressed: _canSave ? _save : null),
                  const SizedBox(width: TfSpace.s10),
                  TfSecondaryButton(label: l.library_cancel, height: TfSize.controlMd, onPressed: _cancel),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.title,
                style: TfText.display(_titleSize).copyWith(color: TfColors.text, decoration: TextDecoration.none),
              ),
            ),
            const SizedBox(width: TfSpace.s10),
            Semantics(
              button: true,
              label: l.library_editTooltip,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _start,
                  child: const TfIconView(TfIcon.pencil, size: TfSize.font14, color: TfColors.muted),
                ),
              ),
            ),
          ],
        ),
        if (widget.artist != null) ...[
          const SizedBox(height: TfSpace.s6),
          Text(
            widget.artist!,
            style: TfText.body().copyWith(color: TfColors.muted, decoration: TextDecoration.none),
          ),
        ],
      ],
    );
  }
}
