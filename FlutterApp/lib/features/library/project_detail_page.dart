import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/features/library/project_detail_store.dart';
import 'package:toneforge/features/library/widgets/detail_actions.dart';
import 'package:toneforge/features/library/widgets/detail_info_card.dart';
import 'package:toneforge/features/library/widgets/detail_title_block.dart';
import 'package:toneforge/features/library/widgets/recordings_card.dart';
import 'package:toneforge/features/library/widgets/stems_card.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/shell/library_detail.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';

/// Página de detalle de un tema (ProjectDetailView, LV:267-386).
class ProjectDetailPage extends ConsumerWidget {
  const ProjectDetailPage({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final detail = ref.watch(projectDetailStoreProvider(projectId).select((s) => s.detail));
    final summary = detail?.summary;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: TfSpace.s40, vertical: TfSpace.s32),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TfSpace.s24,
          children: [
            DetailTextButton(
              label: l.library_detailBack,
              color: TfColors.accent,
              leading: const TfIconView(TfIcon.chevronLeft, size: TfSize.font14, color: TfColors.accent),
              onTap: () => ref.read(libraryDetailProvider.notifier).close(),
            ),
            if (detail != null && summary != null) ...[
              DetailTitleBlock(projectId: projectId, title: summary.title, artist: summary.artist),
              DetailInfoCard(summary: summary),
              StemsCard(stems: detail.stems),
              RecordingsCard(projectId: projectId, parts: detail.parts),
              DetailActions(projectId: projectId, title: summary.title, separation: summary.separationState),
            ],
          ],
        ),
      ),
    );
  }
}
