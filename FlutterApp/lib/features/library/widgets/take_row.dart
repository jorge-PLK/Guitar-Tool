import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toneforge/contract/library_detail.dart';
import 'package:toneforge/features/library/dialogs/delete_take_dialog.dart';
import 'package:toneforge/features/library/library_format.dart';
import 'package:toneforge/features/library/library_metrics.dart';
import 'package:toneforge/features/library/project_detail_store.dart';
import 'package:toneforge/features/library/take_viewer_link.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_buttons.dart';

// PR:66 y PR:76: ancho de «Toma N» y alto de los botones, sin token en el kit.
const double _numberWidth = 64;
const double _buttonHeight = 32;

/// Estrella de cinco puntas rellena en `ok` (marcador de mejor toma).
class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.4;
      final p = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = TfColors.ok);
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}

/// Fila de una toma (PR:62-79).
class TakeRow extends ConsumerWidget {
  const TakeRow({super.key, required this.projectId, required this.part, required this.take});

  final String projectId;
  final PartInfo part;
  final TakeInfo take;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final label = l.library_takeLabel(take.number, part.name);
    final date = take.createdAtDate;
    TextStyle small({bool mono = false}) => TfText.body(TfSize.font12).copyWith(
      color: TfColors.muted,
      decoration: TextDecoration.none,
      fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
    );
    return Row(
      children: [
        SizedBox(
          width: _numberWidth,
          child: Text(
            l.library_takeNumber(take.number),
            style: TfText.body(TfSize.font13, TfWeight.semibold).copyWith(
              color: take.isBest ? TfColors.ok : TfColors.text2,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        if (take.isBest) ...[
          Semantics(
            label: l.library_takeBest,
            // La fuente no trae «★» (salía una barra): estrella dibujada.
            child: const CustomPaint(
              size: Size.square(LibraryMetrics.bestStarSize),
              painter: _StarPainter(),
            ),
          ),
          const SizedBox(width: TfSpace.s12),
        ],
        Expanded(
          child: Wrap(
            spacing: TfSpace.s12,
            runSpacing: TfSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (date != null) Text(formatShortDate(date, locale), style: small()),
              Text(
                take.duration == null ? l.library_takeNoDuration : formatClock(take.duration),
                style: small(mono: true),
              ),
              Text(take.hasVideo ? l.library_takeWithVideo : l.library_takeNoVideo, style: small()),
              if (take.punchCount > 0) Text(l.library_takePunches(take.punchCount), style: small()),
            ],
          ),
        ),
        const SizedBox(width: TfSpace.s12),
        TfSecondaryButton(
          label: l.library_takeView,
          height: _buttonHeight,
          icon: TfIcon.playFill,
          onPressed: take.audio == null || take.songStart == null
              ? null
              : () => openTakeViewer(context, projectId: projectId, takeId: take.id),
        ),
        const SizedBox(width: TfSpace.s12),
        TfSecondaryButton(
          label: l.library_takeDelete,
          height: _buttonHeight,
          onPressed: () async {
            final ok = await confirmDeleteTake(context, label: label);
            if (!ok) return;
            await ref.read(projectDetailStoreProvider(projectId).notifier).deleteTake(take.id);
          },
        ),
      ],
    );
  }
}
