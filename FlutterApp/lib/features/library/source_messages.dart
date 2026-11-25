import 'package:toneforge/features/library/link_import_store.dart';
import 'package:toneforge/l10n/app_localizations.dart';

/// Título y detalle de un error de fuente (`SourceError`, LinkImportSheet.swift:405-437).
/// El error del núcleo trae `code` y `message` (`«título\ndetalle»`): se traduce por `code`
/// y los datos dinámicos (versión, componente, código HTTP, últimas líneas) se leen del `message`.
({String title, String detail}) sourceErrorTexts(AppLocalizations l, LinkImportError error) {
  final msg = error.message;
  switch (error.code) {
    case 'offline':
      return (title: l.library_srcOfflineTitle, detail: l.library_srcOfflineDetail);
    case 'unsupported-link':
      return (title: l.library_srcUnsupportedTitle, detail: l.library_importSupported);
    case 'spotify-unreadable':
      return (title: l.library_srcSpotifyUnreadableTitle, detail: l.library_srcSpotifyUnreadableDetail);
    case 'age-restricted':
      return (title: l.library_srcAgeRestrictedTitle, detail: l.library_srcAgeRestrictedDetail);
    case 'region':
      return (title: l.library_srcRegionTitle, detail: l.library_srcRegionDetail);
    case 'private-video':
      return (title: l.library_srcPrivateTitle, detail: l.library_srcPrivateDetail);
    case 'removed':
      return (title: l.library_srcRemovedTitle, detail: l.library_srcRemovedDetail);
    case 'no-audio-format':
      return (title: l.library_srcNoAudioFormatTitle, detail: l.library_srcNoAudioFormatDetail);
    case 'extractor-broken':
      final version = RegExp(r'\(versi[oó]n ([^)]+)\)').firstMatch(msg)?.group(1);
      final lines = msg.split('\n');
      final detail = lines.skip(1).join('\n').trim();
      return (
        title: version == null
            ? l.library_srcExtractorBrokenTitle
            : l.library_srcExtractorBrokenTitleVersion(version),
        detail: detail.isEmpty ? l.library_srcExtractorBrokenDetail : detail,
      );
    case 'ffmpeg-failed':
      return (title: l.library_srcFfmpegFailedTitle, detail: _lastLines(msg));
    case 'helper-missing':
      final name = RegExp('«([^»]+)»').firstMatch(msg)?.group(1);
      return (
        title: l.library_srcHelperMissingTitle,
        detail: name == null ? msg : l.library_srcHelperMissingDetail(name),
      );
    case 'launch-failed':
      return (title: l.library_srcLaunchFailedTitle, detail: _lastLines(msg));
    case 'http-status':
      final code = int.tryParse(RegExp(r'\d+').firstMatch(msg)?.group(0) ?? '');
      return (
        title: l.library_srcHttpStatusTitle,
        detail: code == null ? msg : l.library_srcHttpStatusDetail(code),
      );
    case 'timed-out':
      return (title: l.library_srcTimedOutTitle, detail: l.library_srcTimedOutDetail);
    case 'cancelled':
      return (title: l.library_srcCancelledTitle, detail: '');
    case 'checksum-mismatch':
      return (title: l.library_srcChecksumTitle, detail: l.library_srcChecksumDetail);
    case 'update-failed':
      return (title: l.library_srcUpdateFailedTitle, detail: _lastLines(msg));
    case 'rate-limited':
      return (title: l.library_srcRateLimitedTitle, detail: l.library_srcRateLimitedDetail);
    case 'no-audio-produced':
      return (title: l.library_srcNoAudioProducedTitle, detail: l.library_srcNoAudioProducedDetail);
    default:
      return (title: l.library_importFailTitle, detail: msg);
  }
}

String _lastLines(String m) {
  final lines = m.trim().split('\n');
  return lines.sublist(lines.length > 4 ? lines.length - 4 : 0).join('\n');
}
