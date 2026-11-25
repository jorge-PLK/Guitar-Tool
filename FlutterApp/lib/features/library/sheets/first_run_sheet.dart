import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';
import 'package:toneforge/widgets/tf_sheet.dart';

import '../library_errors.dart';
import '../library_metrics.dart';
import '../library_store.dart';

/// Respaldo si el núcleo no manda `app.info.proposedProjectsFolder` (RootView.swift:130).
const String proposedProjectsFolder = '~/Music/ToneForge';

/// Hoja de primer arranque (FirstRunSheet, RV:122-137): sin botón de cerrar y sin Esc.
/// Se cierra sola cuando `needsFolder` pasa a false.
Future<void> showFirstRunSheet(BuildContext context) => showTfSheet<void>(
  context: context,
  onCancel: () {},
  builder: (BuildContext ctx) => const _FirstRunSheet(),
);

class _FirstRunSheet extends ConsumerWidget {
  const _FirstRunSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final proposed = ref.watch(libraryStoreProvider.select((s) => s.proposedFolder)) ?? proposedProjectsFolder;
    ref.listen(libraryStoreProvider.select((s) => s.needsFolder), (_, needs) {
      final route = ModalRoute.of(context);
      if (!needs && route != null) route.navigator?.removeRoute(route);
    });
    Future<void> choose() async {
      final err = await ref.read(libraryStoreProvider.notifier).chooseFirstRunFolder();
      if (err != null && context.mounted) await showCoreErrorAlert(context, err);
    }

    return TfSheetScaffold(
      width: LibraryMetrics.firstRunSheetWidth,
      padding: TfSpace.s28,
      titleSize: 24,
      title: l.library_firstRunTitle,
      body: Padding(
        padding: const EdgeInsets.only(top: TfSpace.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TfSpace.s16,
          children: <Widget>[
            Text(l.library_firstRunBody),
            Text(
              l.library_firstRunProposal(proposed),
              style: TfText.body(TfSize.font13).copyWith(color: TfColors.text2),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TfPrimaryButton(label: l.library_firstRunChoose, onPressed: choose),
            ),
          ],
        ),
      ),
    );
  }
}
