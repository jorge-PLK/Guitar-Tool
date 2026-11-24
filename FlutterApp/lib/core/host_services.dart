import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core_client.dart' show Json;

/// Error de un servicio de anfitrión: viaja como `{hostResponse:{id,error:{code,message}}}`.
class HostError implements Exception {
  const HostError(this.code, this.message);
  final String code;
  final String message;
  Json toJson() => {'code': code, 'message': message};
  @override
  String toString() => 'HostError($code: $message)';
}

/// Atiende un `hostRequest` (métodos y params en la cabecera de `HostBroker.swift`). Lanza [HostError] si falla.
abstract class HostServices {
  Future<Json> handle(String method, Json params);
}

/// Vista previa y carga oculta de Songsterr (`showPreview`, `hidePreview`, `load`).
/// OLA 2: aún no hay WebView; la implementación por defecto responde `unsupported`.
abstract class SongsterrHost {
  Future<Json> showPreview(Json params);
  Future<Json> hidePreview(Json params);
  Future<Json> load(Json params);
}

class UnsupportedSongsterrHost implements SongsterrHost {
  const UnsupportedSongsterrHost();
  static const _e = HostError('unsupported', 'Vista previa de Songsterr no disponible todavía.');
  @override
  Future<Json> showPreview(Json params) => Future.error(_e);
  @override
  Future<Json> hidePreview(Json params) => Future.error(_e);
  @override
  Future<Json> load(Json params) => Future.error(_e);
}

/// Diálogos con `file_selector` y abrir URL con `url_launcher`.
class PlatformHostServices implements HostServices {
  const PlatformHostServices({this.songsterr = const UnsupportedSongsterrHost()});
  final SongsterrHost songsterr;

  static List<XTypeGroup> _groups(Json p) {
    final t = p['types'];
    final ext = t is List ? [for (final e in t) '$e'] : const <String>[];
    return ext.isEmpty ? const [] : [XTypeGroup(extensions: ext)];
  }

  @override
  Future<Json> handle(String method, Json params) async {
    switch (method) {
      case 'pickFile':
        final f = await openFile(acceptedTypeGroups: _groups(params));
        return {'path': f?.path};
      case 'pickFiles':
        final fs = await openFiles(acceptedTypeGroups: _groups(params));
        return {'paths': [for (final f in fs) f.path]};
      case 'pickFolder':
        final initial = params['initial'];
        final d = await getDirectoryPath(
            initialDirectory: initial is String && initial.isNotEmpty ? initial : null);
        return {'path': d};
      case 'projectsFolderChanged':
        // Flutter abre los medios por ruta de fichero: no hay origen que volver a servir.
        return {'ok': true};
      case 'saveFile':
        final name = params['suggestedName'];
        final loc = await getSaveLocation(
            suggestedName: name is String ? name : null,
            acceptedTypeGroups: _groups(params));
        return {'path': loc?.path};
      case 'openURL':
        final url = params['url'];
        if (url is! String) throw const HostError('bad-params', 'Falta «url».');
        final uri = Uri.tryParse(url);
        if (uri == null) return {'opened': false};
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        return {'opened': ok};
      case 'showPreview':
        return songsterr.showPreview(params);
      case 'hidePreview':
        return songsterr.hidePreview(params);
      case 'load':
        return songsterr.load(params);
      default:
        throw HostError('unsupported', 'Servicio de anfitrión desconocido: $method.');
    }
  }
}
