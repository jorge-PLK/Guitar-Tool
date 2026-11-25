import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library_detail.dart';
import 'package:toneforge/features/library/project_detail_store.dart';
import 'package:toneforge/features/library/widgets/part_box.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_card.dart';

/// Tarjeta «Grabaciones» (ProjectRecordingsView PR:26-46): una caja por parte con tomas.
class RecordingsCard extends ConsumerWidget {
  const RecordingsCard({super.key, required this.projectId, required this.parts});

  final String projectId;
  final List<PartInfo> parts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final withTakes = [for (final p in parts) if (p.takes.isNotEmpty) p];
    final takeError = ref.watch(projectDetailStoreProvider(projectId).select((s) => s.takeError));
    return TfCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s20, vertical: TfSpace.s18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TfSpace.s12,
          children: [
            SizedBox(
              width: double.infinity,
              child: Text(
                l.library_recordingsTitle,
                style: TfText.display(18).copyWith(color: TfColors.text, decoration: TextDecoration.none),
              ),
            ),
            if (withTakes.isEmpty)
              Text(
                l.library_recordingsNone,
                style: TfText.body(TfSize.font13).copyWith(color: TfColors.muted, decoration: TextDecoration.none),
              )
            else
              for (final p in withTakes) PartBox(projectId: projectId, part: p),
            if (takeError != null)
              Text(
                l.library_takeDeleteError(takeError.message),
                style: TfText.body(TfSize.font12).copyWith(color: TfColors.danger, decoration: TextDecoration.none),
              ),
          ],
        ),
      ),
    );
  }
}
