import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/theme/tokens.dart';

void main() {
  group('TfColors contra Theme.swift y tokens-componentes.md', () {
    // Tabla escrita a mano: [token Dart, hex esperado].
    final cases = <(String, Color, int)>[
      ('bg', TfColors.bg, 0x0F1113),
      ('sidebar', TfColors.sidebar, 0x15181B),
      ('card', TfColors.card, 0x171A1D),
      ('field', TfColors.field, 0x1C2024),
      ('line', TfColors.line, 0x252A2F),
      ('fieldLine', TfColors.fieldLine, 0x2A3036),
      ('text', TfColors.text, 0xE8EAED),
      ('text2', TfColors.text2, 0xC9CED4),
      ('muted', TfColors.muted, 0x9AA3AD),
      ('accent', TfColors.accent, 0xF2A33A),
      ('accentBg', TfColors.accentBg, 0x2A2116),
      ('accentInk', TfColors.accentInk, 0x1A1206),
      ('ok', TfColors.ok, 0x6FD99E),
      ('okBg', TfColors.okBg, 0x16301F),
      ('neutralBg', TfColors.neutralBg, 0x1F242A),
      ('danger', TfColors.danger, 0xF07178),
      ('dangerBg', TfColors.dangerBg, 0x331A1C),
      ('nativeControl', TfColors.nativeControl, 0x45474A),
      ('nativeSegmentBg', TfColors.nativeSegmentBg, 0x2D2E30),
      ('nativeSegmentText', TfColors.nativeSegmentText, 0xC5C5C5),
      ('nativeFieldBg', TfColors.nativeFieldBg, 0x171717),
      ('nativeFieldLine', TfColors.nativeFieldLine, 0x26282A),
      ('nativeStepperBg', TfColors.nativeStepperBg, 0x2D2E30),
      ('nativeStepperLine', TfColors.nativeStepperLine, 0x494A4C),
      ('sectionBlue', TfColors.sectionBlue, 0x6C9BD2),
      ('sectionGreen', TfColors.sectionGreen, 0x6FB58A),
      ('sectionViolet', TfColors.sectionViolet, 0x9C86C9),
      ('sectionRose', TfColors.sectionRose, 0xC97F9E),
      ('sectionTurquoise', TfColors.sectionTurquoise, 0x5DB5B5),
      ('sectionLime', TfColors.sectionLime, 0xA6B85C),
      ('sectionCoral', TfColors.sectionCoral, 0xC8706A),
      ('recordButton', TfColors.recordButton, 0xC8433A),
      ('recordLive', TfColors.recordLive, 0xE5534B),
      ('okBorder', TfColors.okBorder, 0x2F6B45),
      ('previewDeep', TfColors.previewDeep, 0x121417),
      ('videoBg', TfColors.videoBg, 0x0B0C0E),
      ('tileGrey', TfColors.tileGrey, 0x5A636C),
      ('timelineBlue', TfColors.timelineBlue, 0x5BC0EB),
      ('soloViolet', TfColors.soloViolet, 0xB79CFF),
      ('deviceOk', TfColors.deviceOk, 0x4CC38A),
      ('white', TfColors.white, 0xFFFFFF),
      ('black', TfColors.black, 0x000000),
    ];

    for (final (name, color, hex) in cases) {
      test('$name == #${hex.toRadixString(16).padLeft(6, '0')}', () {
        expect(color, Color(0xFF000000 | hex));
      });
    }

    test('sectionPalette tiene 7 colores en el orden de SectionEditor', () {
      expect(TfColors.sectionPalette, [
        const Color(0xFF6C9BD2),
        const Color(0xFF6FB58A),
        const Color(0xFF9C86C9),
        const Color(0xFFC97F9E),
        const Color(0xFF5DB5B5),
        const Color(0xFFA6B85C),
        const Color(0xFFC8706A),
      ]);
    });

    test('laneColors reusa timelineBlue, accent, ok, rosa y turquesa', () {
      expect(TfColors.laneColors, [
        TfColors.timelineBlue,
        TfColors.accent,
        TfColors.ok,
        TfColors.sectionRose,
        TfColors.sectionTurquoise,
      ]);
    });

    test('colorBars tiene 8 colores, blanco al inicio y negro al final', () {
      expect(TfColors.colorBars.length, 8);
      expect(TfColors.colorBars.first, TfColors.white);
      expect(TfColors.colorBars.last, TfColors.black);
    });
  });

  group('TfRadius, TfSize y TfShadow', () {
    test('control 44 y control 10', () {
      expect(TfSize.controlLg, 44);
      expect(TfRadius.control, 10);
    });

    test('card 14', () {
      expect(TfRadius.card, 14);
    });

    test('sidebar 240', () {
      expect(TfSize.sidebarWidth, 240);
    });

    test('pill es un radio grande', () {
      expect(TfRadius.pill, greaterThanOrEqualTo(100));
    });

    test('las 4 sombras son negras con su blur y offset', () {
      expect(TfShadow.countdown.blurRadius, 10);
      expect(TfShadow.countdown.offset, const Offset(0, 4));
      expect(TfShadow.playhead.blurRadius, 2);
      expect(TfShadow.playhead.offset, const Offset(0, 1));
      expect(TfShadow.knob.blurRadius, 3);
      expect(TfShadow.knob.offset, const Offset(0, 2));
      expect(TfShadow.sectionBox.blurRadius, 2);
      expect(TfShadow.sectionBox.offset, Offset.zero);
    });
  });
}
