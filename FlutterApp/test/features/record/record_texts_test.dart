import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/contract/core_message.dart';
import 'package:toneforge/features/record/record_texts.dart';
import 'package:toneforge/l10n/app_localizations.dart';

void main() {
  final AppLocalizations l = lookupAppLocalizations(const Locale('es'));
  CoreMessage m(String code, [Map<String, Object?> args = const {}]) =>
      CoreMessage(code: 'record-block-$code', message: 'MSG-$code', args: args);

  test('cada código conocido -> su clave ARB', () {
    final Map<String, String> expected = <String, String>{
      'busy': l.record_block_busy,
      'invalid-channels': l.record_block_invalidChannels,
      'input-disconnected': l.record_block_inputDisconnected,
      'loop': l.record_block_loop,
      'no-guitar-input': l.record_block_noGuitarInput,
      'no-input-device': l.record_block_noInputDevice,
      'no-part': l.record_block_noPart,
      'output-disconnected': l.record_block_outputDisconnected,
      'punch-no-marks': l.record_block_punchNoMarks,
      'punch-no-take': l.record_block_punchNoTake,
      'speed': l.record_block_speed(0.5),
    };
    expected.forEach((String code, String text) {
      expect(recordBlockText(l, m(code, <String, Object?>{'rate': 0.5})), text, reason: code);
      expect(text, isNot('MSG-$code'));
    });
  });

  test('rate-mismatch compone Hz en kHz; session-unavailable usa detail', () {
    expect(
      recordBlockText(l, m('rate-mismatch', <String, Object?>{'deviceHz': 44100, 'workingHz': 48000})),
      l.record_block_rateMismatch(44.1, 48),
    );
    expect(recordBlockText(l, m('session-unavailable', <String, Object?>{'detail': 'boom'})), 'boom');
    expect(recordBlockText(l, m('session-unavailable')), 'MSG-session-unavailable');
  });

  test('código desconocido -> message', () {
    expect(recordBlockText(l, const CoreMessage(code: 'record-block-nuevo', message: 'Texto del núcleo')), 'Texto del núcleo');
  });

  test('desfase: 0 sin ajustar, signo + y menos tipográfico', () {
    expect(recordOffsetText(l, 0), l.record_offsetUnset);
    expect(recordOffsetText(l, 65), l.record_offsetValue('+65'));
    expect(recordOffsetText(l, -12), l.record_offsetValue('−12'));
  });
}
