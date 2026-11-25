import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/study.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/fmt.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';

/// Píldora «Bucle: nombre|libre · m:ss–m:ss» con ✕ (BT:442-452).
class LoopPill extends StatelessWidget {
  const LoopPill({super.key, required this.loop, required this.onClear});

  final StudyLoop loop;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle style = TfText.body(TfSize.font13, TfWeight.semibold).copyWith(color: TfColors.accent);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TfColors.accentBg,
        borderRadius: BorderRadius.circular(TfRadius.field),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TfSpace.s10, vertical: TfSpace.s6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l.backing_loopLabel(
                loop.name ?? l.backing_loopFree,
                TfFmt.clock(loop.start),
                TfFmt.clock(loop.end),
              ),
              maxLines: 1,
              softWrap: false,
              style: style,
            ),
            const SizedBox(width: TfSpace.s6),
            Semantics(
              button: true,
              label: l.backing_loopClearA11y,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: const ValueKey<String>('loop_clear'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: const TfIconView(TfIcon.xmark, size: TfSize.font13, color: TfColors.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
