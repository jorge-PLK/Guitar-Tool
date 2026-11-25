import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/library.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Selector de tema de Grabar sin proyecto elegido (RecordView.swift:26-45): solo temas con separación `done`.
class RecordTopicChooser extends StatelessWidget {
  const RecordTopicChooser({super.key, required this.topics, required this.onPick});

  final List<ProjectSummary> topics;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<ProjectSummary> ready = <ProjectSummary>[
      for (final ProjectSummary p in topics)
        if (p.separationState == SeparationState.done) p,
    ];
    final TextStyle muted = TfText.body().copyWith(color: TfColors.muted);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s40, vertical: TfSpace.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.record_title, style: TfText.display(TfSize.font30).copyWith(color: TfColors.text)),
          const SizedBox(height: TfSpace.s16),
          if (ready.isEmpty)
            Text(l.record_chooserEmpty, style: muted)
          else ...<Widget>[
            Text(l.record_chooserPick, style: muted),
            for (final ProjectSummary p in ready) ...<Widget>[
              const SizedBox(height: TfSpace.s16),
              _TopicRow(title: p.title, onTap: () => onPick(p.id)),
            ],
          ],
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: TfSpace.s12, vertical: TfSpace.s10),
            decoration: BoxDecoration(color: TfColors.field, borderRadius: BorderRadius.circular(TfRadius.control)),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TfText.body().copyWith(color: TfColors.text))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
