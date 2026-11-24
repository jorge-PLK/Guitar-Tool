import 'package:flutter/widgets.dart';
import 'package:toneforge/theme/tokens.dart';
import 'package:toneforge/theme/typography.dart';
import 'package:toneforge/widgets/tf_number_field.dart';
import 'package:toneforge/widgets/tf_stepper.dart';

/// Desfase en ms (VS:331-350): campo numérico entero de 70 a la derecha, «ms» muted y stepper de paso 1.
/// El rango sale de `choices.offsetRangeMs`. [onChanged] nulo lo deshabilita (cámara sin id, VS:348).
class OffsetField extends StatelessWidget {
  const OffsetField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ValueChanged<int>? cb = onChanged;
    void emit(double v) => cb?.call(v.round());
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: TfSpace.s8,
      children: <Widget>[
        TfNumberField(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          onChanged: cb == null ? null : emit,
        ),
        Text('ms', style: TfText.body().copyWith(color: TfColors.muted)),
        TfStepper(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          onChanged: cb == null ? null : emit,
        ),
      ],
    );
  }
}
