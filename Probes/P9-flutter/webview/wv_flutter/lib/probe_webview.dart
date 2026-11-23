// P9.4: unica capa que conoce el paquete WebView. El resto de lib/ es identico en wv_all y wv_flutter.
// macOS: webview_flutter. Windows: webview_flutter_windows no registra plataforma de webview_flutter;
// se usa su API directa (WebviewController + Webview, fork de webview_windows).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as win;

class ProbeWebView {
  ProbeWebView({
    required this.onMessage,
    required this.onConsole,
    required this.onPageFinished,
    required this.onError,
  });

  static const candidate = 'wv_flutter';
  static const channelName = 'tf';

  final void Function(String raw) onMessage;
  final void Function(String level, String message) onConsole;
  final void Function(String url) onPageFinished;
  final void Function(String description) onError;

  /// Lo fija main.dart con --user-data-dir antes de init(). Solo se aplica en Windows.
  static String? requestedUserDataDir;
  static bool userDataDirApplied = false;
  static String? userDataDirError;
  static bool _envTried = false; // initializeEnvironment vale una sola vez, antes del primer controlador

  late final WebViewController _c;
  win.WebviewController? _w;
  bool _mapped = false;
  String _lastUrl = '';
  String serving = '';
  bool uaApplied = false;

  Future<void> init({String? userAgent}) async {
    if (Platform.isWindows) return _initWin(userAgent);
    _c = WebViewController();
    await _c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _c.setNavigationDelegate(NavigationDelegate(
      onPageFinished: onPageFinished,
      onWebResourceError: (e) => onError('${e.errorCode} ${e.description} ${e.url}'),
    ));
    await _c.setOnConsoleMessage((m) => onConsole(m.level.name, m.message));
    await _c.addJavaScriptChannel(channelName, onMessageReceived: (m) => onMessage(m.message));
    if (userAgent != null) {
      await _c.setUserAgent(userAgent);
      uaApplied = true;
    }
  }

  // Windows: no hay API de consola en el paquete; onConsole no se llama nunca.
  // Canal JS: shim.js encamina webkit.messageHandlers.tf.postMessage a chrome.webview.postMessage.
  Future<void> _initWin(String? userAgent) async {
    final dir = requestedUserDataDir;
    if (dir != null && !_envTried) {
      _envTried = true;
      try {
        await win.WebviewController.initializeEnvironment(userDataPath: dir);
        userDataDirApplied = true;
      } catch (e) {
        userDataDirApplied = false;
        userDataDirError = '$e';
      }
    }
    final w = win.WebviewController();
    _w = w;
    await w.initialize();
    w.webMessage.listen((v) => onMessage(v is String ? v : jsonEncode(v)), onError: (Object e) => onError('webMessage: $e'));
    w.url.listen((u) => _lastUrl = u);
    w.loadingState.listen((s) {
      if (s == win.LoadingState.navigationCompleted) onPageFinished(_lastUrl);
    });
    w.onLoadError.listen((e) => onError('onLoadError ${e.name}'));
    if (userAgent != null) {
      await w.setUserAgent(userAgent);
      uaApplied = true;
    }
  }

  /// macOS: loadFlutterAsset y, si falla, loadFile sobre flutter_assets del .app.
  /// Windows: host virtual https://tf.assets sobre data\flutter_assets junto al exe.
  Future<void> loadAsset(String key) async {
    final w = _w;
    if (w != null) {
      if (!_mapped) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        await w.addVirtualHostNameMapping('tf.assets', '$exeDir\\data\\flutter_assets', win.WebviewHostResourceAccessKind.allow);
        _mapped = true;
      }
      await w.loadUrl('https://tf.assets/$key');
      serving = 'virtual host https://tf.assets → flutter_assets';
      return;
    }
    try {
      await _c.loadFlutterAsset(key);
      serving = 'loadFlutterAsset (file://, lectura concedida a la carpeta del asset)';
    } catch (e) {
      final root = File(Platform.resolvedExecutable).parent.parent.path;
      await _c.loadFile('$root/Frameworks/App.framework/Resources/flutter_assets/$key');
      serving = 'loadFile en flutter_assets (loadFlutterAsset fallo: $e)';
    }
  }

  Future<void> loadHtml(String html) => _w?.loadStringContent(html) ?? _c.loadHtmlString(html);
  Future<void> loadUrl(String url) => _w?.loadUrl(url) ?? _c.loadRequest(Uri.parse(url));
  Future<void> run(String js) => _w != null ? _w!.executeScript(js) : _c.runJavaScript(js);

  Future<String> eval(String js) async {
    final w = _w;
    if (w != null) {
      final r = await w.executeScript(js);
      return r is String ? r : jsonEncode(r);
    }
    return (await _c.runJavaScriptReturningResult(js)).toString();
  }

  Future<String> userAgentFromPlugin() async => _w != null ? eval('navigator.userAgent') : '${await _c.getUserAgent()}';

  /// Sesion fuera de arbol que ofrece el paquete (si la ofrece).
  Future<String> offscreenSupport() async => 'n/a';

  Widget widget() => _w != null ? win.Webview(_w!) : WebViewWidget(controller: _c);
}
