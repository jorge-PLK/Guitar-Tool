import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/features/backing/study_store.dart';
import 'package:toneforge/features/backing/widgets/mixer_levels.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_fader.dart';
import 'package:toneforge/widgets/tf_level_bar.dart';
import 'package:toneforge/widgets/tf_menu.dart';
import 'package:toneforge/widgets/tf_mixer_channel.dart';
import 'package:toneforge/widgets/tf_text_field.dart';
import 'package:toneforge/widgets/tf_toggle_button.dart';

const List<StudyStemKind> _order = <StudyStemKind>[
  StudyStemKind.vocals,
  StudyStemKind.drums,
  StudyStemKind.bass,
  StudyStemKind.guitar,
  StudyStemKind.piano,
  StudyStemKind.other,
];

/// Canales visibles en orden Voz, Batería, Bajo, Guitarra, Piano, Resto (BackingMixer.swift:22-24).
/// Se omiten los de stems vacíos; con guitarras separadas hay un canal por pista (en el orden del núcleo).
List<StudyChannel> orderedMixerChannels(StudyOpenResult study) {
  final Set<StudyStemKind> empty = <StudyStemKind>{for (final StudyEmptyStem e in study.emptyStems) e.kind};
  final List<StudyChannel> out = <StudyChannel>[];
  for (final StudyStemKind kind in _order) {
    for (final StudyChannel c in study.transport.channels) {
      if (c.kind != kind) continue;
      if (c.guitarRole == null && empty.contains(kind)) continue;
      out.add(c);
    }
  }
  return out;
}

/// Silenciado o solo ajeno: canal atenuado y nivel 0.
bool isMixerChannelDim(StudyChannel c, bool anySolo) => c.muted || (anySolo && !c.solo);

String mixerChannelTitle(AppLocalizations l, StudyChannel c) {
  if (c.guitarRole != null) return c.name;
  return switch (c.kind) {
    StudyStemKind.vocals => l.backing_stemVocals,
    StudyStemKind.drums => l.backing_stemDrums,
    StudyStemKind.bass => l.backing_stemBass,
    StudyStemKind.guitar => l.backing_stemGuitar,
    StudyStemKind.piano => l.backing_stemPiano,
    _ => l.backing_stemOther,
  };
}

String mixerDbText(BuildContext context, double v) => TfFmt.db(v, Localizations.localeOf(context).toString());

/// Botones M y S de un canal (`MixerToggle`).
class MixerMuteSolo extends ConsumerWidget {
  const MixerMuteSolo({super.key, required this.channel, required this.title});

  final StudyChannel channel;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final StudyStore store = ref.read(studyStoreProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TfSpace.s6,
      children: <Widget>[
        TfToggleButton(
          text: l.backing_muteLetter,
          on: channel.muted,
          semanticLabel: channel.muted ? l.backing_unmuteA11y(title) : l.backing_muteA11y(title),
          onPressed: () => store.setMix(channel.id, mute: !channel.muted),
        ),
        TfToggleButton(
          text: l.backing_soloLetter,
          on: channel.solo,
          semanticLabel: l.backing_soloA11y(title),
          onPressed: () => store.setMix(channel.id, solo: !channel.solo),
        ),
      ],
    );
  }
}

/// Canal de un stem o de una pista de guitarra (BackingMixer.swift:143-190).
class MixerChannel extends ConsumerWidget {
  const MixerChannel({super.key, required this.channel, required this.anySolo, required this.height});

  final StudyChannel channel;
  final bool anySolo;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String title = mixerChannelTitle(l, channel);
    final bool dim = isMixerChannelDim(channel, anySolo);
    final TextStyle value = TfText.body(TfSize.font12).copyWith(color: TfColors.text2);
    return TfMixerChannel(
      height: height,
      dimmed: dim,
      title: channel.guitarRole == null
          ? _titleText(title)
          : _RenamableTitle(channel: channel, title: title),
      faderBuilder: (double fh) => TfFader(
        dB: channel.gainDB,
        height: fh,
        semanticLabel: l.backing_faderA11y,
        semanticValue: (double v) => mixerDbText(context, v),
        onChanged: (double v) => ref.read(studyStoreProvider.notifier).setMix(channel.id, gainDB: v),
      ),
      levelBuilder: (double fh) => _Level(id: channel.id, height: fh, dim: dim),
      value: Text(channel.muted ? l.backing_muted : mixerDbText(context, channel.gainDB), style: value),
      toggles: MixerMuteSolo(channel: channel, title: title),
    );
  }
}

Widget _titleText(String t) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s4),
      child: Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TfText.body(TfSize.font12, TfWeight.semibold).copyWith(color: TfColors.text),
      ),
    );

class _Level extends ConsumerWidget {
  const _Level({required this.id, required this.height, required this.dim});

  final String id;
  final double height;
  final bool dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double? rms = ref.watch(mixerLevelsProvider.select((m) => m[id]?.rmsDB));
    return TfLevelBar(rmsDb: rms, height: height, dim: dim);
  }
}

/// Título de una pista de guitarra: doble clic o menú contextual lo pasan a edición (BackingMixer.swift:190-214).
class _RenamableTitle extends ConsumerStatefulWidget {
  const _RenamableTitle({required this.channel, required this.title});

  final StudyChannel channel;
  final String title;

  @override
  ConsumerState<_RenamableTitle> createState() => _RenamableTitleState();
}

class _RenamableTitleState extends ConsumerState<_RenamableTitle> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _text.text = widget.title;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    final String name = _text.text.trim();
    setState(() => _editing = false);
    final StudyGuitarRole? role = widget.channel.guitarRole;
    if (role != null && name.isNotEmpty && name != widget.title) {
      ref.read(studyStoreProvider.notifier).renameGuitar(role, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (_editing) {
      return Focus(
        onKeyEvent: (FocusNode _, KeyEvent e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            setState(() => _editing = false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TfTextField(
          controller: _text,
          focusNode: _focus,
          hint: l.backing_channelNameField,
          width: TfSize.mixerChannelWidth - TfSpace.s12,
          onSubmitted: (_) => _commit(),
        ),
      );
    }
    return TfMenu(
      entries: <TfMenuEntry>[TfMenuItem(label: l.backing_channelRenameMenu, onSelected: _start)],
      builder: (BuildContext context, VoidCallback toggle) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _start,
        onSecondaryTap: toggle,
        child: _titleText(widget.title),
      ),
    );
  }
}
