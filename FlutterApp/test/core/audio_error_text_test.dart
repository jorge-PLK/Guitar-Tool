import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/audio_error_text.dart';
import 'package:toneforge/l10n/app_localizations.dart';

void main() {
  test('audioErrorText traduce por código y cae al crudo', () async {
    final AppLocalizations l = await AppLocalizations.delegate.load(const Locale('es'));
    expect(audioErrorText(l, 'not-connected', 'x'), l.audioErrorNotConnected);
    expect(audioErrorText(l, 'sample-rate-mismatch', 'x'), l.audioErrorSampleRate);
    expect(audioErrorText(l, 'busy', 'x'), l.audioErrorBusy);
    expect(audioErrorText(l, 'unavailable', 'x'), l.audioErrorUnavailable);
    expect(audioErrorText(l, 'otro', 'crudo'), 'crudo');
    expect(audioErrorText(l, null, 'crudo'), 'crudo');
    expect(audioErrorText(l, null, null), isNull);
  });
}
