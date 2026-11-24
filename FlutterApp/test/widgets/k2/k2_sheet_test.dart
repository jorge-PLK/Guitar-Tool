import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/widgets/tf_checkbox.dart';
import 'package:toneforge/widgets/tf_dropdown.dart';
import 'package:toneforge/widgets/tf_number_field.dart';
import 'package:toneforge/widgets/tf_segmented.dart';
import 'package:toneforge/widgets/tf_slider.dart';
import 'package:toneforge/widgets/tf_stepper.dart';
import 'package:toneforge/widgets/tf_switch.dart';
import 'package:toneforge/widgets/tf_text_field.dart';

import '../../support/harness.dart';

void main() {
  setUpAll(loadTfFonts);

  group('k2 lámina', () {
    testWidgets('k2 lámina de controles (golden)', (tester) async {
      const List<TfSegment<int>> segs = <TfSegment<int>>[
        TfSegment<int>(value: 1, label: 'Uno'),
        TfSegment<int>(value: 2, label: 'Dos'),
      ];
      const List<TfDropdownItem<int>> items = <TfDropdownItem<int>>[
        TfDropdownItem<int>(value: 1, label: 'Entrada 1'),
        TfDropdownItem<int>(value: 2, label: 'Entrada 2'),
      ];
      void noop(Object? _) {}
      await pumpK2(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            k2Row('switch off/on', Row(children: <Widget>[
              TfSwitch(value: false, onChanged: noop),
              const SizedBox(width: 12),
              TfSwitch(value: true, onChanged: noop),
              const SizedBox(width: 12),
              TfSwitch(value: true, onChanged: noop, small: true),
              const SizedBox(width: 12),
              const TfSwitch(value: true, onChanged: null),
            ])),
            k2Row('checkbox', Row(children: <Widget>[
              TfCheckbox(value: false, onChanged: noop, label: 'Apagada'),
              const SizedBox(width: 16),
              TfCheckbox(value: true, onChanged: noop, label: 'Marcada'),
              const SizedBox(width: 16),
              const TfCheckbox(value: true, onChanged: null, label: 'Off'),
            ])),
            k2Row('segmented', Row(children: <Widget>[
              TfSegmented<int>(segments: segs, value: 1, onChanged: noop),
              const SizedBox(width: 16),
              const TfSegmented<int>(segments: segs, value: 2, onChanged: null),
            ])),
            k2Row('slider', Row(children: <Widget>[
              TfSlider(value: 0.4, width: 120, onChanged: noop),
              const SizedBox(width: 16),
              const TfSlider(value: 0.4, width: 120, onChanged: null),
            ])),
            k2Row('stepper + num', Row(children: <Widget>[
              TfNumberField(value: 120, onChanged: noop),
              const SizedBox(width: 6),
              TfStepper(value: 1, onChanged: noop),
              const SizedBox(width: 16),
              TfNumberField(value: 120, onChanged: noop),
              const SizedBox(width: 16),
              const TfNumberField(value: 120, onChanged: null),
            ])),
            k2Row('dropdown', Row(children: <Widget>[
              TfDropdown<int>(items: items, value: 1, onChanged: noop),
              const SizedBox(width: 16),
              const TfDropdown<int>(items: items, value: 2, onChanged: null),
            ])),
            k2Row('text field', const Row(children: <Widget>[
              TfTextField(search: true, width: 190, hint: 'Buscar tema'),
              SizedBox(width: 16),
              TfTextField(width: 190, hint: 'Enlace'),
            ])),
          ],
        ),
        size: const Size(640, 360),
      );
      await tester.tap(find.byType(TfNumberField).at(1));
      await tester.pump();
      await expectLater(k2Screen(), matchesGoldenFile('goldens/k2_sheet.png'));
    });
  });
}
