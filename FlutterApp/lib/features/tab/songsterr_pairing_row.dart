import 'package:flutter/widgets.dart';
import 'package:toneforge/contract/tab.dart';
import 'package:toneforge/l10n/app_localizations.dart';
import 'package:toneforge/theme/icons.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';

// TOKEN: umbrales orientativos de confianza 0,6 y 0,35 (TSS:323-330)
const double _okFrom = 0.6;
const double _accentFrom = 0.35;

/// Valor del desplegable para «sin pista» (transcripción automática / ninguna).
const int songsterrNoTrack = -1;

/// Color de la confianza: `ok` desde 0,6, `accent` desde 0,35, `danger` por debajo, `muted` si es nulo.
Color songsterrConfidenceColor(double? v) {
  if (v == null) return TfColors.muted;
  if (v >= _okFrom) return TfColors.ok;
  if (v >= _accentFrom) return TfColors.accent;
  return TfColors.danger;
}

const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

/// Fila de la tabla de emparejamiento: nombre, flecha, desplegable y confianza.
class SongsterrPairingRow extends StatelessWidget {
  const SongsterrPairingRow({
    super.key,
    this.name,
    this.nameStyle,
    required this.arrow,
    this.dropdown,
    this.plainText,
    this.soloLabel,
    this.confidence,
    this.confidenceText,
    this.showConfidence = false,
  });

  /// Nombre del slot; `null` deja el hueco (filas de solo posteriores a la primera).
  final String? name;
  final TextStyle? nameStyle;
  final TfIcon arrow;
  final Widget? dropdown;
  final String? plainText;

  /// «Solo k (m:ss)» entre el nombre y la flecha (filas de solo).
  final String? soloLabel;
  final double? confidence;
  final String? confidenceText;
  final bool showConfidence;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SizedBox(
      height: TfSize.songsterrPairingRowHeight,
      child: Row(
        spacing: TfSpace.s10,
        children: <Widget>[
          SizedBox(
            width: TfSize.tabNameWidth,
            child: name == null
                ? null
                : Text(name!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle ?? const TextStyle(color: TfColors.text)),
          ),
          if (soloLabel != null)
            SizedBox(
              width: TfSize.songsterrSoloLabelWidth,
              child: Text(soloLabel!,
                  maxLines: 1,
                  style: const TextStyle(color: TfColors.text2, fontFeatures: _tabular)),
            ),
          TfIconView(arrow, size: TfSize.font12, color: TfColors.muted),
          ?dropdown,
          if (plainText != null)
            Expanded(child: Text(plainText!, style: const TextStyle(color: TfColors.muted))),
          if (plainText == null) const Spacer(),
          if (showConfidence)
            Text(
              confidenceText ?? l.tab_sheetConfidenceUnmeasured,
              style: TextStyle(color: songsterrConfidenceColor(confidence), fontFeatures: _tabular),
            ),
        ],
      ),
    );
  }
}

List<TfDropdownItem<int>> _items(
    List<SongsterrChoiceInfo> choices, String none) {
  return <TfDropdownItem<int>>[
    TfDropdownItem<int>(value: songsterrNoTrack, label: none),
    for (final SongsterrChoiceInfo c in choices)
      TfDropdownItem<int>(value: c.track, label: c.label),
  ];
}

/// Filas de un slot: normal, solista sin secciones o una por solo.
List<Widget> songsterrSlotRows(
  AppLocalizations l,
  SongsterrSlotInfo slot,
  void Function(SongsterrAssignParams) assign,
) {
  if (slot.role == TabSongsterrRole.lead) {
    if (slot.solos.isEmpty) {
      return <Widget>[
        SongsterrPairingRow(
            name: slot.name, arrow: TfIcon.arrowRight, plainText: l.tab_sheetNoSolos),
      ];
    }
    return <Widget>[
      for (int i = 0; i < slot.solos.length; i++)
        SongsterrPairingRow(
          name: i == 0 ? slot.name : null,
          arrow: TfIcon.arrowLeft,
          soloLabel: l.tab_sheetSoloRow(slot.solos[i].index + 1, slot.solos[i].clock),
          dropdown: _soloDropdownFor(l, slot, slot.solos[i], assign),
          confidence: slot.solos[i].confidence,
          confidenceText: slot.solos[i].confidenceText,
          showConfidence: slot.solos[i].track != null,
        ),
    ];
  }
  return <Widget>[
    SongsterrPairingRow(
      name: slot.name,
      arrow: TfIcon.arrowRight,
      dropdown: TfDropdown<int>(
        width: TfSize.songsterrSlotDropdownWidth,
        items: _items(slot.choices, l.tab_sheetPickAutomatic),
        value: slot.track ?? songsterrNoTrack,
        onChanged: (int v) => assign(SongsterrAssignParams(
            stemId: slot.stemId, track: v == songsterrNoTrack ? null : v)),
      ),
      confidence: slot.confidence,
      confidenceText: slot.confidenceText,
      showConfidence: slot.track != null,
    ),
  ];
}

Widget _soloDropdownFor(
  AppLocalizations l,
  SongsterrSlotInfo slot,
  SongsterrSoloRowInfo solo,
  void Function(SongsterrAssignParams) assign,
) {
  return TfDropdown<int>(
    width: TfSize.songsterrSoloDropdownWidth,
    items: _items(solo.choices, l.tab_sheetSoloNone),
    value: solo.track ?? songsterrNoTrack,
    onChanged: (int v) => assign(SongsterrAssignParams(
        stemId: slot.stemId, solo: solo.index, track: v == songsterrNoTrack ? null : v)),
  );
}

