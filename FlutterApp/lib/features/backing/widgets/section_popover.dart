import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/section_popover_rows.dart';
import 'package:toneforge/features/backing/widgets/section_popover_state.dart';
import 'package:toneforge/features/backing/widgets/section_selection.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_divider.dart';
import 'package:toneforge/widgets/tf_switch.dart';
import 'package:toneforge/widgets/tf_text_field.dart';

/// Contenido de la hoja «Sección / Solo» (`SectionPopover`, SectionBoxes.swift:283-415; ficha §7.1).
///
/// No se ancla aquí: quien la monte la pone dentro de un popover y la abre con
/// [SectionPopoverNotifier.open]. Cerrarla de cualquier forma que no sea Esc en el campo ni «Eliminar»
/// renombra la sección con el borrador (`onDisappear`, :341), también si se desmonta desde fuera.
class SectionPopover extends ConsumerStatefulWidget {
  const SectionPopover({required this.sectionId, super.key});

  final String sectionId;

  @override
  ConsumerState<SectionPopover> createState() => _SectionPopoverState();
}

class _SectionPopoverState extends ConsumerState<SectionPopover> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'SectionPopoverName');

  // Capturados al montar: `dispose` no puede usar `ref`.
  late final StudyStore _store;
  late final SectionPopoverNotifier _popover;
  late final SectionSelectionNotifier _selection;

  /// Ya no hay que renombrar al desmontar (Hecho, Esc, Eliminar) o la sección ya no existe.
  bool _settled = false;

  StudySectionInfo? get _section {
    final List<StudySectionInfo>? all = ref.read(studyStoreProvider).study?.sections;
    if (all == null) return null;
    for (final StudySectionInfo s in all) {
      if (s.id == widget.sectionId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _store = ref.read(studyStoreProvider.notifier);
    _popover = ref.read(sectionPopoverProvider.notifier);
    _selection = ref.read(sectionSelectionProvider.notifier);
    _text.text = _section?.name ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    if (!_settled) _rename();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Nombre vacío: el núcleo pone el por defecto (`SectionEditor.rename`).
  void _rename() {
    _settled = true;
    unawaited(_store.updateSection(StudyUpdateSectionParams(id: widget.sectionId, name: _text.text)));
  }

  void _done() {
    if (_settled) return;
    _rename();
    _popover.close();
  }

  void _cancel() {
    _settled = true;
    _popover.close();
  }

  void _delete() {
    _settled = true;
    _selection.clear();
    unawaited(_store.deleteSection(widget.sectionId));
    _popover.close();
  }

  Future<void> _toggleSolo(bool on) async {
    final bool untouched = _text.text == _section?.name;
    await _store.updateSection(StudyUpdateSectionParams(id: widget.sectionId, solo: on));
    if (!mounted || !untouched) return;
    final String? name = _section?.name;
    if (name != null) _text.text = name;
  }

  void _pickColor(int i, StudySectionInfo s) {
    final StudyColorChange color = s.color == i ? const StudyColorAuto() : StudyColorPalette(i);
    unawaited(_store.updateSection(StudyUpdateSectionParams(id: widget.sectionId, color: color)));
  }

  void _nudge(bool start, bool forward) => unawaited(_store.nudgeSectionEdge(widget.sectionId,
      start: start, forward: forward, bar: HardwareKeyboard.instance.isAltPressed));

  Future<void> _listen(StudySectionInfo s) async {
    final bool wasPlaying = ref.read(studyStoreProvider).transport?.playing ?? false;
    await _store.setLoop(s.start, s.end, name: s.name);
    await _store.seek(s.start);
    if (!wasPlaying) await _store.play();
  }

  KeyEventResult _onNameKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudySectionInfo? s = ref.watch(
      studyStoreProvider.select((st) => st.study?.sections.where((x) => x.id == widget.sectionId).firstOrNull),
    );
    if (s == null) {
      _settled = true;
      return const SizedBox.shrink();
    }
    final bool mac = defaultTargetPlatform == TargetPlatform.macOS;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _done,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _done,
      },
      child: SizedBox(
        width: sectionPopoverWidth,
        child: Padding(
          padding: const EdgeInsets.all(TfSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: TfSpace.s12,
            children: <Widget>[
              Text(
                s.solo ? l.backing_sectionSheetSolo : l.backing_sectionSheetSection,
                style: TfText.display(16).copyWith(color: TfColors.text),
              ),
              Focus(
                onKeyEvent: _onNameKey,
                child: TfTextField(
                  key: const ValueKey<String>('section-name'),
                  controller: _text,
                  focusNode: _focus,
                  hint: l.backing_sectionName,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _done(),
                ),
              ),
              SectionSuggestions(draft: _text.text, onPick: (String n) => setState(() => _text.text = n)),
              SectionSwatches(solo: s.solo, current: s.paletteIndex, onPick: (int i) => _pickColor(i, s)),
              Row(children: <Widget>[
                Expanded(
                  child: Text(l.backing_sectionSolo, style: TfText.body(TfSize.font13).copyWith(color: TfColors.text)),
                ),
                TfSwitch(
                  key: const ValueKey<String>('section-solo'),
                  small: true,
                  value: s.solo,
                  semanticLabel: l.backing_sectionSolo,
                  onChanged: (bool on) => unawaited(_toggleSolo(on)),
                ),
              ]),
              const TfDivider(),
              SectionEdgeRow(
                title: l.backing_sectionStart,
                isStart: true,
                time: s.start,
                onNudge: (bool fwd) => _nudge(true, fwd),
              ),
              SectionEdgeRow(
                title: l.backing_sectionEnd,
                isStart: false,
                time: s.end,
                onNudge: (bool fwd) => _nudge(false, fwd),
              ),
              Text(
                mac ? l.backing_sectionNudgeHintMac : l.backing_sectionNudgeHintWin,
                style: TfText.body(TfSize.font11).copyWith(color: TfColors.muted),
              ),
              Row(children: <Widget>[
                TfSecondaryButton(
                  key: const ValueKey<String>('section-listen'),
                  label: l.backing_sectionListen,
                  icon: TfIcon.repeat,
                  iconSize: TfSize.font13,
                  hPadding: TfSpace.s12,
                  onPressed: () => unawaited(_listen(s)),
                ),
                const Spacer(),
                TfDangerButton(label: l.backing_sectionDelete, onPressed: _delete),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TfPrimaryButton(label: l.backing_sectionDone, onPressed: _done),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
