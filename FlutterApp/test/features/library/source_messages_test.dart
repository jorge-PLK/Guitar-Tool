import 'package:flutter_test/flutter_test.dart';
import 'package:toneforge/core/core_client.dart';
import 'package:toneforge/features/library/link_import_logic.dart';
import 'package:toneforge/features/library/source_messages.dart';
import 'package:toneforge/l10n/app_localizations_en.dart';
import 'package:toneforge/l10n/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();
  final en = AppLocalizationsEn();

  group('source_messages con args', () {
    test('fromCore copia args', () {
      final e = LinkImportError.fromCore(const CoreError('http-status', 'x', {'status': 503}));
      expect(e.args['status'], 503);
    });

    test('args mandan sobre el message', () {
      const e = LinkImportError(
        code: 'http-status',
        message: 'Respuesta inesperada\nEl servidor respondió con el código 404.',
        args: {'status': 503},
      );
      expect(sourceErrorTexts(es, e).detail, es.library_srcHttpStatusDetail(503));
      const v = LinkImportError(code: 'extractor-broken', message: 'a (versión 1)\nd', args: {'version': '2025.1'});
      expect(sourceErrorTexts(es, v).title, es.library_srcExtractorBrokenTitleVersion('2025.1'));
      const h = LinkImportError(code: 'helper-missing', message: 'm «otro»', args: {'name': 'ffmpeg'});
      expect(sourceErrorTexts(es, h).detail, es.library_srcHelperMissingDetail('ffmpeg'));
    });

    test('sin args cae al regex del message', () {
      const e = LinkImportError(code: 'http-status', message: 'Respuesta\nCódigo 404.');
      expect(sourceErrorTexts(es, e).detail, es.library_srcHttpStatusDetail(404));
    });
  });

  group('errores de Spotify', () {
    const cases = {
      'spotify-missing-credentials': 'Búsqueda en Spotify no disponible: falta la clave (.env)',
      'spotify-rejected': 'Spotify ha rechazado la clave',
      'spotify-offline': 'Sin conexión con Spotify',
      'spotify-bad-response': 'Spotify ha devuelto una respuesta inesperada',
    };
    for (final MapEntry(key: code, value: text) in cases.entries) {
      test(code, () {
        final e = LinkImportError(code: code, message: text);
        expect(sourceErrorTexts(es, e).title, text);
        expect(sourceErrorTexts(en, e).title, isNot(text));
        expect(sourceErrorTexts(en, e).title, contains('Spotify'));
      });
    }

    test('spotify-rate-limited por args, por message y sin dato', () {
      const a = LinkImportError(code: 'spotify-rate-limited', message: 'Spotify pide esperar 9 s', args: {'retryAfter': 30});
      expect(sourceErrorTexts(es, a).title, 'Spotify pide esperar 30 s');
      expect(sourceErrorTexts(en, a).title, 'Spotify asks to wait 30 s');
      const m = LinkImportError(code: 'spotify-rate-limited', message: 'Spotify pide esperar 9 s');
      expect(sourceErrorTexts(es, m).title, 'Spotify pide esperar 9 s');
      const n = LinkImportError(code: 'spotify-rate-limited', message: 'Spotify');
      expect(sourceErrorTexts(es, n).title, 'Spotify');
    });
  });
}
