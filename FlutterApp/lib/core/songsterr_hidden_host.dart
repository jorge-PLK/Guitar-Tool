import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webview_all/webview_all.dart' as wv;

import 'core_client.dart' show Json;
import 'host_services.dart';

/// Página oculta que usa [HiddenSongsterrHost]: un WebView sin ventana. Se sustituye por un falso en tests.
abstract class HiddenWebPage {
  /// Navega a [url] y termina al acabar la carga principal. Devuelve el estado HTTP si se conoce (si no, `null`).
  /// Lanza `HostError('httpStatus', status:)` si el documento principal responde >= 400 y `HostError('offline')`
  /// si la navegación falla.
  Future<int?> navigate(Uri url, {String? userAgent});

  /// Evalúa una expresión JS que da booleano; un error cuenta como `false`.
  Future<bool> evaluateBool(String js);

  /// `document.documentElement.outerHTML`.
  Future<String> outerHtml();

  /// Libera el WebView (idempotente).
  Future<void> close();
}

typedef HiddenWebPageFactory = Future<HiddenWebPage> Function();

/// `SongsterrHost.load`: carga oculta de una página de Songsterr (contrato en `Temp/win/step8-contract.md`).
///
/// Modo elegido: `OffscreenWebViewSession` de `webview_all` (solo macOS). No necesita widget en el árbol (ni
/// `Overlay` ni host a nivel de app, así que no toca el layout), se cierra de forma determinista y usa un
/// almacén privado aislado. Los modos `offstage` y `zero` de P9 también valen, pero exigen montar un widget.
/// Windows (WebView2): sin sesión offscreen en el plugin; responde `unsupported` hasta medir un host montado.
/// `showPreview` y `hidePreview` siguen sin soporte. `cancelled` no se emite: el puente no trae cancelación.
class HiddenSongsterrHost implements SongsterrHost {
  HiddenSongsterrHost({
    HiddenWebPageFactory? pageFactory,
    this.pollInterval = const Duration(milliseconds: 250),
  }) : _factory = pageFactory ?? OffscreenWebPage.create;

  final HiddenWebPageFactory _factory;
  final Duration pollInterval;
  Future<void> _tail = Future<void>.value();

  static const _unsupported = HostError('unsupported', 'Vista previa de Songsterr no disponible todavía.');

  @override
  Future<Json> showPreview(Json params) => Future.error(_unsupported);
  @override
  Future<Json> hidePreview(Json params) => Future.error(_unsupported);

  /// Una carga a la vez: cada llamada espera a que acabe la anterior.
  @override
  Future<Json> load(Json params) {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      try {
        await prev;
        return await _run(params);
      } finally {
        done.complete();
      }
    }();
  }

  Future<Json> _run(Json params) async {
    final url = params['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null || !uri.hasScheme) throw const HostError('bad-params', 'Falta «url».');
    final ua = params['userAgent'];
    final script = params['readyScript'];
    final t = params['timeout'];
    final timeout = Duration(milliseconds: ((t is num ? t.toDouble() : 30.0) * 1000).round());
    final stopwatch = Stopwatch()..start();

    final HiddenWebPage page;
    try {
      page = await _factory();
    } on HostError {
      rethrow;
    } catch (_) {
      throw _unsupported;
    }
    try {
      int? status;
      try {
        status = await page.navigate(uri, userAgent: ua is String ? ua : null).timeout(timeout);
      } on TimeoutException {
        throw const HostError('offline', 'La navegación no terminó a tiempo.');
      }
      if (script is String && script.isNotEmpty) {
        while (!await page.evaluateBool(script)) {
          if (stopwatch.elapsed + pollInterval > timeout) {
            throw const HostError('readyTimeout', 'La página no llegó a estar lista.');
          }
          await Future<void>.delayed(pollInterval);
        }
      }
      return {'status': status ?? 200, 'html': await page.outerHtml()};
    } finally {
      try {
        await page.close();
      } catch (_) {
        // liberar es best-effort: el resultado o el error ya están decididos
      }
    }
  }
}

/// Adaptador real sobre `OffscreenWebViewSession` (solo macOS).
class OffscreenWebPage implements HiddenWebPage {
  OffscreenWebPage._(this._session);
  final wv.OffscreenWebViewSession _session;
  bool _closed = false;

  static Future<HiddenWebPage> create() async {
    if (!Platform.isMacOS) throw const HostError('unsupported', 'Carga oculta no disponible en esta plataforma.');
    final s = await wv.OffscreenWebViewSession.fromPlatformCreationParams(
      const wv.PlatformWebViewControllerCreationParams(sessionMode: wv.WebViewSessionMode.isolatedIncognito),
    );
    return OffscreenWebPage._(s);
  }

  wv.WebViewController get _c => _session.controller;

  @override
  Future<int?> navigate(Uri url, {String? userAgent}) async {
    final c = _c;
    final done = Completer<int?>();
    void fail(HostError e) {
      if (!done.isCompleted) done.completeError(e);
    }

    await c.setJavaScriptMode(wv.JavaScriptMode.unrestricted);
    if (userAgent != null) await c.setUserAgent(userAgent);
    await c.setNavigationDelegate(wv.NavigationDelegate(
      onHttpError: (e) {
        final code = e.response?.statusCode ?? 0;
        fail(HostError('httpStatus', 'Songsterr respondió con el error $code.', status: code));
        unawaited(c.loadRequest(Uri.parse('about:blank')).catchError((_) {}));
      },
      onWebResourceError: (e) {
        if (e.isForMainFrame ?? true) fail(HostError('offline', '${e.errorCode} ${e.description}'));
      },
      onPageFinished: (_) {
        if (!done.isCompleted) done.complete(null);
      },
    ));
    await c.loadRequest(url);
    return done.future;
  }

  @override
  Future<bool> evaluateBool(String js) async {
    try {
      return _asBool(await _c.runJavaScriptReturningResult(js));
    } catch (_) {
      return false;
    }
  }

  static bool _asBool(Object? v) {
    if (v is bool) return v;
    final s = '$v'.trim().toLowerCase();
    return s == 'true' || s == '1';
  }

  @override
  Future<String> outerHtml() async {
    final raw = await _c.runJavaScriptReturningResult('document.documentElement.outerHTML');
    return decodeHtmlResult(raw.toString());
  }

  /// Mac devuelve el texto como JSON (con comillas); Windows ya decodificado. Se decodifica solo si va entre comillas.
  static String decodeHtmlResult(String raw) {
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        final v = jsonDecode(raw);
        if (v is String) return v;
      } catch (_) {}
    }
    return raw;
  }

  @override
  Future<void> close() {
    if (_closed) return Future<void>.value();
    _closed = true;
    return _session.close();
  }
}
